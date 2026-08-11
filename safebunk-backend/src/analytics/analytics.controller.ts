import { Controller, Get, UseGuards } from '@nestjs/common';
import { ApiOperation, ApiTags, ApiBearerAuth } from '@nestjs/swagger';
import { AuthGuard } from '../common/guards/auth.guard';
import { CurrentUser, AuthenticatedUser } from '../common/decorators/current-user.decorator';
import { AnalyticsService } from './analytics.service';
import { ApiResponse } from '../common/dto/api-response.dto';

@ApiTags('Analytics')
@Controller('analytics')
@UseGuards(AuthGuard)
@ApiBearerAuth()
export class AnalyticsController {
  constructor(private readonly analyticsService: AnalyticsService) {}

  @Get()
  @ApiOperation({ summary: 'Get consolidated attendance analytics' })
  async getAnalytics(@CurrentUser() user: AuthenticatedUser): Promise<ApiResponse<any>> {
    const data = await this.analyticsService.getConsolidatedAnalytics(
      user.studentId,
      user.cookies,
    );
    return ApiResponse.ok(data);
  }

  @Get('hour-wise')
  @ApiOperation({ summary: 'Get hour-wise attendance report' })
  async getHourWiseAttendance(@CurrentUser() user: AuthenticatedUser): Promise<ApiResponse<any>> {
    const data = await this.analyticsService.getHourWiseAttendance(
      user.studentId,
      user.cookies,
    );
    return ApiResponse.ok(data);
  }
}
