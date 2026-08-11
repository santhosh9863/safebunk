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
    const title = roasting ? template.roastTitle : template.neutralTitle;
    return {
      title,
      body: this.fill(template.body, event),
    };
  }

  private fill(template: string, event: NotificationEventPayload): string {
    const percentage =
      event.percentage !== undefined
        ? `${this.trimZeroes(event.percentage)}%`
        : '';
    const target = event.target !== undefined ? `${event.target}%` : '75%';
    const subject = event.subjectName || 'this class';
    return template
      .replaceAll('{subjectName}', subject)
      .replaceAll('{percentage}', percentage)
      .replaceAll('{target}', target)
      .replaceAll('{minutes}', String(event.minutes ?? ''));
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
          roastTitle: 'She waited. You ghosted. 💀',
          neutralTitle: 'Attendance marked',
          body: '{subjectName} has been marked absent.',
        };

      // ── Percentage transitions ──
      case 'attendanceImproved':
        return {
          roastTitle: 'She noticed. 👀',
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
          body: '100% attendance. Bro practically lives on campus.',
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
          roastTitle: "She's waiting. 👀",
          neutralTitle: 'Upcoming class',
          body: '{subjectName} starts in 30 minutes.',
        };
      case 'classReminder10Min':
        return {
          roastTitle: "Don't ghost her. 💀",
          neutralTitle: 'Upcoming class',
          body: '{subjectName} starts in 10 minutes.',
        };
      case 'classReminder5Min':
        return {
          roastTitle: "She's getting impatient. 😭",
          neutralTitle: 'Upcoming class',
          body: '{subjectName} starts in 5 minutes.',
        };
      case 'classStarting':
        return {
          roastTitle: 'Move, bro. 😭',
          neutralTitle: 'Class starting now',
          body: '{subjectName} is starting now.',
        };
      case 'classMissed':
        return {
          roastTitle: 'Left her waiting. 💀',
          neutralTitle: 'Class missed',
          body: 'You missed {subjectName}.',
        };
      case 'nextClass':
        return {
          roastTitle: 'Round two. 😏',
          neutralTitle: 'Next class',
          body: '{subjectName} starts in {minutes} minutes.',
        };

      // ── Timetable ──
      case 'timetableUpdated':
        return {
          roastTitle: 'She changed plans. 👀',
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
