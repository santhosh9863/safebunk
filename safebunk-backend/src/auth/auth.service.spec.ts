import { AuthService } from './auth.service';

const now = Date.now();

function makeStore(stored: unknown[] = []) {
  return {
    get: jest.fn(() => stored),
    set: jest.fn(),
  };
}

function makeService(stored: unknown[] = []) {
  const store = makeStore(stored);
  const service = new AuthService({} as any, {} as any, store as any);
  return { service, store };
}

const legacyStudentSession = {
  token: 'legacy-student-token',
  studentId: '4301',
  username: 'student',
  cookies: 'session=abc',
  authToken: 'linways-token',
  createdAt: now,
};

const staffSession = {
  token: 'staff-token',
  role: 'STAFF',
  staffId: 'staff-1',
  username: 'maintenance.ravi',
  createdAt: now,
};

describe('AuthService sessions', () => {
  it('creates and validates a staff session with the server-assigned role', () => {
    const { service } = makeService();

    const session = service.createStaffSession({
      staffId: 'staff-1',
      username: 'maintenance.ravi',
      role: 'STAFF',
    });

    expect(session.role).toBe('STAFF');
    expect(session.staffId).toBe('staff-1');
    expect(service.validateSession(session.token)).toEqual(session);
  });

  it('supports ADMIN staff sessions and keeps them out of student watcher sessions', () => {
    const { service } = makeService([legacyStudentSession]);

    const admin = service.createStaffSession({
      staffId: 'admin-1',
      username: 'campus.admin',
      role: 'ADMIN',
    });

    expect(admin.role).toBe('ADMIN');
    expect(service.getActiveSessions().map((s) => s.token)).toEqual([
      'legacy-student-token',
    ]);
  });

  it('rejects an invalid staff role instead of defaulting to a privileged role', () => {
    const { service } = makeService();

    expect(() =>
      service.createStaffSession({
        staffId: 'staff-1',
        username: 'someone',
        role: 'SUPERUSER' as any,
      }),
    ).toThrow('Cannot create a staff session with an invalid role');
  });

  it('restores legacy student sessions as STUDENT (least privilege)', () => {
    const { service } = makeService([legacyStudentSession]);

    const restored = service.validateSession('legacy-student-token');
    expect(restored?.role).toBe('STUDENT');
    expect(restored).toMatchObject({
      studentId: '4301',
      username: 'student',
    });
  });

  it('restores staff sessions and drops unknown or malformed roles', () => {
    const { service } = makeService([
      staffSession,
      {
        token: 'unknown-role-token',
        role: 'SUPERUSER',
        staffId: 'staff-999',
        username: 'unknown',
        createdAt: now,
      },
      {
        token: 'staff-without-id-token',
        role: 'ADMIN',
        username: 'missing-id',
        createdAt: now,
      },
    ]);

    expect(service.validateSession('staff-token')?.role).toBe('STAFF');
    expect(service.validateSession('unknown-role-token')).toBeNull();
    expect(service.validateSession('staff-without-id-token')).toBeNull();
  });

  it('does not restore expired sessions', () => {
    const { service } = makeService([
      {
        ...legacyStudentSession,
        createdAt: now - 25 * 60 * 60 * 1000,
      },
    ]);

    expect(service.validateSession('legacy-student-token')).toBeNull();
  });
});
