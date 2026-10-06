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
  staffName: string;
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
  staffName?: string;
  minutes?: number;
  /** Classes scheduled for that day (used by the wrap-up at dispatch time). */
  totalCount?: number;
}

interface ParsedEntry {
  entry: TimetableEntry;
  start: Date;
  end: Date;
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
 *
 * Only a few signature moments are pre-planned per day — never per-class spam:
 *   1. First class of the day  → lead reminder
 *   2. First class after the longest break (lunch) → `nextClass`
 *   3. Last class of the day   → lead reminder
 *   4. ~15 min after the last class ends → `dayWrapUp` (stats filled at fire)
 *
 * Saturday and Sunday are skipped entirely (the Sunday chill message is
 * dispatched by a separate weekly cron).
 */
@Injectable()
export class TimetableWatcherService {
  private readonly logger = new Logger(TimetableWatcherService.name);
  private readonly running = new Set<string>();

  /** The longest gap (minutes) that counts as the lunch break. */
  private static readonly LUNCH_GAP_MS = 30 * 60 * 1000;

  constructor(
    private readonly authService: AuthService,
    private readonly linwaysService: LinwaysService,
    private readonly store: JsonStoreService,
    private readonly notifications: NotificationsService,
  ) {}

  @Cron(CronExpression.EVERY_5_MINUTES)
  async watchTimetables(): Promise<void> {
    if (this.isWeekend()) return;
    const sessions = this.authService.getActiveSessions();
    for (const session of sessions) {
      if (this.notifications.getDevices(session.studentId).some((d) => d.enabled)) {
        await this.safeWatch(session);
      }
    }
  }

