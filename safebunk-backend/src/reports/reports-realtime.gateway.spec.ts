import {
  REPORT_CHANGED_EVENT,
  ReportsRealtimeGateway,
} from './reports-realtime.gateway';

const STUDENT_SESSION = {
  token: 'student-token',
  role: 'STUDENT' as const,
  studentId: 'student_1',
  username: 'student.one',
  cookies: 'cookies',
  authToken: 'linways-token',
  createdAt: Date.now(),
};

const STAFF_SESSION = {
  token: 'staff-token',
  role: 'STAFF' as const,
  staffId: 'staff_1',
  username: 'staff.one',
  createdAt: Date.now(),
};

const ADMIN_SESSION = {
  token: 'admin-token',
  role: 'ADMIN' as const,
  staffId: 'admin_1',
  username: 'admin.one',
  createdAt: Date.now(),
};

interface FakeSocket {
  handshake: {
    auth: Record<string, unknown>;
    headers: Record<string, string>;
  };
  data: Record<string, unknown>;
  join: jest.Mock;
  disconnect: jest.Mock;
  emit: jest.Mock;
}

function fakeSocket(token?: string): FakeSocket {
  return {
    handshake: {
      auth: token ? { token } : {},
      headers: token ? { authorization: `Bearer ${token}` } : {},
    },
    data: {},
    join: jest.fn().mockResolvedValue(undefined),
    disconnect: jest.fn(),
    emit: jest.fn(),
  };
}

