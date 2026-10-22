import {
  Body,
  Controller,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiParam,
  ApiTags,
} from '@nestjs/swagger';
import { AuthGuard } from '../common/guards/auth.guard';
import {
  AuthenticatedUser,
  CurrentUser,
} from '../common/decorators/current-user.decorator';
import { ApiResponse } from '../common/dto/api-response.dto';
import { DEFAULT_MAX_DUPLICATE_CANDIDATES } from './ml.constants';
import { CategorySuggestionDto } from './dto/category-suggestion.dto';
import { DraftDuplicateSuggestionsDto } from './dto/draft-duplicate-suggestions.dto';
import { DuplicateSuggestionsDto } from './dto/duplicate-suggestions.dto';
import { MlSuggestionsService } from './ml-suggestions.service';
import {
  CategorySuggestionView,
  DuplicateSuggestionView,
} from './ml.types';

/**
 * Student-facing suggestion endpoints.
 *
 * These routes never mutate a report. Ownership comes from the AuthGuard
 * session; the client cannot supply a student id. The internal ML service is
 * reached only by NestJS and never exposed directly.
 */
@ApiTags('ML Suggestions')
@Controller('ml')
@UseGuards(AuthGuard)
@ApiBearerAuth()
export class MlController {
  constructor(private readonly suggestions: MlSuggestionsService) {}

  @Post('category-suggestion')
  @ApiOperation({
    summary: 'Suggest a category for a draft report description (suggestion only)',
  })
  async categorySuggestion(
    @Body() dto: CategorySuggestionDto,
  ): Promise<ApiResponse<CategorySuggestionView>> {
    const suggestion = await this.suggestions.suggestCategory(dto.description);
    return ApiResponse.ok(suggestion, 'Suggestion only; no report was changed.');
  }

  @Post('duplicate-suggestions/preview')
  @ApiOperation({
    summary: 'Suggest possible duplicates for an unsaved draft (suggestion only)',
    description:
      'Compares draft text with the authenticated student’s earlier reports. ' +
      'No report is created or changed.',
  })
  async draftDuplicateSuggestions(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: DraftDuplicateSuggestionsDto,
  ): Promise<ApiResponse<DuplicateSuggestionView>> {
    const suggestion = await this.suggestions.suggestDuplicatesForDraft(
      user.studentId,
      {
        description: dto.description,
        category: dto.category ?? null,
        location: dto.location ?? null,
        maxCandidates: dto.maxCandidates ?? DEFAULT_MAX_DUPLICATE_CANDIDATES,
      },
    );
    return ApiResponse.ok(
      suggestion,
      suggestion.available
        ? 'Suggestion only; no report was changed.'
        : 'ML suggestions unavailable; no report was changed.',
    );
  }

  @Post('duplicate-suggestions/:reportId')
  @ApiParam({ name: 'reportId', description: 'Id of a report owned by the student' })
  @ApiOperation({
    summary: 'Suggest possible duplicates for one of my reports (suggestion only)',
  })
  async duplicateSuggestions(
    @CurrentUser() user: AuthenticatedUser,
    @Param('reportId') reportId: string,
    @Body() dto: DuplicateSuggestionsDto,
  ): Promise<ApiResponse<DuplicateSuggestionView>> {
    const suggestion = await this.suggestions.suggestDuplicatesForStudent(
      user.studentId,
      reportId,
      dto.maxCandidates,
    );
    return ApiResponse.ok(
      suggestion,
      suggestion.available
        ? 'Suggestion only; no report was changed.'
        : 'ML suggestions unavailable; no report was changed.',
    );
  }
}
