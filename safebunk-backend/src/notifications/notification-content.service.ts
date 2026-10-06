import { Injectable } from '@nestjs/common';
import { NotificationEventPayload, NotificationEventType } from './notification-events';
import { NotificationPreferencesDto, DEFAULT_PREFERENCES } from './dto/notification-preferences.dto';

export interface NotificationContent {
  title: string;
  body: string;
}

interface Template {
  roastTitle: string;
  neutralTitle: string;
  body: string;
}

/** Direct-address word per gender: [male, female, unknown]. */
const ADDRESS: Record<'male' | 'female' | 'unknown', string> = {
  male: 'king',
  female: 'queen',
  unknown: 'legend',
};

/**
 * Centralized Gen-Z message library for the server side. All wording lives
 * here — watchers never build user-facing text. Roasting only changes the
 * presentation; the factual body is identical.
 */
@Injectable()
export class NotificationContentService {
  build(
    event: NotificationEventPayload,
    preferences: NotificationPreferencesDto,
  ): NotificationContent {
    const template = this.templateFor(event.type);
    const roasting = preferences.roastingEnabled !== false;
    const gender = this.genderOf(preferences);
    const teacher = this.teacherOf(event.staffName);
    const rawTitle = roasting
      ? template.roastTitle
          .replaceAll('{address}', ADDRESS[gender])
          .replaceAll('{dude}', this.dude(gender))
      : template.neutralTitle;
    const teacherLead = teacher.label
      ? `${teacher.label} just marked you absent, ${this.dude(gender)}! 💀`
      : 'Class waited. You ghosted. 💀';
    const teacherWith = teacher.label ? ` with ${teacher.label}` : '';
    return {
      title: this.fill(rawTitle, event)
        .replaceAll('{teacherName}', teacher.name)
        .replaceAll('{teacherTag}', teacher.tag)
        .replaceAll('{teacherLead}', teacherLead)
        .replaceAll('{teacherWith}', teacherWith),
      body: this.fill(template.body, event)
        .replaceAll('{dude}', this.dude(gender))
        .replaceAll('{attender}', this.attender(gender))
        .replaceAll('{teacherName}', teacher.name)
        .replaceAll('{teacherTag}', teacher.tag)
        .replaceAll('{teacherWith}', teacherWith),
    };
  }

  private genderOf(preferences: NotificationPreferencesDto): 'male' | 'female' | 'unknown' {
    if (preferences.gender === 'male') return 'male';
    if (preferences.gender === 'female') return 'female';
    return 'unknown';
  }

  private dude(gender: 'male' | 'female' | 'unknown'): string {
    switch (gender) {
      case 'male':
        return 'bro';
      case 'female':
        return 'sis';
      default:
        return 'bestie';
    }
  }

  /** Perfect-attendance phrasing per gender. */
  private attender(gender: 'male' | 'female' | 'unknown'): string {
    switch (gender) {
      case 'male':
        return 'Bro practically lives on campus';
      case 'female':
        return 'She practically lives on campus';
      default:
        return 'Certified campus dweller';
    }
  }

  /**
   * Resolve a faculty member's name into a respectful, gender-correct
   * address. Honorifics (when the portal provides them) decide the tag;
   * anything without one defaults to "Prof." so the wording never invents
   * a gender. Returns label:null when no name is available at all.
   */
  private teacherOf(staffName?: string): { label: string | null; name: string; tag: string } {
    const raw = (staffName ?? '').trim();
    if (!raw) return { label: null, name: '', tag: '' };
    const match = /^(mr\.?|mrs\.?|ms\.?|miss|dr\.?)\s+/i.exec(raw);
    if (!match) {
      return { label: `Prof. ${raw}`, name: raw, tag: 'Prof.' };
    }
    const honorific = match[1].toLowerCase().replace(/\.$/, '');
    const name = raw.slice(match[0].length).trim() || raw;
    switch (honorific) {
      case 'mr':
        return { label: `${name} sir`, name, tag: 'sir' };
      case 'mrs':
      case 'ms':
      case 'miss':
        return { label: `${name} ma'am`, name, tag: "ma'am" };
      default: // dr / dr.
        return { label: `Prof. ${name}`, name, tag: 'Prof.' };
    }
  }

  private fill(template: string, event: NotificationEventPayload): string {
    const percentage =
      event.percentage !== undefined
        ? `${this.trimZeroes(event.percentage)}%`
        : '';
    const target = event.target !== undefined ? `${event.target}%` : '75%';
    const subject = event.subjectName || 'this class';
    const presentCount = event.presentCount !== undefined ? String(event.presentCount) : '?';
    const totalCount = event.totalCount !== undefined ? String(event.totalCount) : '?';
    return template
      .replaceAll('{subjectName}', subject)
      .replaceAll('{percentage}', percentage)
      .replaceAll('{target}', target)
      .replaceAll('{minutes}', String(event.minutes ?? ''))
      .replaceAll('{presentCount}', presentCount)
      .replaceAll('{totalCount}', totalCount);
  }

