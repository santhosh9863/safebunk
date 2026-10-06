import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { JsonStoreService } from '../common/store/json-store.service';
import { NotificationsService } from './notifications.service';
import { NotificationContentService } from './notification-content.service';
import { FcmService, FcmSendResult } from './fcm.service';
import { NotificationEventPayload } from './notification-events';
import { NotificationPreferencesDto } from './dto/notification-preferences.dto';
import {
  TimetableEntry,
  TimetableWatcherService,
  PlannedReminder,
} from './timetable-watcher.service';

class FakeFcmService extends FcmService {
  devMode = true;
  override get isDevMode(): boolean {
    return this.devMode;
  }
  override async sendToDevice(): Promise<FcmSendResult> {
    return { delivered: false, devMode: true };
  }
}

class FakeAuth {
  active: any[] = [];
  getActiveSessions() {
    return this.active;
  }
}

class FakeLinways {
  response: { status: number; data: unknown } = {
    status: 200,
    data: { success: true, data: { classes: [] } },
  };
  async get() {
    return this.response;
  }
}

function makeStore(): JsonStoreService {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'pulse-store-'));
  process.env.PULSE_STORE_PATH = path.join(dir, 'pulse-store.json');
  return new JsonStoreService();
}

/** The real college day: 8:30→9:30, 9:30→10:25, break, 10:50→11:50,
 * 11:50→12:45, lunch, 1:30→2:30, 2:30→3:30. */
const TODAY = '2026-08-13';
function realDay(): TimetableEntry[] {
  const slots: Array<[string, string, string, string, string]> = [
    ['p1', 'Math', 'Arun', '08:30', '09:30'],
    ['p2', 'Physics', 'Divya', '09:30', '10:25'],
    ['p3', 'Chemistry', 'Ravi', '10:50', '11:50'],
    ['p4', 'English', 'Neha', '11:50', '12:45'],
    ['p5', 'CS', 'Meera', '13:30', '14:30'],
    ['p6', 'PE', 'Kiran', '14:30', '15:30'],
  ];
  return slots.map(([id, subject, staff, from, to]) => ({
    id,
    subjectName: subject,
    staffName: staff,
    fromTime: from,
    toTime: to,
    date: TODAY,
    hour: id,
  }));
}

