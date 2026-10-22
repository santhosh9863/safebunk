import { GUARDS_METADATA } from '@nestjs/common/constants';
import { AuthGuard } from '../common/guards/auth.guard';
import { StaffAuthGuard } from '../common/guards/staff-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { ROLES_KEY } from '../common/decorators/roles.decorator';
import { MlController } from './ml.controller';
import { StaffMlController } from './staff-ml.controller';

describe('ML route authorization wiring', () => {
  it('puts student ML suggestions behind the student-only guard', () => {
    expect(Reflect.getMetadata(GUARDS_METADATA, MlController)).toEqual([
      AuthGuard,
    ]);
  });

  it('requires staff authentication and a staff/admin role for staff ML routes', () => {
    expect(Reflect.getMetadata(GUARDS_METADATA, StaffMlController)).toEqual([
      StaffAuthGuard,
      RolesGuard,
    ]);
    expect(Reflect.getMetadata(ROLES_KEY, StaffMlController)).toEqual([
      'STAFF',
      'ADMIN',
    ]);
  });

  it('does not expose the internal ML service without a PULSE session', () => {
    expect(Reflect.getMetadata(GUARDS_METADATA, MlController)).not.toEqual([]);
    expect(
      Reflect.getMetadata(GUARDS_METADATA, StaffMlController),
    ).not.toEqual([]);
  });
});
