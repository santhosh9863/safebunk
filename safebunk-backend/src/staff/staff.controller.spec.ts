import { StaffController } from './staff.controller';
import { StaffReportsController } from '../reports/staff-reports.controller';
import { ReportsController } from '../reports/reports.controller';
import { ROLES_KEY } from '../common/decorators/roles.decorator';
import { GUARDS_METADATA } from '@nestjs/common/constants';
import { AuthGuard } from '../common/guards/auth.guard';
import { StaffAuthGuard } from '../common/guards/staff-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';

describe('staff route authorization wiring', () => {
  it('puts staff authentication and role checks on staff routes', () => {
    expect(Reflect.getMetadata(GUARDS_METADATA, StaffController)).toEqual([
      StaffAuthGuard,
      RolesGuard,
    ]);
    expect(Reflect.getMetadata(GUARDS_METADATA, StaffReportsController)).toEqual([
      StaffAuthGuard,
      RolesGuard,
    ]);
  });

  it('keeps student report routes behind the student-only guard', () => {
    expect(Reflect.getMetadata(GUARDS_METADATA, ReportsController)).toEqual([
      AuthGuard,
    ]);
  });

  it('allows staff and admin on the staff controller, but admin only for user management', () => {
    expect(Reflect.getMetadata(ROLES_KEY, StaffController)).toEqual([
      'STAFF',
      'ADMIN',
    ]);
    expect(
      Reflect.getMetadata(ROLES_KEY, StaffController.prototype.listStaff),
    ).toEqual(['ADMIN']);
    expect(
      Reflect.getMetadata(ROLES_KEY, StaffController.prototype.createStaff),
    ).toEqual(['ADMIN']);
  });

  it('allows staff and admin on read-only staff report routes', () => {
    expect(Reflect.getMetadata(ROLES_KEY, StaffReportsController)).toEqual([
      'STAFF',
      'ADMIN',
    ]);
  });
});