describe('ReportsRealtimeGateway', () => {
  let auth: { validateSession: jest.Mock };
  let prisma: { staffUser: { findUnique: jest.Mock } };
  let gateway: ReportsRealtimeGateway;

  beforeEach(() => {
    auth = { validateSession: jest.fn() };
    prisma = { staffUser: { findUnique: jest.fn() } };
    gateway = new ReportsRealtimeGateway(auth as any, prisma as any);
  });

  async function installMiddleware(): Promise<{
    run: (socket: FakeSocket) => Promise<Error | undefined>;
    server: { use: jest.Mock; to: jest.Mock };
  }> {
    let middleware:
      ((socket: FakeSocket, next: (error?: Error) => void) => void) | undefined;
    const server = {
      use: jest.fn((fn) => {
        middleware = fn;
      }),
      to: jest.fn(),
    };
    gateway.afterInit(server as any);
    return {
      server,
      run: (socket) =>
        new Promise((resolve) => {
          if (!middleware) throw new Error('Middleware was not installed');
          middleware(socket, resolve);
        }),
    };
  }

  it('rejects a missing or invalid session during the handshake', async () => {
    const { run } = await installMiddleware();

    await expect(run(fakeSocket())).resolves.toBeInstanceOf(Error);

    auth.validateSession.mockReturnValue(null);
    const invalid = await run(fakeSocket('expired-token'));
    expect(invalid).toBeInstanceOf(Error);
    expect(invalid?.message).toBe('Unauthorized');
  });

  it('accepts a valid student session from the auth payload', async () => {
    const { run } = await installMiddleware();
    auth.validateSession.mockReturnValue(STUDENT_SESSION);
    const socket = fakeSocket('student-token');

    await expect(run(socket)).resolves.toBeUndefined();
    expect(auth.validateSession).toHaveBeenCalledWith('student-token');
    expect(socket.data.reportSession).toBe(STUDENT_SESSION);
  });

  it('accepts a Bearer token from the handshake headers', async () => {
    const { run } = await installMiddleware();
    auth.validateSession.mockReturnValue(STUDENT_SESSION);
    const socket = fakeSocket();
    socket.handshake.headers.authorization = 'Bearer student-token';

    await expect(run(socket)).resolves.toBeUndefined();
    expect(auth.validateSession).toHaveBeenCalledWith('student-token');
  });

  it('rejects inactive staff and staff whose role changed', async () => {
    const { run } = await installMiddleware();
    auth.validateSession.mockReturnValue(STAFF_SESSION);

    prisma.staffUser.findUnique.mockResolvedValue({
      active: false,
      role: 'STAFF',
    });
    await expect(run(fakeSocket('staff-token'))).resolves.toBeInstanceOf(Error);

    prisma.staffUser.findUnique.mockResolvedValue({
      active: true,
      role: 'ADMIN',
    });
    await expect(run(fakeSocket('staff-token'))).resolves.toBeInstanceOf(Error);
  });

  it('revalidates active staff and assigns the staff room on connect', async () => {
    const { run } = await installMiddleware();
    auth.validateSession.mockReturnValue(STAFF_SESSION);
    prisma.staffUser.findUnique.mockResolvedValue({
      active: true,
      role: 'STAFF',
    });

    const socket = fakeSocket('staff-token');
    await expect(run(socket)).resolves.toBeUndefined();
    await gateway.handleConnection(socket as any);

    expect(socket.join).toHaveBeenCalledWith('staff:staff_1');
    gateway.handleDisconnect(socket as any);
  });

  it('assigns the admin room to an admin and the student room to a student', async () => {
    const { run } = await installMiddleware();
    auth.validateSession.mockReturnValue(ADMIN_SESSION);
    prisma.staffUser.findUnique.mockResolvedValue({
      active: true,
      role: 'ADMIN',
    });

    const adminSocket = fakeSocket('admin-token');
    await run(adminSocket);
    await gateway.handleConnection(adminSocket as any);
    expect(adminSocket.join).toHaveBeenCalledWith('admin');
    gateway.handleDisconnect(adminSocket as any);

    auth.validateSession.mockReturnValue(STUDENT_SESSION);
    const studentSocket = fakeSocket('student-token');
    await run(studentSocket);
    await gateway.handleConnection(studentSocket as any);
    expect(studentSocket.join).toHaveBeenCalledWith('student:student_1');
    gateway.handleDisconnect(studentSocket as any);
  });

  it('routes events only to the owner, current/previous assignee, and admins', async () => {
    // A client cannot choose a room: the gateway assigns exactly these recipient
    // rooms from database identity. There is deliberately no subscribe handler.
    const { server } = await installMiddleware();
    const emit = jest.fn();
    server.to.mockReturnValue({ emit });

    gateway.publishReportChanged({
      reportId: 'report_1',
      code: 'PULSE-1042',
      status: 'IN_PROGRESS',
      change: 'reassigned',
      studentId: 'student_1',
      assignedStaffId: 'staff_new',
      previousAssignedStaffId: 'staff_old',
    });

    const rooms = server.to.mock.calls.map(([room]) => room);
    expect(new Set(rooms)).toEqual(
      new Set([
        'admin',
        'student:student_1',
        'staff:staff_new',
        'staff:staff_old',
      ]),
    );
    expect(rooms).not.toContain('student:student_2');
    expect(rooms).not.toContain('');
    expect(emit).toHaveBeenCalledTimes(4);
    expect(emit).toHaveBeenCalledWith(REPORT_CHANGED_EVENT, expect.any(Object));

    const payload = emit.mock.calls[0][1];
    expect(payload).toMatchObject({
      reportId: 'report_1',
      code: 'PULSE-1042',
      status: 'IN_PROGRESS',
      change: 'reassigned',
    });
    expect(payload.eventId).toEqual(expect.any(String));
    expect(Object.keys(payload).sort()).toEqual([
      'change',
      'code',
      'eventId',
      'occurredAt',
      'reportId',
      'status',
    ]);
    expect(payload).not.toHaveProperty('description');
    expect(payload).not.toHaveProperty('title');
    expect(payload).not.toHaveProperty('studentId');
    expect(payload).not.toHaveProperty('assignedStaffId');
  });

  it('disconnects an open socket when its session expires', async () => {
    jest.useFakeTimers();
    try {
      const { run } = await installMiddleware();
      auth.validateSession.mockReturnValue(STUDENT_SESSION);
      const socket = fakeSocket('student-token');
      await run(socket);
      await gateway.handleConnection(socket as any);

      auth.validateSession.mockReturnValue(null);
      jest.advanceTimersByTime(60_000);
      await Promise.resolve();
      await Promise.resolve();
      await Promise.resolve();

      expect(socket.emit).toHaveBeenCalledWith('reports:error', {
        code: 'session_expired',
      });
      expect(socket.disconnect).toHaveBeenCalledWith(true);
      gateway.handleDisconnect(socket as any);
    } finally {
      jest.useRealTimers();
    }
  });

  it('does not notify a student about an internal progress note', async () => {
    const { server } = await installMiddleware();
    const emit = jest.fn();
    server.to.mockReturnValue({ emit });

    gateway.publishReportChanged({
      reportId: 'report_1',
      code: 'PULSE-1042',
      status: 'ASSIGNED',
      change: 'progress',
      studentId: 'student_1',
      assignedStaffId: 'staff_1',
      notifyStudent: false,
    });

    const rooms = server.to.mock.calls.map(([room]) => room);
    expect(rooms.sort()).toEqual(['admin', 'staff:staff_1']);
    expect(rooms).not.toContain('student:student_1');
    expect(emit).toHaveBeenCalledTimes(2);
  });
});
