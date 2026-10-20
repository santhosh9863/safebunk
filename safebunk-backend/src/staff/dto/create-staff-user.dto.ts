import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsIn,
  IsOptional,
  IsString,
  Matches,
  MaxLength,
  MinLength,
} from 'class-validator';
import { STAFF_ROLES, StaffRole } from '../../auth/session.types';
import {
  STAFF_PASSWORD_MAX_LENGTH,
  STAFF_PASSWORD_MIN_LENGTH,
  STAFF_USERNAME_MAX_LENGTH,
  STAFF_USERNAME_MIN_LENGTH,
} from '../staff.types';

/**
 * Admin-only account provisioning. The acting admin's role comes from their
 * authenticated session; this DTO is only used after RolesGuard allows ADMIN.
 */
export class CreateStaffUserDto {
  @ApiProperty({ example: 'maintenance.ravi' })
  @IsString()
  @MinLength(STAFF_USERNAME_MIN_LENGTH)
  @MaxLength(STAFF_USERNAME_MAX_LENGTH)
  @Matches(/^[A-Za-z0-9._-]+$/, {
    message: 'username may contain letters, numbers, dots, underscores and hyphens',
  })
  username: string;

  @ApiProperty({ example: 'a long unique password' })
  @IsString()
  @MinLength(STAFF_PASSWORD_MIN_LENGTH)
  @MaxLength(STAFF_PASSWORD_MAX_LENGTH)
  password: string;

  @ApiPropertyOptional({ example: 'Ravi Kumar' })
  @IsOptional()
  @IsString()
  @MaxLength(120)
  displayName?: string;

  @ApiProperty({ enum: [...STAFF_ROLES] })
  @IsIn([...STAFF_ROLES])
  role: StaffRole;
}
