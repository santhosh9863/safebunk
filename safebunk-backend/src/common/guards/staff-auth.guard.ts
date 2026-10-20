import {
  Injectable,
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  UnauthorizedException,
} from '@nestjs/common';
import { AuthService } from '../../auth/auth.service';
import { isStaffRole } from '../../auth/session.types';
import { PrismaService } from '../../prisma/prisma.service';
import { AuthenticatedStaff } from '../decorators/current-user.decorator';

/**
 * Staff/admin-only authentication boundary.
 *
 * A valid student token is authenticated but not authorized here, so it gets
 * 403 rather than 401. Missing/expired tokens still get 401.
 *
 * Staff sessions are revalidated against the StaffUser row on every request.
 * A deleted/deactivated account, or a role change, invalidates an existing
 * token immediately instead of leaving it usable until the 24-hour session TTL.
 */
@Injectable()
export class StaffAuthGuard implements CanActivate {
  constructor(
    private readonly authService: AuthService,
    private readonly prisma: PrismaService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest();
    const authHeader = request.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      throw new UnauthorizedException('Missing or invalid authorization header');
    }

    const token = authHeader.slice(7);
    const session = this.authService.validateSession(token);

    if (!session) {
      throw new UnauthorizedException('Session expired or invalid');
    }

    if (session.role !== 'STAFF' && session.role !== 'ADMIN') {
      throw new ForbiddenException('Staff access required');
    }

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
      throw new UnauthorizedException('Session expired or invalid');
    }

    request.user = {
      staffId: session.staffId,
      username: session.username,
      role: account.role,
    } as AuthenticatedStaff;

    return true;
  }
}
