import { Body, Controller, Get, Param, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AuthGuard } from '../common/guards/auth.guard';
import { CurrentUser, AuthenticatedUser } from '../common/decorators/current-user.decorator';
import { ApiResponse } from '../common/dto/api-response.dto';
import { CreateReportDto } from './dto/create-report.dto';
import { ReportsService } from './reports.service';

@ApiTags('Reports')
@Controller('reports')
@UseGuards(AuthGuard)
@ApiBearerAuth()
export class ReportsController {
  constructor(private readonly reportsService: ReportsService) {}

  @Post()
  @ApiOperation({ summary: 'Create a campus issue report (student)' })
  async createReport(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: CreateReportDto,
  ): Promise<ApiResponse<unknown>> {
    const report = await this.reportsService.createReport(user.studentId, dto);
    return ApiResponse.ok(report, 'Report created');
  }

  @Get('my')
  @ApiOperation({ summary: 'List my reports' })
  async listMyReports(@CurrentUser() user: AuthenticatedUser): Promise<ApiResponse<unknown>> {
    const reports = await this.reportsService.listMyReports(user.studentId);
    return ApiResponse.ok(reports);
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get a report I own' })
  async getReport(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id') id: string,
  ): Promise<ApiResponse<unknown>> {
    const report = await this.reportsService.getOwnedReport(user.studentId, id);
    return ApiResponse.ok(report);
  }
}
