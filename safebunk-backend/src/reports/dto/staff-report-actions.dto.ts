import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsIn,
  IsNotEmpty,
  IsOptional,
  IsString,
  MaxLength,
  MinLength,
} from 'class-validator';
import { ALL_REPORT_STATUSES } from '../report-status';

export class StaffReportListQueryDto {
  @ApiPropertyOptional({ enum: ALL_REPORT_STATUSES })
  @IsOptional()
  @IsIn([...ALL_REPORT_STATUSES])
  status?: string;
}

export class AssignReportDto {
  @ApiProperty({
    description: 'Id of an active STAFF account. ADMIN accounts are not assignees.',
  })
  @IsString()
  @IsNotEmpty()
  @MaxLength(64)
  staffId: string;

  @ApiPropertyOptional({
    description:
      'Optional department label. Stored on the report for display and routing.',
    example: 'Maintenance',
  })
  @IsOptional()
  @IsString()
  @MaxLength(120)
  department?: string;
}

export class AddProgressNoteDto {
  @ApiProperty({ example: 'Parts ordered; repair scheduled for tomorrow.' })
  @IsString()
  @MinLength(1)
  @MaxLength(2000)
  note: string;
}

export class ResolveReportDto {
  @ApiProperty({ example: 'Replaced the faulty valve and verified no leakage.' })
  @IsString()
  @MinLength(3)
  @MaxLength(4000)
  resolutionNotes: string;
}

export class RejectReportDto {
  @ApiProperty({
    example: 'Duplicate report; the issue was already fixed under PULSE-1042.',
  })
  @IsString()
  @MinLength(3)
  @MaxLength(1000)
  reason: string;
}
