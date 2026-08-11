import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { JsonStoreService } from '../common/store/json-store.service';
import { NotificationsService } from './notifications.service';
import { PlannedReminder } from './timetable-watcher.service';

const STORE_REMINDERS = 'plannedReminders';

/**
 * Fires server-scheduled class reminders at their exact minute. Runs every
 * minute; anything whose fire time has arrived and is still unprocessed is
 * delivered through FCM (OS-level delivery — no app process needed). Class
 * reminders carry a short FCM TTL so a stale "starts in 5 minutes" never
 * arrives hours later.
 */
@Injectable()
export class NotificationSchedulerService {
  private readonly logger = new Logger(NotificationSchedulerService.name);
  private running = false;

  constructor(
    private readonly store: JsonStoreService,
    private readonly notifications: NotificationsService,
  ) {}

  @Cron('* * * * *')
  async fireDueReminders(): Promise<void> {
    if (this.running) return;
    this.running = true;
    try {
      const reminders = this.store.getOr<PlannedReminder[]>(STORE_REMINDERS, []);
      if (reminders.length === 0) return;

      const now = Date.now();
      const due = reminders.filter((r) => r.fireAt <= now);
      if (due.length === 0) return;

      const remaining = reminders.filter((r) => r.fireAt > now);
      const stillPending: PlannedReminder[] = [];

      for (const reminder of due) {
        if (this.notifications.isProcessed(reminder.eventId)) continue;

        await this.notifications.dispatchEvent(reminder.studentId, {
          type: reminder.type,
          subjectName: reminder.subjectName,
          minutes: reminder.minutes,
          eventId: reminder.eventId,
        });

        // dispatchEvent marks processed when it actually dispatched; keep
        // entries until then so nothing is lost across retries.
        if (!this.notifications.isProcessed(reminder.eventId)) {
          stillPending.push(reminder);
        }
      }

      if (stillPending.length > 0) {
        this.store.set(STORE_REMINDERS, [...remaining, ...stillPending]);
      } else {
        this.store.set(STORE_REMINDERS, remaining);
      }
    } catch (error) {
      this.logger.error(`Reminder firing failed: ${error}`);
    } finally {
      this.running = false;
    }
  }
}