  private trimZeroes(value: number): string {
    const text = value.toFixed(1);
    return text.endsWith('.0') ? value.toFixed(0) : text;
  }

  private templateFor(type: NotificationEventType): Template {
    switch (type) {
      // ── Attendance marked ──
      case 'attendanceMarkedPresent':
        return {
          roastTitle: "Damn, you showed up. 💀",
          neutralTitle: 'Attendance marked',
          body: '{subjectName} has been marked present.',
        };
      case 'attendanceMarkedAbsent':
        return {
          roastTitle: '{teacherLead}',
          neutralTitle: 'Attendance marked',
          body: '{subjectName} has been marked absent.',
        };

      // ── Percentage transitions ──
      case 'attendanceImproved':
        return {
          roastTitle: 'Attendance noticed. 👀',
          neutralTitle: 'Attendance up',
          body: 'Your attendance climbed to {percentage}.',
        };
      case 'attendanceDropped':
        return {
          roastTitle: 'That hurt. 📉',
          neutralTitle: 'Attendance down',
          body: 'Your attendance dropped to {percentage}.',
        };
      case 'enteredSafeZone':
        return {
          roastTitle: 'Back together. 🫶',
          neutralTitle: 'Back in the safe zone',
          body: "You're finally back above {target}.",
        };
      case 'leftSafeZone':
        return {
          roastTitle: 'We need to talk. 👀',
          neutralTitle: 'Below the safe zone',
          body: "You're back below the {target} safe zone.",
        };
      case 'enteredDangerZone':
        return {
          roastTitle: "You're cooked. 😭",
          neutralTitle: 'Danger zone',
          body: 'Your attendance just entered the danger zone.',
        };
      case 'recoveredFromDanger':
        return {
          roastTitle: 'Character development. 🔥',
          neutralTitle: 'Out of the danger zone',
          body: 'You recovered from the danger zone.',
        };
      case 'perfectAttendance':
        return {
          roastTitle: 'Too available. 🗿',
          neutralTitle: 'Perfect attendance',
          body: '100% attendance. {attender}.',
        };

      // ── Milestones ──
      case 'reached80':
        return {
          roastTitle: 'Showing off now. 💀',
          neutralTitle: 'Milestone reached',
          body: 'Your attendance just crossed 80%.',
        };
      case 'reached90':
        return {
          roastTitle: 'Too consistent. 😭',
          neutralTitle: 'Milestone reached',
          body: 'Your attendance just crossed 90%.',
        };
      case 'reached95':
        return {
          roastTitle: 'Certified menace. 🗿',
          neutralTitle: 'Milestone reached',
          body: 'Your attendance just crossed 95%.',
        };

      // ── Class reminders ──
      case 'classReminder30Min':
        return {
          roastTitle: 'Class is waiting. 👀',
          neutralTitle: 'Upcoming class',
          body: '{subjectName}{teacherWith} starts in 30 minutes.',
        };
      case 'classReminder10Min':
        return {
          roastTitle: "Don't ghost the class. 💀",
          neutralTitle: 'Upcoming class',
          body: '{subjectName}{teacherWith} starts in 10 minutes.',
        };
      case 'classReminder5Min':
        return {
          roastTitle: 'Class is getting impatient. 😭',
          neutralTitle: 'Upcoming class',
          body: '{subjectName}{teacherWith} starts in 5 minutes.',
        };
      case 'classStarting':
        return {
          roastTitle: 'Move it, {dude}. 😭',
          neutralTitle: 'Class starting now',
          body: '{subjectName} is starting now.',
        };
      case 'classMissed':
        return {
          roastTitle: 'Left the class waiting. 💀',
          neutralTitle: 'Class missed',
          body: 'You missed {subjectName}.',
        };
      case 'nextClass':
        return {
          roastTitle: 'Round two. 😏',
          neutralTitle: 'Next class',
          body: '{subjectName}{teacherWith} starts in {minutes} minutes.',
        };

      // ── Day-level facts ──
      case 'dayWrapUp':
        return {
          roastTitle: "Day's a W — {presentCount}/{totalCount}. 💅",
          neutralTitle: 'Day complete',
          body: "College's done for today. You attended {presentCount} of {totalCount} classes.",
        };
      case 'sundayChill':
        return {
          roastTitle: "It's Sunday. Rest, {address}. 👑",
          neutralTitle: 'Sunday',
          body: 'No classes. No alarms. No problems.',
        };

      // ── Timetable ──
      case 'timetableUpdated':
        return {
          roastTitle: 'Plans changed. 👀',
          neutralTitle: 'Timetable updated',
          body: 'Your timetable has been updated.',
        };

      // ── System ──
      case 'testNotification':
        return {
          roastTitle: 'PULSE ping. 👀',
          neutralTitle: 'PULSE test',
          body: 'This is a test notification from PULSE.',
        };

      default:
        return {
          roastTitle: 'PULSE update. 👀',
          neutralTitle: 'PULSE update',
          body: 'Something changed on your timetable.',
        };
    }
  }
}
