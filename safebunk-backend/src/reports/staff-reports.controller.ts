import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  Query,
  Res,
  StreamableFile,
  UseGuards,
} from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { Response } from 'express';
import { StaffAuthGuard } from '../common/guards/staff-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import {
  AuthenticatedStaff,
  CurrentStaff,
} from '../common/decorators/current-user.decorator';
import { ApiResponse } from '../common/dto/api-response.dto';
import { ReportsService } from './reports.service';
import {
  AddProgressNoteDto,
  AssignReportDto,
  RejectReportDto,
  ResolveReportDto,
  StaffReportListQueryDto,
} from './dto/staff-report-actions.dto';

/**
 * Staff/admin issue handling.
 *
 * - STAFF sees and updates only reports assigned to the staffId from the
 *   verified session.
 * - ADMIN sees every report, assigns/reassigns to active STAFF accounts, and
 *   may explicitly reject with a recorded reason.
 */
@ApiTags('Staff Reports')
@Controller('staff/reports')
@UseGuards(StaffAuthGuard, RolesGuard)
@Roles('STAFF', 'ADMIN')
@ApiBearerAuth()
export class StaffReportsController {
  constructor(private readonly reportsService: ReportsService) {}

  @Get()
  @ApiOperation({
    summary: 'List reports (staff: assigned only; admin: all campus reports)',
  })
  async listReports(
    @CurrentStaff() staff: AuthenticatedStaff,
    @Query() query: StaffReportListQueryDto,
  ): Promise<ApiResponse<unknown>> {
    return ApiResponse.ok(
      await this.reportsService.listReportsForStaff(staff, query.status),
    );
  }

  // Declared before GET /:id so the literal segment is never read as an id.
  @Get(':id/photo')
  @ApiOperation({
    summary: 'Download a report photo (assigned staff or any admin)',
  })
  async downloadPhoto(
    @CurrentStaff() staff: AuthenticatedStaff,
    @Param('id') id: string,
    @Res({ passthrough: true }) res: Response,
  ): Promise<StreamableFile> {
    const { buffer, contentType } =
      await this.reportsService.downloadReportPhoto(staff, id);
    res.setHeader('Content-Type', contentType);
    res.setHeader('Content-Length', buffer.length);
    res.setHeader('Cache-Control', 'private, max-age=0, no-store');
    return new StreamableFile(buffer);
  }

  @Get(':id')
  @ApiOperation({
    summary: 'Get report detail and history (assigned staff or any admin)',
  })
  async getReport(
    @CurrentStaff() staff: AuthenticatedStaff,
    @Param('id') id: string,
  ): Promise<ApiResponse<unknown>> {
    return ApiResponse.ok(await this.reportsService.getReportForStaff(staff, id));
  }

  @Post(':id/assign')
  @Roles('ADMIN')
  @ApiOperation({ summary: 'Assign/reassign a report to an active STAFF account' })
  async assignReport(
    @CurrentStaff() admin: AuthenticatedStaff,
    @Param('id') id: string,
    @Body() dto: AssignReportDto,
  ): Promise<ApiResponse<unknown>> {
    return ApiResponse.ok(
      await this.reportsService.assignReport(admin, id, dto),
      'Report assigned',
    );
  }

  @Post(':id/accept')
  @Roles('STAFF')
  @ApiOperation({ summary: 'Accept my assigned report (ASSIGNED → IN_PROGRESS)' })
  async acceptReport(
    @CurrentStaff() staff: AuthenticatedStaff,
    @Param('id') id: string,
  ): Promise<ApiResponse<unknown>> {
    return ApiResponse.ok(
      await this.reportsService.acceptReport(staff, id),
      'Report accepted',
    );
  }

  @Post(':id/progress')
  @Roles('STAFF')
  @ApiOperation({ summary: 'Add a progress note to my assigned report' })
  async addProgressNote(
    @CurrentStaff() staff: AuthenticatedStaff,
    @Param('id') id: string,
    @Body() dto: AddProgressNoteDto,
  ): Promise<ApiResponse<unknown>> {
    return ApiResponse.ok(
      await this.reportsService.addProgressNote(staff, id, dto),
      'Progress note added',
    );
  }

  @Post(':id/resolve')
  @Roles('STAFF')
  @ApiOperation({
    summary: 'Resolve my in-progress report with required resolution notes',
  })
  async resolveReport(
    @CurrentStaff() staff: AuthenticatedStaff,
    @Param('id') id: string,
    @Body() dto: ResolveReportDto,
  ): Promise<ApiResponse<unknown>> {
    return ApiResponse.ok(
      await this.reportsService.resolveReport(staff, id, dto),
      'Report resolved',
    );
  }

  @Post(':id/reject')
  @Roles('ADMIN')
  @ApiOperation({ summary: 'Reject a report with a required reason (admin only)' })
  async rejectReport(
    @CurrentStaff() admin: AuthenticatedStaff,
    @Param('id') id: string,
    @Body() dto: RejectReportDto,
  ): Promise<ApiResponse<unknown>> {
    return ApiResponse.ok(
      await this.reportsService.rejectReport(admin, id, dto),
      'Report rejected',
    );
  }
}
