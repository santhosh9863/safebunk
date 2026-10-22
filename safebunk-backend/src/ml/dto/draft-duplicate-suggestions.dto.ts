import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { Transform, Type } from 'class-transformer';
import {
  IsInt,
  IsOptional,
  IsString,
  Matches,
  Max,
  MaxLength,
  Min,
  MinLength,
} from 'class-validator';
import {
  DEFAULT_MAX_DUPLICATE_CANDIDATES,
  MAX_DUPLICATE_CANDIDATES,
} from '../ml.constants';

function trimString(value: unknown): unknown {
  return typeof value === 'string' ? value.trim() : value;
}

/**
 * Compares an unsaved draft with the authenticated student's earlier reports.
 * Only complaint text/category/location are accepted; identity always comes
 * from the session guard.
 */
export class DraftDuplicateSuggestionsDto {
  @ApiProperty({
    example: 'Water is leaking from a pipe under the sink.',
    description: 'Draft report description text only.',
    minLength: 5,
    maxLength: 4000,
  })
  @Transform(({ value }) => trimString(value))
  @IsString()
  @MinLength(5)
  @MaxLength(4000)
  @Matches(/\S/, { message: 'description must not be blank' })
  description: string;

  @ApiPropertyOptional({
    maxLength: 80,
    description:
      'Optional draft category. Unsupported/free-text values are omitted before ML.',
  })
  @Transform(({ value }) => trimString(value))
  @IsOptional()
  @IsString()
  @MaxLength(80)
  category?: string;

  @ApiPropertyOptional({
    maxLength: 160,
    description: 'Optional draft location.',
  })
  @Transform(({ value }) => trimString(value))
  @IsOptional()
  @IsString()
  @MaxLength(160)
  location?: string;

  @ApiPropertyOptional({
    default: DEFAULT_MAX_DUPLICATE_CANDIDATES,
    minimum: 1,
    maximum: MAX_DUPLICATE_CANDIDATES,
  })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(MAX_DUPLICATE_CANDIDATES)
  maxCandidates?: number;
}
