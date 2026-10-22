import { Injectable, Logger } from '@nestjs/common';
import {
  OnGatewayConnection,
  OnGatewayDisconnect,
  OnGatewayInit,
  WebSocketGateway,
} from '@nestjs/websockets';
import { randomUUID } from 'crypto';
import { Namespace, Socket } from 'socket.io';
import { AuthService } from '../auth/auth.service';
import { isStaffRole, Session } from '../auth/session.types';
import { PrismaService } from '../prisma/prisma.service';

export const REPORT_CHANGED_EVENT = 'report:changed';

export type ReportChangeType =
  | 'created'
  | 'assigned'
  | 'reassigned'
  | 'accepted'
  | 'progress'
  | 'resolved'
  | 'rejected';

export interface ReportChangedEvent {
  eventId: string;
  reportId: string;
  code: string;
  status: string;
  change: ReportChangeType;
  occurredAt: string;
}

export interface PublishReportChangedInput {
  reportId: string;
  code: string;
  status: string;
  change: ReportChangeType;
  studentId: string;
  assignedStaffId?: string | null;
  previousAssignedStaffId?: string | null;
  notifyStudent?: boolean;
}

interface ReportSocketData {
  reportSession?: Session;
  authCheckTimer?: NodeJS.Timeout;
}

const ADMIN_ROOM = 'admin';
const SESSION_CHECK_INTERVAL_MS = 60_000;

/**
 * Real-time report notifications.
 *
 * Security model:
 * - The connection is authenticated during the Socket.IO handshake with the
 *   same Bearer session token used by the REST API.
 * - Rooms are assigned by the server from that verified session. Clients cannot
 *   choose or join a room, so a student can never subscribe to another
 *   student's updates and staff cannot subscribe to unassigned work.
 * - Events contain only routing-safe summary fields. Descriptions, photos,
 *   attachment URLs, reporter identity and staff identity never leave the API
 *   through this channel; clients refetch the authorized REST representation.
 */
@WebSocketGateway({
  namespace: '/reports',
  cors: {
    origin: process.env.CORS_ORIGIN || '*',
  },
})
@Injectable()
export class ReportsRealtimeGateway
  implements
    OnGatewayInit<Namespace>,
    OnGatewayConnection<Socket>,
    OnGatewayDisconnect<Socket>
{
  private readonly logger = new Logger(ReportsRealtimeGateway.name);
  private server?: Namespace;

  constructor(
    private readonly authService: AuthService,
    private readonly prisma: PrismaService,
  ) {}

  afterInit(server: Namespace): void {
    this.server = server;
    server.use((socket, next) => {
      void this.authenticate(socket)
        .then(async (session) => {
          socket.data.reportSession = session;
          // Join before the namespace handshake completes so no event can slip
          // through between the client's first REST resync and room membership.
          await socket.join(this.roomFor(session));
          next();
        })
        .catch(() => next(new Error('Unauthorized')));
    });
  }

  handleConnection(client: Socket): void {
    const session = (client.data as ReportSocketData).reportSession;
    if (!session) {
      client.disconnect(true);
      return;
    }

    if (client.connected === false) return;

    // A session can expire or a staff account can be deactivated while the
    // socket is open. Revalidate periodically so an old socket cannot keep
    // receiving updates after REST access has been revoked.
    const timer = setInterval(() => {
      void this.revalidate(client).catch((error: unknown) => {
        this.logger.warn(
          `Report socket session check failed: ${
            error instanceof Error ? error.message : String(error)
          }`,
        );
      });
    }, SESSION_CHECK_INTERVAL_MS);
    timer.unref?.();
    (client.data as ReportSocketData).authCheckTimer = timer;
  }

  handleDisconnect(client: Socket): void {
    const timer = (client.data as ReportSocketData).authCheckTimer;
    if (timer) clearInterval(timer);
  }

  /**
   * Emits a report summary change after the database operation has committed.
   * The owning student, the currently assigned staff member, a previous
   * assignee (so a reassigned queue drops the item), and every admin are the
   * only possible recipients.
   */
  publishReportChanged(input: PublishReportChangedInput): void {
    if (!this.server) return;

    const event: ReportChangedEvent = {
      eventId: randomUUID(),
      reportId: input.reportId,
      code: input.code,
      status: input.status,
      change: input.change,
      occurredAt: new Date().toISOString(),
    };

    const rooms = new Set<string>([ADMIN_ROOM]);
    if (input.notifyStudent !== false) {
      rooms.add(this.studentRoom(input.studentId));
    }
    if (input.assignedStaffId) {
      rooms.add(this.staffRoom(input.assignedStaffId));
    }
    if (
      input.previousAssignedStaffId &&
      input.previousAssignedStaffId !== input.assignedStaffId
    ) {
      rooms.add(this.staffRoom(input.previousAssignedStaffId));
    }

    try {
      for (const room of rooms) {
        this.server.to(room).emit(REPORT_CHANGED_EVENT, event);
      }
    } catch (error) {
      // A real-time delivery failure must never turn an already-committed REST
      // operation into a failed request. Clients resync on their next connect.
      this.logger.warn(
        `Failed to publish report change: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }
  }

  private async authenticate(client: Socket): Promise<Session> {
    const token = this.extractToken(client);
    if (!token) throw new Error('Missing session');

    const session = await this.authenticateToken(token);
    if (!session) throw new Error('Invalid session');
    return session;
  }

  private async authenticateToken(token: string): Promise<Session | null> {
    const session = this.authService.validateSession(token);
    if (!session) return null;

    if (session.role === 'STAFF' || session.role === 'ADMIN') {
      const account = await this.prisma.staffUser.findUnique({
        where: { id: session.staffId },
        select: { active: true, role: true },
      });
      if (
        !account ||
        !account.active ||
        !isStaffRole(account.role) ||
        account.role !== session.role
      ) {
        return null;
      }
    }

    return session;
  }

  private async revalidate(client: Socket): Promise<void> {
    const data = client.data as ReportSocketData;
    const token = data.reportSession?.token;
    if (!token) {
      client.disconnect(true);
      return;
    }

    const session = await this.authenticateToken(token);
    if (!session) {
      client.emit('reports:error', { code: 'session_expired' });
      client.disconnect(true);
      return;
    }
    data.reportSession = session;
  }

  private extractToken(client: Socket): string | null {
    const authToken = client.handshake.auth?.token;
    if (typeof authToken === 'string' && authToken.trim()) {
      return authToken.trim();
    }

    const header = client.handshake.headers?.authorization;
    if (typeof header === 'string' && header.startsWith('Bearer ')) {
      return header.slice(7).trim() || null;
    }

    return null;
  }

  private roomFor(session: Session): string {
    if (session.role === 'STUDENT') return this.studentRoom(session.studentId);
    if (session.role === 'ADMIN') return ADMIN_ROOM;
    return this.staffRoom(session.staffId);
  }

  private studentRoom(studentId: string): string {
    return `student:${studentId}`;
  }

  private staffRoom(staffId: string): string {
    return `staff:${staffId}`;
  }
}
