import { Controller, Get, Param, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { StaffAuthGuard } from '../common/guards/staff-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { ApiResponse } from '../common/dto/api-response.dto';
import { ReportsService } from './reports.service';

/**
 * Read-only staff/admin report access. Status/assignment mutations are a
 * later lifecycle milestone; this controller deliberately exposes no writes.
 */
@ApiTags('Staff Reports')
@Controller('staff/reports')
@UseGuards(StaffAuthGuard, RolesGuard)
@Roles('STAFF', 'ADMIN')
@ApiBearerAuth()
export class StaffReportsController {
  constructor(private readonly reportsService: ReportsService) {}

  @Get()
  @ApiOperation({ summary: 'List all reports (staff/admin)' })
  async listReports(): Promise<ApiResponse<unknown>> {
    return ApiResponse.ok(await this.reportsService.listReportsForStaff());
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get any report, regardless of student owner (staff/admin)' })
  async getReport(@Param('id') id: string): Promise<ApiResponse<unknown>> {
    return ApiResponse.ok(await this.reportsService.getReportForStaff(id));
  }
}
