import 'reflect-metadata';
import { ValidationPipe } from '@nestjs/common';
import { plainToInstance } from 'class-transformer';
import { validate } from 'class-validator';
import { CategorySuggestionDto } from './category-suggestion.dto';
import { DuplicateSuggestionsDto } from './duplicate-suggestions.dto';

async function errorsFor<T extends object>(
  type: new () => T,
  payload: Record<string, unknown>,
) {
  return validate(plainToInstance(type, payload));
}

describe('ML suggestion request validation', () => {
  it('accepts a normal category description and trims it', async () => {
    const dto = plainToInstance(CategorySuggestionDto, {
      description: '  Water is leaking under the sink.  ',
    });

    expect(dto.description).toBe('Water is leaking under the sink.');
    await expect(validate(dto)).resolves.toHaveLength(0);
  });

  it('rejects missing, blank, too-short, and oversized descriptions', async () => {
    for (const payload of [
      {},
      { description: '   ' },
      { description: 'leak' },
      { description: 'x'.repeat(4_001) },
      { description: 42 },
    ]) {
      const errors = await errorsFor(CategorySuggestionDto, payload);
      expect(errors.length).toBeGreaterThan(0);
    }
  });

  it('rejects identity and role fields through the global whitelist', async () => {
    const pipe = new ValidationPipe({
      whitelist: true,
      transform: true,
      forbidNonWhitelisted: true,
    });

    await expect(
      pipe.transform(
        {
          description: 'Water is leaking under the sink.',
          studentId: '4301',
          role: 'ADMIN',
        },
        { type: 'body', metatype: CategorySuggestionDto },
      ),
    ).rejects.toThrow();
  });

  it('accepts optional candidate limits and rejects out-of-range values', async () => {
    await expect(
      errorsFor(DuplicateSuggestionsDto, { maxCandidates: 5 }),
    ).resolves.toHaveLength(0);
    await expect(errorsFor(DuplicateSuggestionsDto, {})).resolves.toHaveLength(0);

    for (const maxCandidates of [0, 21, 2.5, 'many']) {
      const errors = await errorsFor(DuplicateSuggestionsDto, { maxCandidates });
      expect(errors.length).toBeGreaterThan(0);
    }
  });
});
