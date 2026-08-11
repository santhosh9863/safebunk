import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { AuthService, Session } from '../auth/auth.service';
import { LinwaysService } from '../linways/linways.service';
import { LINWAYS_ENDPOINTS } from '../linways/linways.constants';
import { JsonStoreService } from '../common/store/json-store.service';
import { NotificationsService } from './notifications.service';
import { NotificationRuleService } from './notification-rule.service';
import { NotificationEventPayload } from './notification-events';

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
 * Background attendance monitor.
 *
 * Every 5 minutes, for each student with an active backend session AND at
 * least one registered device:
 *   1. Fetch the daily attendance report (bypassing the request cache) and
 *      diff it against the stored snapshot → attendanceMarkedPresent/Absent
 *      for every NEW record (deterministic eventId per record+status).
 *   2. Fetch the subject-wise report, compute the overall percentage and run
 *      the rule engine → ONE best zone/direction event per day (plus
 *      milestones). The baseline is always persisted, even when disabled.
 *
 * Polling is bounded by session availability: watchers only run for students
 * whose in-memory session (max 24 h) is still valid. No password is stored,
 * so once a session expires monitoring stops until the student logs in again.
 */
@Injectable()
export class AttendanceWatcherService {
  private readonly logger = new Logger(AttendanceWatcherService.name);
  private readonly running = new Set<string>();

  constructor(
    private readonly authService: AuthService,
    private readonly linwaysService: LinwaysService,
    private readonly store: JsonStoreService,
    private readonly notifications: NotificationsService,
    private readonly rules: NotificationRuleService,
  ) {}

  @Cron(CronExpression.EVERY_5_MINUTES)
  async pollAttendance(): Promise<void> {
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
      await this.checkPercentage(session);
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
    for (const record of records) {
      const key = `${record.date}|${record.subjectName}|${record.hour}`;
      if (snapshot.records[key] === record.status) continue;

      snapshot.records[key] = record.status;
      changed = true;

      const eventType = this.rules.statusToEvent(record.status);
      if (!eventType) continue;

      await this.notifications.dispatchEvent(studentId, {
        type: eventType,
        subjectName: record.subjectName,
        eventId: `${studentId}|att|${key}|${record.status}`,
      });
    }

    if (changed) {
      snapshot.updatedAt = Date.now();
      snapshots[studentId] = snapshot;
      this.store.set(STORE_SNAPSHOTS, snapshots);
    }
  }

  // ── Percentage transitions / zones ──────────────────────────

  private async checkPercentage(session: Session): Promise<void> {
    const studentId = session.studentId;
    const response = await this.linwaysService.get(
      LINWAYS_ENDPOINTS.SUBJECT_WISE_ATTENDANCE,
      { studentId },
      session.cookies,
    );
    if (response.status !== 200) return;

    const overall = this.parseOverallPercentage(response.data);
    if (overall === null) return;

    const snapshots = this.store.getOr<Record<string, AttendanceSnapshot>>(STORE_SNAPSHOTS, {});
    const snapshot = snapshots[studentId] ?? {
      records: {},
      overallPct: null,
      lastPct: null,
      lastPctEventDate: null,
      updatedAt: 0,
    };

    snapshot.overallPct = overall;

    const today = new Date().toISOString().slice(0, 10);
    const preferences = this.notifications.getPreferences(studentId);

    if (snapshot.lastPct === null) {
      // First observation — silent baseline.
      snapshot.lastPct = overall;
      snapshot.lastPctEventDate = today;
    } else {
      const { event, milestones } = this.rules.evaluateAttendanceTransition(
        snapshot.lastPct,
        overall,
      );
      const isNewDay = snapshot.lastPctEventDate !== today;

      // One best event per day (plus milestones on that same transition).
      if (event && isNewDay) {
        const percentEvent: NotificationEventPayload = {
          type: event,
          percentage: overall,
          eventId: `${studentId}|pct|${today}|${event}`,
        };
        await this.notifications.dispatchEvent(studentId, percentEvent);

        for (const milestone of milestones) {
          if (preferences.milestonesEnabled === false) continue;
          await this.notifications.dispatchEvent(studentId, {
            type: milestone,
            percentage: overall,
            eventId: `${studentId}|pct|${today}|${milestone}`,
          });
        }
        snapshot.lastPctEventDate = today;
      }

      snapshot.lastPct = overall;
    }

    snapshots[studentId] = snapshot;
    this.store.set(STORE_SNAPSHOTS, snapshots);
  }

  // ── Linways response parsing (mirrors the Flutter models) ───

  private parseDailyReport(data: unknown): MarkedRecord[] {
    const inner = this.pluck(data, ['data', 'Data']) as Record<string, unknown> | null;
    const report = inner ? (inner['report'] as unknown[]) : null;
    if (!Array.isArray(report)) return [];

    const records: MarkedRecord[] = [];
    for (const reportEntry of report) {
      if (!this.isRecord(reportEntry)) continue;
      const date = this.str(reportEntry['attendance_date']);
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

  /** Overall percentage from the subject-wise report (present/total weighted). */
  private parseOverallPercentage(data: unknown): number | null {
    const inner = this.pluck(data, ['data', 'Data']) as Record<string, unknown> | null;
    const report = inner ? (inner['report'] ?? inner['subjects']) : null;
    if (!Array.isArray(report) || report.length === 0) return null;

    let present = 0;
    let total = 0;
    for (const subject of report) {
      if (!this.isRecord(subject)) continue;
      // Field names vary across Linways versions — try several spellings.
      const p = this.num(
        this.first(
          subject,
          ['presentHours', 'present_hours', 'presentCount', 'present', 'attendedHours', 'attended_hours'],
        ),
      );
      const t = this.num(
        this.first(
          subject,
          ['totalHours', 'total_hours', 'totalCount', 'total', 'scheduledHours'],
        ),
      );
      if (p !== null && t !== null) {
        present += p;
        total += t;
      } else if (this.str(subject['percentage']).length > 0) {
        // Fallback: weighted by hours is unavailable, accumulate percentages.
        const pct = this.num(subject['percentage']);
        if (pct !== null) {
          present += pct;
          total += 1;
        }
      }
    }

    if (total <= 0) return null;
    return Math.round((present / total) * 1000) / 10;
  }

  // ── helpers ─────────────────────────────────────────────────

  private pluck(value: unknown, keys: string[]): unknown {
    if (!this.isRecord(value)) return value;
    for (const key of keys) {
      if (value[key] !== undefined) return value[key];
    }
    return value;
  }

  private first(record: Record<string, unknown>, keys: string[]): unknown {
    for (const key of keys) {
      if (record[key] !== undefined) return record[key];
    }
    return undefined;
  }

  private str(value: unknown): string {
    return value === null || value === undefined ? '' : String(value);
  }

  private num(value: unknown): number | null {
    if (value === null || value === undefined || value === '') return null;
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }

  private isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === 'object' && value !== null;
  }
}
