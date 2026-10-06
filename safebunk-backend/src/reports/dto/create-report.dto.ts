import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsIn,
  IsOptional,
  IsString,
  MaxLength,
  MinLength,
} from 'class-validator';
import { ALL_REPORT_PRIORITIES } from '../report-status';

export class CreateReportDto {
  @ApiProperty({ example: 'Water Leakage' })
  @IsString()
  @MinLength(3)
  @MaxLength(160)
  title: string;

  @ApiProperty({ example: 'Water leaking from the ceiling near the electrical panel.' })
  @IsString()
  @MinLength(10)
  @MaxLength(4000)
  description: string;

  @ApiPropertyOptional({ example: 'Infrastructure' })
  @IsOptional()
  @IsString()
  @MaxLength(80)
  category?: string;

  @ApiPropertyOptional({ example: 'Block B · 2nd Floor' })
  @IsOptional()
  @IsString()
  @MaxLength(160)
  location?: string;

  @ApiPropertyOptional({ enum: ALL_REPORT_PRIORITIES, default: 'MEDIUM' })
  @IsOptional()
  @IsIn([...ALL_REPORT_PRIORITIES])
  priority?: string;

  @ApiPropertyOptional({ description: 'URL of an uploaded photo (Phase 3)' })
  @IsOptional()
  @IsString()
  @MaxLength(512)
  imageUrl?: string;

  // NOTE: no studentId field. Global ValidationPipe runs with
  // whitelist + forbidNonWhitelisted, so a client-supplied studentId is
  // rejected outright. Ownership comes only from the AuthGuard session.
}
