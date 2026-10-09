import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Post,
  Res,
  StreamableFile,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import {
  ApiBearerAuth,
  ApiBody,
  ApiConsumes,
  ApiOperation,
  ApiTags,
} from '@nestjs/swagger';
import { Response } from 'express';
import { AuthGuard } from '../common/guards/auth.guard';
import { CurrentUser, AuthenticatedUser } from '../common/decorators/current-user.decorator';
import { ApiResponse } from '../common/dto/api-response.dto';
import { CreateReportDto } from './dto/create-report.dto';
import { ReportsService } from './reports.service';
import { AttachmentsService } from './attachments/attachments.service';
import { MAX_IMAGE_BYTES, UploadedImage } from './attachments/image-validator';

@ApiTags('Reports')
@Controller('reports')
@UseGuards(AuthGuard)
@ApiBearerAuth()
export class ReportsController {
  constructor(
    private readonly reportsService: ReportsService,
    private readonly attachmentsService: AttachmentsService,
  ) {}

  @Post()
  @ApiOperation({ summary: 'Create a campus issue report (student)' })
  async createReport(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: CreateReportDto,
  ): Promise<ApiResponse<unknown>> {
    const report = await this.reportsService.createReport(user.studentId, dto);
    return ApiResponse.ok(report, 'Report created');
  }

  // --- Attachments ----------------------------------------------------------
  // Declared before GET /:id so the literal segment is never read as an id.

  @Post('attachments')
  @ApiOperation({ summary: 'Upload a report photo (student, multipart)' })
  @ApiConsumes('multipart/form-data')
  @ApiBody({
    schema: {
      type: 'object',
      properties: { file: { type: 'string', format: 'binary' } },
      required: ['file'],
    },
  })
  @UseInterceptors(FileInterceptor('file', { limits: { fileSize: MAX_IMAGE_BYTES, files: 1 } }))
  async uploadAttachment(
    @CurrentUser() user: AuthenticatedUser,
    @UploadedFile() file: UploadedImage | undefined,
  ): Promise<ApiResponse<unknown>> {
    const attachment = await this.attachmentsService.createFromUpload(user.studentId, file);
    return ApiResponse.ok(attachment, 'Attachment uploaded');
  }

  @Get('attachments/:id')
  @ApiOperation({ summary: 'Download one of my report photos (student)' })
  async downloadAttachment(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id') id: string,
    @Res({ passthrough: true }) res: Response,
  ): Promise<StreamableFile> {
    const { buffer, contentType } = await this.attachmentsService.download(user.studentId, id);
    res.setHeader('Content-Type', contentType);
    res.setHeader('Content-Length', buffer.length);
    res.setHeader('Cache-Control', 'private, max-age=0, no-store');
    return new StreamableFile(buffer);
  }

  @Delete('attachments/:id')
  @ApiOperation({ summary: 'Remove my not-yet-attached report photo (student)' })
  async deleteAttachment(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id') id: string,
  ): Promise<ApiResponse<unknown>> {
    await this.attachmentsService.removeOwnUnlinked(user.studentId, id);
    return ApiResponse.ok(null, 'Attachment removed');
  }

  // --- Reports --------------------------------------------------------------

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
