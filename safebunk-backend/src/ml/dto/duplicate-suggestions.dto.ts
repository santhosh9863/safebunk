import { ApiPropertyOptional } from '@nestjs/swagger';
import { Type } from 'class-transformer';
import { IsInt, IsOptional, Max, Min } from 'class-validator';
import {
  DEFAULT_MAX_DUPLICATE_CANDIDATES,
  MAX_DUPLICATE_CANDIDATES,
} from '../ml.constants';

export class DuplicateSuggestionsDto {
  @ApiPropertyOptional({
    default: DEFAULT_MAX_DUPLICATE_CANDIDATES,
    minimum: 1,
    maximum: MAX_DUPLICATE_CANDIDATES,
    description: 'Maximum number of ranked duplicate candidates to return.',
  })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(MAX_DUPLICATE_CANDIDATES)
  maxCandidates?: number;
}
