import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { JsonStoreService } from '../common/store/json-store.service';
import { NotificationsService } from './notifications.service';
import { NotificationContentService } from './notification-content.service';
import { FcmService, FcmSendResult } from './fcm.service';
import { AttendanceWatcherService } from './attendance-watcher.service';

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
    data: { success: true, data: { report: [] } },
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

/** The real college day with statuses per class. */
function reportDay(statuses: string[]): unknown {
  const subjects = ['Math', 'Physics', 'Chemistry', 'English', 'CS', 'PE'];
  const staff = ['Arun', 'Divya', 'Ravi', 'Neha', 'Meera', 'Kiran'];
  return {
    success: true,
    data: {
      report: [
        {
          attendance_date: '2026-08-13',
          hourDetails: statuses.map((status, i) => ({
            subjectDetails: [
              {
                subjectName: subjects[i],
                hour: String(i + 1),
                attendanceStatus: status,
                staffName: staff[i],
              },
            ],
          })),
        },
      ],
    },
  };
}

describe('AttendanceWatcherService — absent roasts (first + last class only)', () => {
  let watcher: AttendanceWatcherService;
  let store: JsonStoreService;
  let notifications: NotificationsService;
  let auth: FakeAuth;
  let linways: FakeLinways;

  const session = { studentId: '4301', cookies: {}, authToken: 'fake-token' };

  beforeEach(() => {
    store = makeStore();
    const fcm = new FakeFcmService();
    notifications = new NotificationsService(store, new NotificationContentService(), fcm);
    auth = new FakeAuth();
    linways = new FakeLinways();
    watcher = new AttendanceWatcherService(
      auth as never,
      linways as never,
      store,
      notifications,
    );
  });

  const checkMarked = () =>
    (watcher as unknown as {
      checkMarkedRecords(session: unknown): Promise<void>;
    }).checkMarkedRecords(session);

  const dispatchedEvents = () => {
    const events: Array<Record<string, unknown>> = [];
    const dispatch = (studentId: string, event: Record<string, unknown>) => {
      events.push({ ...event, studentId });
      return Promise.resolve(true);
    };
    return { dispatch, events };
  };

  it('all 6 classes absent → exactly 2 roasts (first + last hour)', async () => {
    linways.response.data = reportDay(['0', '0', '0', '0', '0', '0']);
    const { dispatch, events } = dispatchedEvents();
    jest.spyOn(notifications, 'dispatchEvent').mockImplementation(dispatch);

    await checkMarked();

    expect(events).toHaveLength(2);
    expect(events.map((e) => e.subjectName)).toEqual(['Math', 'PE']);
    expect(events[0].staffName).toBe('Arun');
    expect(events[1].staffName).toBe('Kiran');
  });

  it('only middle classes absent → zero roasts', async () => {
    linways.response.data = reportDay(['1', '0', '0', '0', '1', '1']);
    const dispatch = jest.spyOn(notifications, 'dispatchEvent');

    await checkMarked();

    expect(dispatch).not.toHaveBeenCalled();
  });

  it('only the first class absent → one roast', async () => {
    linways.response.data = reportDay(['0', '1', '1', '1', '1', '1']);
    const dispatch = jest.spyOn(notifications, 'dispatchEvent');

    await checkMarked();

    expect(dispatch).toHaveBeenCalledTimes(1);
    expect(dispatch).toHaveBeenCalledWith(
      '4301',
      expect.objectContaining({
        type: 'attendanceMarkedAbsent',
        subjectName: 'Math',
        staffName: 'Arun',
      }),
    );
  });

  it('repolling the same report never re-sends the roast', async () => {
    // A registered device makes dispatchEvent mark events processed (dev
    // mode), so the snapshot advances and the second poll stays silent.
    await notifications.registerDevice('4301', { fcmToken: 't1' });
    linways.response.data = reportDay(['0', '1', '1', '1', '1', '0']);
    const dispatch = jest.spyOn(notifications, 'dispatchEvent');

    await checkMarked();
    await checkMarked();

    expect(dispatch).toHaveBeenCalledTimes(2); // first + last, once each
    const firstEvents = dispatch.mock.calls.map((c) => c[1].subjectName as string);
    expect(new Set(firstEvents)).toEqual(new Set(['Math', 'PE']));
  });

  it('registers a device so real dispatch semantics apply', async () => {
    await notifications.registerDevice('4301', { fcmToken: 't1' });
    linways.response.data = reportDay(['0', '0', '0', '0', '0', '0']);
    const { dispatch, events } = dispatchedEvents();
    jest.spyOn(notifications, 'dispatchEvent').mockImplementation(dispatch);

    await checkMarked();

    expect(events).toHaveLength(2);
  });

  it('passes the bearer token and normalizes DD-MM-YYYY report dates', async () => {
    const get = jest.spyOn(linways, 'get');
    linways.response.data = {
      success: true,
      data: {
        report: [
          {
            attendance_date: '13-08-2026',
            hourDetails: [
              {
                subjectDetails: [
                  {
                    subjectName: 'Math',
                    hour: '1',
                    attendanceStatus: '0',
                    staffName: 'Arun',
                  },
                ],
              },
            ],
          },
        ],
      },
    };
    const { dispatch, events } = dispatchedEvents();
    jest.spyOn(notifications, 'dispatchEvent').mockImplementation(dispatch);

    await checkMarked();

    expect(get).toHaveBeenCalledWith(expect.any(String), expect.any(Object), session.cookies, 'fake-token');
    expect(events).toHaveLength(1);
    // Snapshot key must use the normalized YYYY-MM-DD date.
    const snapshots = store.get<Record<string, { records: Record<string, string> }>>(
      'attendanceSnapshots',
    );
    const keys = Object.keys(snapshots?.['4301']?.records ?? {});
    expect(keys[0]).toContain('2026-08-13');
  });
});
