import { ApiProperty } from '@nestjs/swagger';
import { Transform } from 'class-transformer';
import {
  IsString,
  Matches,
  MaxLength,
  MinLength,
} from 'class-validator';

export class CategorySuggestionDto {
  @ApiProperty({
    example: 'Water is leaking from a pipe under the sink.',
    description: 'Report description text only. Do not send identity or role data.',
    minLength: 5,
    maxLength: 4000,
  })
  @Transform(({ value }) => (typeof value === 'string' ? value.trim() : value))
  @IsString()
  @MinLength(5)
  @MaxLength(4000)
  @Matches(/\S/, { message: 'description must not be blank' })
  description: string;
}