describe('TimetableWatcherService — signature-moment planning', () => {
  let watcher: TimetableWatcherService;
  let store: JsonStoreService;
  let notifications: NotificationsService;
  let auth: FakeAuth;
  let linways: FakeLinways;

  beforeEach(() => {
    store = makeStore();
    const fcm = new FakeFcmService();
    notifications = new NotificationsService(store, new NotificationContentService(), fcm);
    auth = new FakeAuth();
    linways = new FakeLinways();
    watcher = new TimetableWatcherService(
      auth as never,
      linways as never,
      store,
      notifications,
    );
  });

  const planned = () =>
    store.getOr<PlannedReminder[]>(
      'plannedReminders',
      [],
    ).filter((r) => r.studentId === '4301');

  it('plans exactly the 4 signature moments for the real college day', async () => {
    // Fake "now" = 08:00 so every class is still upcoming.
    const originalNow = Date.now;
    const fakeNow = new Date('2026-08-13T08:00:00').getTime();
    Date.now = () => fakeNow;
    try {
      await watcher.replanReminders('4301', realDay());
      const reminders = planned();

      // First class lead (8:20) + post-lunch nextClass (13:20) + last class
      // lead (14:20) + wrap-up (15:45).
      expect(reminders).toHaveLength(4);

      const byType = new Map(reminders.map((r) => [r.type, r]));
      const lead = byType.get('classReminder10Min');
      const next = byType.get('nextClass');
      const wrap = byType.get('dayWrapUp');

      expect(lead).toBeDefined();
      expect(byType.get('classReminder10Min')).toBeDefined();
      expect(next).toBeDefined();
      expect(wrap).toBeDefined();

      // Post-lunch nextClass targets CS (13:30) at 13:20, minutes = 10,
      // and carries the faculty name for the message wording.
      expect(next?.subjectName).toBe('CS');
      expect(next?.staffName).toBe('Meera');
      expect(next?.minutes).toBe(10);
      expect(next?.fireAt).toBe(new Date('2026-08-13T13:20:00').getTime());

      // Wrap-up fires 15 min after the last class (15:30) ends → 15:45.
      expect(wrap?.fireAt).toBe(new Date('2026-08-13T15:45:00').getTime());
      expect(wrap?.totalCount).toBe(6);
    } finally {
      Date.now = originalNow;
    }
  });

  it('uses a 30-min lead when configured', async () => {
    await notifications.setPreferences('4301', {
      reminderTiming: '30' as NotificationPreferencesDto['reminderTiming'],
    });
    const originalNow = Date.now;
    Date.now = () => new Date('2026-08-13T08:00:00').getTime();
    try {
      await watcher.replanReminders('4301', realDay());
      const reminders = planned();
      const leads = reminders.filter((r) => r.type === 'classReminder30Min');
      // First class (8:30) − 30 = 8:00; last class (14:30) − 30 = 14:00.
      expect(leads.map((r) => r.fireAt)).toEqual([
        new Date('2026-08-13T08:00:00').getTime(),
        new Date('2026-08-13T14:00:00').getTime(),
      ]);
    } finally {
      Date.now = originalNow;
    }
  });

  it('skips the lunch message when no gap reaches 60 minutes', async () => {
    const entries = realDay().filter((e) => e.id !== 'p3' && e.id !== 'p4');
    // Only 8:30, 9:30, 13:30, 14:30 remain — the 4h gap is lunch.
    const originalNow = Date.now;
    Date.now = () => new Date('2026-08-13T08:00:00').getTime();
    try {
      await watcher.replanReminders('4301', entries);
      const types = planned().map((r) => r.type);
      expect(types).toContain('nextClass');
      expect(types).toContain('dayWrapUp');
    } finally {
      Date.now = originalNow;
    }
  });

  it('plans nothing when reminders are disabled', async () => {
    await notifications.setPreferences('4301', { classRemindersEnabled: false });
    await watcher.replanReminders('4301', realDay());
    expect(planned()).toHaveLength(0);
  });

  it('cancels existing reminders when there are no upcoming classes', async () => {
    const originalNow = Date.now;
    Date.now = () => new Date('2026-08-13T08:00:00').getTime();
    try {
      await watcher.replanReminders('4301', realDay());
      expect(planned().length).toBeGreaterThan(0);

      Date.now = () => new Date('2026-08-13T18:00:00').getTime();
      await watcher.replanReminders('4301', realDay());
      expect(planned()).toHaveLength(0);
    } finally {
      Date.now = originalNow;
    }
  });

  it('dispatches sundayChill with a per-week deterministic eventId', async () => {
    auth.active = [{ studentId: '4301' }];
    const dispatch = jest.spyOn(notifications, 'dispatchEvent');
    await notifications.registerDevice('4301', { fcmToken: 't1' });
    await watcher.fireSundayChill();
    expect(dispatch).toHaveBeenCalledWith(
      '4301',
      expect.objectContaining({ type: 'sundayChill' }),
    );
  });

  it('parses the real get-my-daily-schedule shape end-to-end', async () => {
    auth.active = [
      { studentId: '4301', cookies: {}, authToken: 'fake-token' },
    ];
    linways.response.data = {
      success: true,
      data: {
        classes: [
          {
            time: '08:30 AM - 09:30 AM',
            duration: '1h',
            courseName: '24BCA51P - WP LAB - Web Programming Lab',
            facultyName: 'Geetha.S',
            courseCode: '24BCA51P - WP LAB',
            attendanceStatus: 'Present',
          },
          {
            time: '08:30 AM - 09:30 AM',
            duration: '1h',
            courseName: '24BCA51P - WP LAB - Web Programming Lab',
            facultyName: 'Abhilash Shetty',
            courseCode: '24BCA51P - WP LAB',
            attendanceStatus: 'Present',
          },
          {
            time: '01:30 PM - 02:30 PM',
            duration: '1h',
            courseName: 'ECO-DSC-E1 - MICRO ECONOMICS',
            facultyName: 'Priya M',
            courseCode: 'ECO-DSC-E1',
            attendanceStatus: 'Present',
          },
          {
            time: '02:30 PM - 03:30 PM',
            duration: '1h',
            courseName: 'Kannada',
            facultyName: 'Lakshmi',
            courseCode: 'KAN1',
            attendanceStatus: 'Present',
          },
        ],
      },
    };
    const get = jest.spyOn(linways, 'get');
    const originalNow = Date.now;
    Date.now = () => new Date('2026-08-13T08:00:00').getTime();
    try {
      await notifications.registerDevice('4301', { fcmToken: 't1' });
      await watcher.watchTimetables();

      // Bearer token + no query params, matching the working request.
      expect(get).toHaveBeenCalledWith(
        expect.any(String),
        undefined,
        expect.any(Object),
        'fake-token',
      );

      const reminders = planned();
      const subjects = reminders.map((r) => r.subjectName);
      // Duplicate 08:30 slot collapsed to one class; code prefixes stripped.
      expect(subjects.filter((s) => s === 'Web Programming Lab')).toHaveLength(1);
      expect(subjects).toContain('MICRO ECONOMICS');
      expect(subjects).toContain('Kannada');

      const first = reminders.find((r) => r.type === 'classReminder10Min');
      expect(first).toBeDefined();
      expect(first?.subjectName).toBe('Web Programming Lab');
      expect(first?.staffName).toBe('Geetha.S');
      expect(first?.fireAt).toBe(new Date('2026-08-13T08:20:00').getTime());

      const next = reminders.find((r) => r.type === 'nextClass');
      // Longest gap (09:30 → 13:30) is lunch → nextClass at 13:20.
      expect(next?.subjectName).toBe('MICRO ECONOMICS');
      expect(next?.staffName).toBe('Priya M');
      expect(next?.fireAt).toBe(new Date('2026-08-13T13:20:00').getTime());
    } finally {
      Date.now = originalNow;
    }
  });
});
