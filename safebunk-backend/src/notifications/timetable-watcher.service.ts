import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { AuthService, Session } from '../auth/auth.service';
import { LinwaysService } from '../linways/linways.service';
import { LINWAYS_ENDPOINTS } from '../linways/linways.constants';
import { JsonStoreService } from '../common/store/json-store.service';
import { NotificationsService } from './notifications.service';
import { NotificationEventPayload, NotificationEventType } from './notification-events';
import { ReminderTiming } from './dto/notification-preferences.dto';

export interface TimetableEntry {
  id: string;
  subjectName: string;
  fromTime: string;
  toTime: string;
  date: string;
  hour: string;
}

export interface PlannedReminder {
  studentId: string;
  eventId: string;
  type: NotificationEventType;
  fireAt: number; // epoch ms
  subjectName?: string;
  minutes?: number;
}

interface TimetableSnapshot {
  dateKey: string;
  fingerprint: string;
  updatedAt: number;
}

const STORE_TIMETABLE = 'timetableSnapshots';
const STORE_REMINDERS = 'plannedReminders';

/**
 * Watches the real Linways timetable (never hardcoded times). When today's
 * schedule changes the old planned reminders are replaced and a
 * `timetableUpdated` event is fired once (deterministic eventId per day).
 * Pre-plans the preference-based lead reminders (30/10/5 min + class start)
 * for the scheduler to fire.
 */
@Injectable()
export class TimetableWatcherService {
  private readonly logger = new Logger(TimetableWatcherService.name);
  private readonly running = new Set<string>();

  constructor(
    private readonly authService: AuthService,
    private readonly linwaysService: LinwaysService,
    private readonly store: JsonStoreService,
    private readonly notifications: NotificationsService,
  ) {}

  @Cron(CronExpression.EVERY_5_MINUTES)
  async watchTimetables(): Promise<void> {
    const sessions = this.authService.getActiveSessions();
    for (const session of sessions) {
      if (this.notifications.getDevices(session.studentId).some((d) => d.enabled)) {
        await this.safeWatch(session);
      }
    }
  }

  private async safeWatch(session: Session): Promise<void> {
    const studentId = session.studentId;
    if (this.running.has(studentId)) return;
    this.running.add(studentId);
    try {
      const response = await this.linwaysService.get(
        LINWAYS_ENDPOINTS.STUDENT_DAILY_SCHEDULE,
        { studentId },
        session.cookies,
      );
      if (response.status !== 200) return;

      const entries = this.parseSchedule(response.data);
      const dateKey = this.dateKey(new Date());
      const fingerprint = entries
        .map((e) => `${e.id}|${e.subjectName}|${e.fromTime}|${e.toTime}`)
        .sort()
        .join(';');

      const snapshots = this.store.getOr<Record<string, TimetableSnapshot>>(STORE_TIMETABLE, {});
      const previous = snapshots[studentId];
      const changed = !previous || previous.fingerprint !== fingerprint;

      if (changed) {
        snapshots[studentId] = { dateKey, fingerprint, updatedAt: Date.now() };
        this.store.set(STORE_TIMETABLE, snapshots);

        if (previous && previous.dateKey === dateKey) {
          // Real change on the same day (not just a new day rolling over).
          await this.notifications.dispatchEvent(studentId, {
            type: 'timetableUpdated',
            eventId: `${studentId}|timetable|${dateKey}|updated`,
          });
        }

        await this.replanReminders(studentId, entries);
      }
    } catch (error) {
      this.logger.warn(`Timetable watch failed for ${studentId}: ${error}`);
    } finally {
      this.running.delete(studentId);
    }
  }

  /** Replace all planned reminders for the student from the fresh timetable. */
  async replanReminders(studentId: string, entries: TimetableEntry[]): Promise<void> {
    const reminders = this.store.getOr<PlannedReminder[]>(STORE_REMINDERS, []);
    const others = reminders.filter((r) => r.studentId !== studentId);
    const preferences = this.notifications.getPreferences(studentId);
    if (preferences.classRemindersEnabled === false || preferences.masterEnabled === false) {
      this.store.set(STORE_REMINDERS, others);
      return;
    }

    const now = Date.now();
    const leadMinutes =
      preferences.reminderTiming === ReminderTiming.minutes30
        ? 30
        : preferences.reminderTiming === ReminderTiming.minutes5
          ? 5
          : 10;

    const planned: PlannedReminder[] = [];
    for (const entry of entries) {
      const start = this.parseStart(entry);
      if (!start || start.getTime() <= now) continue;

      const startEpoch = start.getTime();
      const leadType = this.leadType(leadMinutes);

      const add = (type: NotificationEventType, fireAt: number, minutes?: number) => {
        planned.push({
          studentId,
          type,
          fireAt,
          minutes,
          subjectName: entry.subjectName,
          eventId: `${studentId}|cls|${entry.date}|${entry.id}|${type}`,
        });
      };

      add(leadType, startEpoch - leadMinutes * 60_000);
      if (leadMinutes !== 5) {
        add('classReminder5Min', startEpoch - 5 * 60_000);
      }
      add('classStarting', startEpoch);
    }

    this.store.set(STORE_REMINDERS, [...others, ...planned]);
    this.logger.log(
      `Replanned ${planned.length} reminders for ${studentId} (${leadMinutes}-min lead)`,
    );
  }

  cancelStudentReminders(studentId: string): void {
    const reminders = this.store.getOr<PlannedReminder[]>(STORE_REMINDERS, []);
    this.store.set(
      STORE_REMINDERS,
      reminders.filter((r) => r.studentId !== studentId),
    );
  }

  // ── Parsing (mirrors the Flutter TimetableApiService._parseDailySchedule) ──

  private parseSchedule(data: unknown): TimetableEntry[] {
    const root = this.asRecord(data);
    if (!root || root['success'] !== true) return [];
    const body = this.asRecord(root['data']);
    if (!body) return [];
    const classes = body['classes'];
    if (!Array.isArray(classes)) return [];

    const entries: TimetableEntry[] = [];
    for (const raw of classes) {
      const entry = this.asRecord(raw);
      if (!entry) continue;
      const subjects = entry['subjects'];
      const firstSubject = Array.isArray(subjects) ? this.asRecord(subjects[0]) : null;
      entries.push({
        id: this.str(entry['id']),
        subjectName: this.str(firstSubject?.['name']) || this.str(entry['subjectName']) || 'Unknown',
        fromTime: this.str(entry['fromTime']),
        toTime: this.str(entry['toTime']),
        date: this.str(entry['date']),
        hour: this.str(entry['hour']),
      });
    }
    return entries.filter((e) => e.id && e.fromTime);
  }

  private parseStart(entry: TimetableEntry): Date | null {
    const match = /(\d{1,2}):(\d{2})/.exec(entry.fromTime);
    if (!match) return null;
    const hour = Number(match[1]);
    const minute = Number(match[2]);
    const date = entry.date ? new Date(entry.date) : new Date();
    if (Number.isNaN(date.getTime())) return null;
    date.setHours(hour, minute, 0, 0);
    return date;
  }

  private leadType(minutes: number): NotificationEventType {
    switch (minutes) {
      case 30:
        return 'classReminder30Min';
      case 5:
        return 'classReminder5Min';
      default:
        return 'classReminder10Min';
    }
  }

  private dateKey(date: Date): string {
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
  }

  private str(value: unknown): string {
    return value === null || value === undefined ? '' : String(value);
  }

  private asRecord(value: unknown): Record<string, unknown> | null {
    return typeof value === 'object' && value !== null
      ? (value as Record<string, unknown>)
      : null;
  }
}
