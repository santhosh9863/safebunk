import { Module } from '@nestjs/common';
import { ReportsController } from './reports.controller';
import { StaffReportsController } from './staff-reports.controller';
import { ReportsService } from './reports.service';
import { ReportsRealtimeGateway } from './reports-realtime.gateway';
import { AttachmentsService } from './attachments/attachments.service';
import { ReportStorageService } from './attachments/report-storage.service';

@Module({
  controllers: [ReportsController, StaffReportsController],
  providers: [
    ReportsService,
    ReportsRealtimeGateway,
    AttachmentsService,
    ReportStorageService,
  ],
})
export class ReportsModule {}
