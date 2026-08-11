import { Module } from '@nestjs/common';
import { NotificationsController } from './notifications.controller';
import { NotificationsService } from './notifications.service';
import { FcmService } from './fcm.service';
import { NotificationRuleService } from './notification-rule.service';
import { NotificationContentService } from './notification-content.service';
import { AttendanceWatcherService } from './attendance-watcher.service';
import { TimetableWatcherService } from './timetable-watcher.service';
import { NotificationSchedulerService } from './notification-scheduler.service';

@Module({
  controllers: [NotificationsController],
  providers: [
    NotificationsService,
    FcmService,
    NotificationRuleService,
    NotificationContentService,
    AttendanceWatcherService,
    TimetableWatcherService,
    NotificationSchedulerService,
  ],
  exports: [NotificationsService, TimetableWatcherService],
})
export class NotificationsModule {}
