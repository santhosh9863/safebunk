import { ExecutionContext, ForbiddenException } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { RolesGuard } from './roles.guard';
import { ROLES_KEY } from '../decorators/roles.decorator';

function makeContext(user: any, handler: Function, controller: Function) {
  const request = { user };
  return {
    switchToHttp: () => ({ getRequest: () => request }),
    getHandler: () => handler,
    getClass: () => controller,
  } as unknown as ExecutionContext;
}

describe('RolesGuard', () => {
  const guard = new RolesGuard(new Reflector());

  const staffHandler = () => undefined;
  const adminHandler = () => undefined;
  const noRoleHandler = () => undefined;

  class TestController {}
  class AdminController {}
  class NoRoleController {}

  Reflect.defineMetadata(ROLES_KEY, ['STAFF', 'ADMIN'], TestController);
  Reflect.defineMetadata(ROLES_KEY, ['ADMIN'], AdminController);
  Reflect.defineMetadata(ROLES_KEY, ['ADMIN'], adminHandler);
  Reflect.defineMetadata(ROLES_KEY, ['STAFF', 'ADMIN'], staffHandler);

  it('allows STAFF on a staff/admin route', () => {
    const context = makeContext(
      { staffId: 'staff-1', username: 'maintenance.ravi', role: 'STAFF' },
      staffHandler,
      TestController,
    );

    expect(guard.canActivate(context)).toBe(true);
  });

  it('allows ADMIN on a staff/admin route', () => {
    const context = makeContext(
      { staffId: 'admin-1', username: 'campus.admin', role: 'ADMIN' },
      staffHandler,
      TestController,
    );

    expect(guard.canActivate(context)).toBe(true);
  });

  it('denies STAFF on an admin-only route', () => {
    const context = makeContext(
      { staffId: 'staff-1', username: 'maintenance.ravi', role: 'STAFF' },
      adminHandler,
      AdminController,
    );

    expect(() => guard.canActivate(context)).toThrow(ForbiddenException);
  });

  it('allows ADMIN on an admin-only route', () => {
    const context = makeContext(
      { staffId: 'admin-1', username: 'campus.admin', role: 'ADMIN' },
      adminHandler,
      AdminController,
    );

    expect(guard.canActivate(context)).toBe(true);
  });

  it('denies a missing principal on a role-protected route', () => {
    const context = makeContext(undefined, adminHandler, AdminController);

    expect(() => guard.canActivate(context)).toThrow(ForbiddenException);
  });

  it('allows routes with no role requirement', () => {
    const context = makeContext(undefined, noRoleHandler, NoRoleController);

    expect(guard.canActivate(context)).toBe(true);
  });

  it('supports class-level roles and admin-only method overrides', () => {
    const classContext = makeContext(
      { staffId: 'staff-1', username: 'maintenance.ravi', role: 'STAFF' },
      noRoleHandler,
      TestController,
    );
    expect(guard.canActivate(classContext)).toBe(true);

    const overrideContext = makeContext(
      { staffId: 'staff-1', username: 'maintenance.ravi', role: 'STAFF' },
      adminHandler,
      TestController,
    );
    expect(() => guard.canActivate(overrideContext)).toThrow(ForbiddenException);

    const adminOverrideContext = makeContext(
      { staffId: 'admin-1', username: 'campus.admin', role: 'ADMIN' },
      adminHandler,
      TestController,
    );
    expect(guard.canActivate(adminOverrideContext)).toBe(true);
  });
});
