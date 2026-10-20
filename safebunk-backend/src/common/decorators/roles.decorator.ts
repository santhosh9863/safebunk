import { SetMetadata } from '@nestjs/common';
import { StaffRole } from '../../auth/session.types';

export const ROLES_KEY = 'pulse_staff_roles';

/**
 * Restricts a staff-authenticated route to the listed roles.
 * Must be used together with StaffAuthGuard.
 */
export const Roles = (...roles: StaffRole[]) => SetMetadata(ROLES_KEY, roles);
