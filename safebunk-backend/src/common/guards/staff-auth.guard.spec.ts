import {
  ForbiddenException,
  UnauthorizedException,
  ExecutionContext,
} from '@nestjs/common';
import { StaffAuthGuard } from './staff-auth.guard';

function makeContext(authorization?: string) {
  const request: any = {
    headers: authorization ? { authorization } : {},
  };
  const context = {
    switchToHttp: () => ({ getRequest: () => request }),
  } as unknown as ExecutionContext;
  return { request, context };
}

function makeGuard(session: any, account: any = null) {
  const auth = { validateSession: jest.fn(() => session) };
  const prisma = {
    staffUser: {
      findUnique: jest.fn(async () => account),
    },
  };
  return { guard: new StaffAuthGuard(auth as any, prisma as any), auth, prisma };
}

const staffSession = {
  token: 'staff-token',
  role: 'STAFF',
  staffId: 'staff-1',
  username: 'maintenance.ravi',
  createdAt: Date.now(),
};

const adminSession = {
  token: 'admin-token',
  role: 'ADMIN',
  staffId: 'admin-1',
  username: 'campus.admin',
  createdAt: Date.now(),
};

describe('StaffAuthGuard (staff/admin routes)', () => {
  it('rejects unauthenticated requests with 401', async () => {
    const { guard } = makeGuard(null);
    const { context } = makeContext();

    await expect(guard.canActivate(context)).rejects.toThrow(
      UnauthorizedException,
    );
  });

  it('rejects an invalid or expired token with 401', async () => {
    const { guard } = makeGuard(null);
    const { context } = makeContext('Bearer expired-token');

    await expect(guard.canActivate(context)).rejects.toThrow(
      UnauthorizedException,
    );
  });

  it('denies a valid student token with 403 before touching staff accounts', async () => {
    const { guard, prisma } = makeGuard({
      token: 'student-token',
      role: 'STUDENT',
      studentId: '4301',
      username: 'student',
      cookies: 'session=abc',
      authToken: 'linways-token',
      createdAt: Date.now(),
    });
    const { context, request } = makeContext('Bearer student-token');

    await expect(guard.canActivate(context)).rejects.toThrow(
      ForbiddenException,
    );
    expect(prisma.staffUser.findUnique).not.toHaveBeenCalled();
    expect(request.user).toBeUndefined();
  });

  it('allows a valid staff session and exposes the staff identity', async () => {
    const { guard, prisma } = makeGuard(staffSession, {
      active: true,
      role: 'STAFF',
    });
    const { context, request } = makeContext('Bearer staff-token');

    await expect(guard.canActivate(context)).resolves.toBe(true);
    expect(prisma.staffUser.findUnique).toHaveBeenCalledWith({
      where: { id: 'staff-1' },
      select: { active: true, role: true },
    });
    expect(request.user).toEqual({
      staffId: 'staff-1',
      username: 'maintenance.ravi',
      role: 'STAFF',
    });
  });

  it('allows a valid admin session', async () => {
    const { guard } = makeGuard(adminSession, {
      active: true,
      role: 'ADMIN',
    });
    const { context, request } = makeContext('Bearer admin-token');

    await expect(guard.canActivate(context)).resolves.toBe(true);
    expect(request.user.role).toBe('ADMIN');
  });

  it('rejects an inactive account even when the token is still unexpired', async () => {
    const { guard } = makeGuard(staffSession, {
      active: false,
      role: 'STAFF',
    });
    const { context } = makeContext('Bearer staff-token');

    await expect(guard.canActivate(context)).rejects.toThrow(
      UnauthorizedException,
    );
  });

  it('rejects a deleted account', async () => {
    const { guard } = makeGuard(staffSession);
    const { context } = makeContext('Bearer staff-token');

    await expect(guard.canActivate(context)).rejects.toThrow(
      UnauthorizedException,
    );
  });

  it('rejects a session after the account role changes', async () => {
    const { guard } = makeGuard(adminSession, {
      active: true,
      role: 'STAFF',
    });
    const { context } = makeContext('Bearer admin-token');

    await expect(guard.canActivate(context)).rejects.toThrow(
      UnauthorizedException,
    );
  });

  it('rejects a malformed account role instead of trusting the session role', async () => {
    const { guard } = makeGuard(adminSession, {
      active: true,
      role: 'SUPERUSER',
    });
    const { context } = makeContext('Bearer admin-token');

    await expect(guard.canActivate(context)).rejects.toThrow(
      UnauthorizedException,
    );
  });
});
