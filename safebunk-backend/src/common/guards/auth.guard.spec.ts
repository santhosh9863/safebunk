import {
  ForbiddenException,
  UnauthorizedException,
  ExecutionContext,
} from '@nestjs/common';
import { AuthGuard } from './auth.guard';

function makeContext(authorization?: string) {
  const request: any = {
    headers: authorization ? { authorization } : {},
  };
  const context = {
    switchToHttp: () => ({ getRequest: () => request }),
  } as unknown as ExecutionContext;
  return { request, context };
}

function makeGuard(session: any) {
  const auth = { validateSession: jest.fn(() => session) };
  return { guard: new AuthGuard(auth as any), auth };
}

describe('AuthGuard (student routes)', () => {
  it('rejects unauthenticated requests with 401', () => {
    const { guard } = makeGuard(null);
    const { context } = makeContext();

    expect(() => guard.canActivate(context)).toThrow(UnauthorizedException);
  });

  it('rejects an invalid or expired token with 401', () => {
    const { guard } = makeGuard(null);
    const { context } = makeContext('Bearer expired-token');

    expect(() => guard.canActivate(context)).toThrow(UnauthorizedException);
  });

  it('allows a student session and exposes only the student identity', () => {
    const { guard } = makeGuard({
      token: 'student-token',
      role: 'STUDENT',
      studentId: '4301',
      username: 'student',
      cookies: 'session=abc',
      authToken: 'linways-token',
      createdAt: Date.now(),
    });
    const { context, request } = makeContext('Bearer student-token');

    expect(guard.canActivate(context)).toBe(true);
    expect(request.user).toEqual({
      role: 'STUDENT',
      studentId: '4301',
      username: 'student',
      cookies: 'session=abc',
    });
  });

  it('denies a valid staff/admin token on student-only routes with 403', () => {
    const { guard } = makeGuard({
      token: 'staff-token',
      role: 'STAFF',
      staffId: 'staff-1',
      username: 'maintenance.ravi',
      createdAt: Date.now(),
    });
    const { context, request } = makeContext('Bearer staff-token');

    expect(() => guard.canActivate(context)).toThrow(ForbiddenException);
    expect(request.user).toBeUndefined();
  });

  it('denies a valid admin token on student-only routes with 403', () => {
    const { guard } = makeGuard({
      token: 'admin-token',
      role: 'ADMIN',
      staffId: 'admin-1',
      username: 'campus.admin',
      createdAt: Date.now(),
    });
    const { context } = makeContext('Bearer admin-token');

    expect(() => guard.canActivate(context)).toThrow(ForbiddenException);
  });
});
