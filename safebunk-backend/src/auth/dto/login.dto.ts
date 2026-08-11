import { ApiProperty } from '@nestjs/swagger';
import { IsString, MinLength } from 'class-validator';

export class LoginDto {
  @ApiProperty({ example: 'BCA24XXX', description: 'Linways student username' })
  @IsString()
  @MinLength(3)
  username: string;

  @ApiProperty({ example: '********', description: 'Linways student password' })
  @IsString()
  @MinLength(3)
  password: string;
}
