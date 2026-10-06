import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { AuthService, Session } from '../auth/auth.service';
import { LinwaysService } from '../linways/linways.service';
import { LINWAYS_ENDPOINTS } from '../linways/linways.constants';
import { JsonStoreService } from '../common/store/json-store.service';
import { NotificationsService } from './notifications.service';

interface MarkedRecord {
  date: string;
  subjectName: string;
  hour: string;
  status: string;
  staffName?: string;
}

interface AttendanceSnapshot {
  records: Record<string, string>; // key -> status
  overallPct: number | null;
  lastPct: number | null;
  lastPctEventDate: string | null;
  updatedAt: number;
}

const STORE_SNAPSHOTS = 'attendanceSnapshots';

/**
 * Background attendance monitor — "absent roast" only.
 *
 * Every minute during college hours (weekdays), for each student with an
 * active backend session AND at least one registered device:
 *   - Fetch the daily attendance report and diff it against the stored
 *     snapshot. Only a NEWLY-marked ABSENT record for the FIRST or LAST
 *     class of the day dispatches the `attendanceMarkedAbsent` roast —
 *     middle classes stay silent (no spam). Present/leave records and
 *     middle absences just advance the silent baseline (dedupe via
 *     deterministic eventId per record+status).
 *
 * Outside college hours and on weekends no polling happens at all — zero
 * Linways load. Polling is bounded by session availability: watchers only run
 * for students whose in-memory session (max 24 h) is still valid.
 */
@Injectable()
export class AttendanceWatcherService {
  private readonly logger = new Logger(AttendanceWatcherService.name);
  private readonly running = new Set<string>();

  /** Poll window (college hours) — start hour/min and end hour/min, local. */
  private static readonly WATCH_START = { hour: 7, minute: 30 };
  private static readonly WATCH_END = { hour: 19, minute: 0 };

  constructor(
    private readonly authService: AuthService,
    private readonly linwaysService: LinwaysService,
    private readonly store: JsonStoreService,
    private readonly notifications: NotificationsService,
  ) {}

  @Cron(CronExpression.EVERY_MINUTE)
  async pollAttendance(): Promise<void> {
    if (!this.inWatchWindow()) return;
    const sessions = this.authService.getActiveSessions();
    for (const session of sessions) {
      if (this.notifications.getDevices(session.studentId).some((d) => d.enabled)) {
        await this.safePoll(session);
      }
    }
  }

  private async safePoll(session: Session): Promise<void> {
    const studentId = session.studentId;
    if (this.running.has(studentId)) return;
    this.running.add(studentId);
    try {
      await this.checkMarkedRecords(session);
    } catch (error) {
      this.logger.warn(`Attendance poll failed for ${studentId}: ${error}`);
    } finally {
      this.running.delete(studentId);
    }
  }

  // ── Newly marked attendance records ─────────────────────────

  private async checkMarkedRecords(session: Session): Promise<void> {
    const studentId = session.studentId;
    const response = await this.linwaysService.get(
      LINWAYS_ENDPOINTS.DAILY_ATTENDANCE,
      { studentId },
      session.cookies,
      session.authToken,
    );
    if (response.status !== 200) return;

    const records = this.parseDailyReport(response.data);
    if (records.length === 0) return;

    const snapshots = this.store.getOr<Record<string, AttendanceSnapshot>>(STORE_SNAPSHOTS, {});
    const snapshot = snapshots[studentId] ?? {
      records: {},
      overallPct: null,
      lastPct: null,
      lastPctEventDate: null,
      updatedAt: 0,
    };

    let changed = false;
    // Only the first and last class of the day are roast targets — middle
    // absences advance the silent baseline so a fully-absent day sends
    // exactly two messages.
    const firstKey = this.recordKey(records[0]);
    const lastKey = this.recordKey(records[records.length - 1]);
    for (const record of records) {
      const key = this.recordKey(record);
      if (snapshot.records[key] === record.status) continue;

      // Absent-only: present and leave records (and non-target absent
      // classes) just advance the silent baseline — no notification.
      if (record.status !== '0' || (key !== firstKey && key !== lastKey)) {
        snapshot.records[key] = record.status;
        changed = true;
        continue;
      }

      const eventId = `${studentId}|att|${key}|${record.status}`;
      const delivered = await this.notifications.dispatchEvent(studentId, {
        type: 'attendanceMarkedAbsent',
        subjectName: record.subjectName,
        staffName: record.staffName,
        eventId,
      });

      // Only advance the baseline when the event was delivered (or already
      // processed). Otherwise the event stays pending and is re-attempted on
      // the next poll — this is what makes "phone off → phone on" and
      // "transient FCM outage" delivery work without duplicates.
      if (delivered || this.notifications.isProcessed(eventId)) {
        snapshot.records[key] = record.status;
        changed = true;
      }
    }

    if (changed) {
      snapshot.updatedAt = Date.now();
      snapshots[studentId] = snapshot;
      this.store.set(STORE_SNAPSHOTS, snapshots);
    }
  }