  /** Sunday, 10:00 AM — the one and only Sunday message. */
  @Cron('0 0 10 * * 0')
  async fireSundayChill(): Promise<void> {
    const sessions = this.authService.getActiveSessions();
    for (const session of sessions) {
      if (this.notifications.getDevices(session.studentId).some((d) => d.enabled)) {
        await this.notifications.dispatchEvent(session.studentId, {
          type: 'sundayChill',
          eventId: `${session.studentId}|sunday|${this.weekKey(new Date())}`,
        });
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
        undefined,
        session.cookies,
        session.authToken,
      );
      if (response.status !== 200) {
        this.logger.warn(
          `Timetable watch non-200 (${response.status}) for ${studentId} — session may be stale`,
        );
        return;
      }

      const entries = this.parseSchedule(response.data);
      const dateKey = this.dateKey(new Date());
      const fingerprint = entries
        .map((e) => `${e.id}|${e.subjectName}|${e.staffName}|${e.fromTime}|${e.toTime}`)
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

  /**
   * Replace all planned reminders for the student with the day's signature
   * moments (first class, post-lunch class, last class, wrap-up). All times
   * come from the real timetable; the lunch break is the longest gap.
   */
  async replanReminders(studentId: string, entries: TimetableEntry[]): Promise<void> {
    const reminders = this.store.getOr<PlannedReminder[]>(STORE_REMINDERS, []);
    const others = reminders.filter((r) => r.studentId !== studentId);
    const preferences = this.notifications.getPreferences(studentId);
    if (preferences.classRemindersEnabled === false || preferences.masterEnabled === false) {
      this.store.set(STORE_REMINDERS, others);
      return;
    }

    const now = Date.now();
    const parsed = entries
      .map((entry) => this.parseWindow(entry))
      .filter((p): p is ParsedEntry => p !== null && p.start.getTime() > now)
      .sort((a, b) => a.start.getTime() - b.start.getTime());

    if (parsed.length === 0) {
      this.store.set(STORE_REMINDERS, others);
      return;
    }

    const leadMinutes =
      preferences.reminderTiming === ReminderTiming.minutes30
        ? 30
        : preferences.reminderTiming === ReminderTiming.minutes5
          ? 5
          : 10;
    const leadType = this.leadType(leadMinutes);

    const planned: PlannedReminder[] = [];
    const add = (
      parsed: ParsedEntry,
      type: NotificationEventType,
      fireAt: number,
      minutes?: number,
    ) => {
      planned.push({
        studentId,
        type,
        fireAt,
        minutes,
        subjectName: parsed.entry.subjectName,
        staffName: parsed.entry.staffName,
        eventId: `${studentId}|cls|${parsed.entry.date}|${parsed.entry.id}|${type}`,
      });
    };

    // 1. First class of the day → lead reminder.
    const first = parsed[0];
    add(first, leadType, first.start.getTime() - leadMinutes * 60_000);

    // 2. First class after the longest break (lunch) → nextClass.
    const postLunch = this.postLunchClass(parsed);
    if (postLunch) {
      add(postLunch, 'nextClass', postLunch.start.getTime() - 10 * 60_000, 10);
    }

    // 3. Last class of the day → lead reminder (skip if it IS the lunch class).
    const last = parsed[parsed.length - 1];
    if (!postLunch || last.entry.id !== postLunch.entry.id) {
      add(last, leadType, last.start.getTime() - leadMinutes * 60_000);
    }

    // 4. Wrap-up ~15 min after the last class ends (stats filled at fire time).
    if (preferences.wrapUpEnabled !== false) {
      planned.push({
        studentId,
        type: 'dayWrapUp',
        fireAt: last.end.getTime() + 15 * 60_000,
        totalCount: parsed.length,
        eventId: `${studentId}|cls|${last.entry.date}|wrapup`,
      });
    }

    this.store.set(STORE_REMINDERS, [...others, ...planned]);
    this.logger.log(
      `Replanned ${planned.length} signature reminders for ${studentId} (${leadMinutes}-min lead)`,
    );
  }

  /** Class starting right after the longest gap ≥ 60 min (lunch), or null. */
  private postLunchClass(parsed: ParsedEntry[]): ParsedEntry | null {
    if (parsed.length < 2) return null;
    let largestGap = 0;
    let gapStart = -1;
    for (let i = 1; i < parsed.length; i++) {
      const gap = parsed[i].start.getTime() - parsed[i - 1].end.getTime();
      if (gap > largestGap) {
        largestGap = gap;
        gapStart = i;
      }
    }
    if (largestGap < TimetableWatcherService.LUNCH_GAP_MS) return null;
    return parsed[gapStart];
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

    const today = this.dateKey(new Date());
    const entries: TimetableEntry[] = [];
    const seenSlots = new Set<string>();
    for (const raw of classes) {
      const entry = this.asRecord(raw);
      if (!entry) continue;

      const fromTime = this.str(entry['fromTime']);
      const toTime = this.str(entry['toTime']);
      const range = this.parseRange(this.str(entry['time']));
      const effectiveFrom = fromTime || range.from;
      const effectiveTo = toTime || range.to;
      if (!effectiveFrom || !effectiveTo) continue;

      // The endpoint may return duplicate rows for the same slot (batch
      // splits) — keep one class per time slot.
      const slotKey = `${effectiveFrom}|${effectiveTo}`;
      if (seenSlots.has(slotKey)) continue;
      seenSlots.add(slotKey);

      const subjects = entry['subjects'];
      const firstSubject = Array.isArray(subjects) ? this.asRecord(subjects[0]) : null;
      const subjectName =
        this.stripCourseCode(this.str(entry['courseName'])) ||
        this.str(firstSubject?.['name']) ||
        this.str(entry['subjectName']) ||
        'Unknown';
      const staffName =
        this.str(entry['facultyName']) ||
        this.str(firstSubject?.['staffName']) ||
        this.str(entry['staffName']) ||
        this.str(firstSubject?.['staff_name']) ||
        this.str(entry['staff_name']) ||
        '';

      entries.push({
        id: this.str(entry['id']) || `${this.str(entry['courseCode']) || subjectName}|${slotKey}`,
        subjectName,
        staffName,
        fromTime: effectiveFrom,
        toTime: effectiveTo,
        date: this.str(entry['date']) || today,
        hour: this.str(entry['hour']) || String(entries.length + 1),
      });
    }
    return entries.filter((e) => e.id && e.fromTime);
  }

  /** Parses "08:30 AM - 09:30 AM" → { from: "08:30", to: "09:30" } (24h). */
  private parseRange(time: string): { from: string; to: string } {
    const match = /(\d{1,2}):(\d{2})\s*(AM|PM)\s*-\s*(\d{1,2}):(\d{2})\s*(AM|PM)/i.exec(time);
    if (!match) return { from: '', to: '' };
    const to24 = (h: string, m: string, meridian: string): string =>
      `${String((Number(h) % 12) + (meridian.toUpperCase() === 'PM' ? 12 : 0)).padStart(2, '0')}:${m}`;
    return {
      from: to24(match[1], match[2], match[3]),
      to: to24(match[4], match[5], match[6]),
    };
  }

  /** Strips a leading course-code prefix: "24BCA51P - WP LAB - Web Programming Lab" → "Web Programming Lab". */
  private stripCourseCode(value: string): string {
    const trimmed = value.trim();
    if (!trimmed) return '';
    const codePattern = /^[A-Za-z0-9\s().,/-]+-\s+(.+)$/;
    const match = codePattern.exec(trimmed);
    return match ? match[1].trim() : trimmed;
  }

  private parseStart(entry: TimetableEntry): Date | null {
    return this.parseClock(entry.fromTime, entry.date);
  }

  private parseEnd(entry: TimetableEntry): Date | null {
    return this.parseClock(entry.toTime, entry.date);
  }

  private parseWindow(entry: TimetableEntry): ParsedEntry | null {
    const start = this.parseStart(entry);
    const end = this.parseEnd(entry);
    if (!start || !end || !end.getTime() || end.getTime() <= start.getTime()) return null;
    return { entry, start, end };
  }

  private parseClock(time: string, dateRaw: string): Date | null {
    const match = /(\d{1,2}):(\d{2})/.exec(time);
    if (!match) return null;
    const hour = Number(match[1]);
    const minute = Number(match[2]);
    const date = dateRaw ? new Date(dateRaw) : new Date();
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

  /** Monday-based ISO week key — used to dedupe the weekly Sunday chill. */
  private weekKey(date: Date): string {
    const d = new Date(date.getFullYear(), date.getMonth(), date.getDate());
    const day = d.getDay();
    const diff = d.getDate() - day + (day === 0 ? -6 : 1);
    const monday = new Date(d.setDate(diff));
    return this.dateKey(monday);
  }

  private isWeekend(): boolean {
    const day = new Date().getDay();
    return day === 0 || day === 6;
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
