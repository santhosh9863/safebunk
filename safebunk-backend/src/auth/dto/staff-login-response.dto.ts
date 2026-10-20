import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { StaffRole } from '../session.types';

export class StaffIdentityDto {
  @ApiProperty()
  id: string;

  @ApiProperty()
  username: string;

  @ApiPropertyOptional({ nullable: true })
  displayName: string | null;

  @ApiProperty({ enum: ['STAFF', 'ADMIN'] })
  role: StaffRole;
}

export class StaffLoginResponseDto {
  @ApiProperty({ example: '9f1c...' })
  accessToken: string;

  @ApiProperty()
  staff: StaffIdentityDto;
}