  // ── Linways response parsing (mirrors the Flutter models) ───

  /** Deterministic per-record key used for snapshot dedupe + eventIds. */
  private recordKey(record: MarkedRecord): string {
    return `${record.date}|${record.subjectName}|${record.hour}`;
  }

  private parseDailyReport(data: unknown): MarkedRecord[] {
    const inner = this.pluck(data, ['data', 'Data']) as Record<string, unknown> | null;
    const report = inner ? (inner['report'] as unknown[]) : null;
    if (!Array.isArray(report)) return [];

    const records: MarkedRecord[] = [];
    for (const reportEntry of report) {
      if (!this.isRecord(reportEntry)) continue;
      // Linways reports DD-MM-YYYY — normalize to YYYY-MM-DD so keys match
      // the schedule/dateKey format used elsewhere.
      const date = this.normalizeDate(this.str(reportEntry['attendance_date']));
      const hourDetails = reportEntry['hourDetails'];
      if (!Array.isArray(hourDetails)) continue;

      hourDetails.forEach((hourEntry, hourIndex) => {
        if (!this.isRecord(hourEntry)) return;
        const subjectDetails = hourEntry['subjectDetails'];
        if (!Array.isArray(subjectDetails)) return;

        for (const subjectEntry of subjectDetails) {
          if (!this.isRecord(subjectEntry)) continue;
          records.push({
            date,
            subjectName: this.str(subjectEntry['subjectName']) || 'Unknown',
            hour: this.str(subjectEntry['hour'] || subjectEntry['hourName']) || String(hourIndex),
            status: this.str(subjectEntry['attendanceStatus']) || '0',
            staffName: this.str(subjectEntry['staffName']) || undefined,
          });
        }
      });
    }
    return records;
  }

  // ── helpers ─────────────────────────────────────────────────

  /** True between 7:30–19:00 local on a weekday (Sat/Sun are skipped). */
  private inWatchWindow(): boolean {
    const now = new Date();
    const day = now.getDay();
    if (day === 0 || day === 6) return false;
    const minutes = now.getHours() * 60 + now.getMinutes();
    const start = AttendanceWatcherService.WATCH_START.hour * 60 + AttendanceWatcherService.WATCH_START.minute;
    const end = AttendanceWatcherService.WATCH_END.hour * 60 + AttendanceWatcherService.WATCH_END.minute;
    return minutes >= start && minutes < end;
  }

  private pluck(value: unknown, keys: string[]): unknown {
    if (!this.isRecord(value)) return value;
    for (const key of keys) {
      if (value[key] !== undefined) return value[key];
    }
    return value;
  }

  private str(value: unknown): string {
    return value === null || value === undefined ? '' : String(value);
  }

  /** Converts DD-MM-YYYY → YYYY-MM-DD; leaves other formats untouched. */
  private normalizeDate(value: string): string {
    const match = /^(\d{2})-(\d{2})-(\d{4})$/.exec(value);
    return match ? `${match[3]}-${match[2]}-${match[1]}` : value;
  }

  private isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === 'object' && value !== null;
  }
}
