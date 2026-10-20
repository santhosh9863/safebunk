import { ApiProperty } from '@nestjs/swagger';
import { IsString, MaxLength, MinLength } from 'class-validator';

/**
 * Staff login accepts credentials only. Role is never accepted from the
 * client; it is read from the StaffUser row after password verification.
 */
export class StaffLoginDto {
  @ApiProperty({ example: 'campus.admin' })
  @IsString()
  @MinLength(3)
  @MaxLength(64)
  username: string;

  @ApiProperty({ example: '********' })
  @IsString()
  @MinLength(1)
  @MaxLength(256)
  password: string;
}
