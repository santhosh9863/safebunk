import { Body, Controller, Param, Post, UseGuards } from '@nestjs/common';
import {
  ApiBearerAuth,
  ApiOperation,
  ApiParam,
  ApiTags,
} from '@nestjs/swagger';
import { StaffAuthGuard } from '../common/guards/staff-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import {
  AuthenticatedStaff,
  CurrentStaff,
} from '../common/decorators/current-user.decorator';
import { ApiResponse } from '../common/dto/api-response.dto';
import { DuplicateSuggestionsDto } from './dto/duplicate-suggestions.dto';
import { MlSuggestionsService } from './ml-suggestions.service';
import { DuplicateSuggestionView } from './ml.types';

/**
 * Staff/admin duplicate suggestions follow the existing issue-handling
 * visibility rules. STAFF may request suggestions only for their assignments;
 * ADMIN may request them for any report.
 */
@ApiTags('Staff ML Suggestions')
@Controller('staff/ml')
@UseGuards(StaffAuthGuard, RolesGuard)
@Roles('STAFF', 'ADMIN')
@ApiBearerAuth()
export class StaffMlController {
  constructor(private readonly suggestions: MlSuggestionsService) {}

  @Post('duplicate-suggestions/:reportId')
  @ApiParam({ name: 'reportId', description: 'Id of an authorized report' })
  @ApiOperation({
    summary: 'Suggest possible duplicates for an authorized report (suggestion only)',
  })
  async duplicateSuggestions(
    @CurrentStaff() staff: AuthenticatedStaff,
    @Param('reportId') reportId: string,
    @Body() dto: DuplicateSuggestionsDto,
  ): Promise<ApiResponse<DuplicateSuggestionView>> {
    const suggestion = await this.suggestions.suggestDuplicatesForStaff(
      staff,
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
