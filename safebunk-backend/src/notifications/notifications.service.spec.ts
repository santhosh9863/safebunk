import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import { JsonStoreService } from '../common/store/json-store.service';
import { NotificationContentService } from './notification-content.service';
import { FcmService, FcmSendResult } from './fcm.service';
import { NotificationEventPayload } from './notification-events';
import { NotificationsService } from './notifications.service';
import { DevicePlatform } from './dto/register-device.dto';

class FakeFcmService extends FcmService {
  devMode = true;
  sent: Array<{ token: string; event: NotificationEventPayload }> = [];
  result: FcmSendResult = { delivered: false, devMode: true };

  constructor() {
    super();
  }

  override get isDevMode(): boolean {
    return this.devMode;
  }

  override async sendToDevice(
    token: string,
    event: NotificationEventPayload,
    _content: { title: string; body: string },
  ): Promise<FcmSendResult> {
    this.sent.push({ token, event });
    return this.result;
  }
}

function makeStore(): JsonStoreService {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'pulse-store-'));
  process.env.PULSE_STORE_PATH = path.join(dir, 'pulse-store.json');
  return new JsonStoreService();
}

const event = (id: string, type = 'attendanceMarkedPresent'): NotificationEventPayload => ({
  type: type as NotificationEventPayload['type'],
  eventId: id,
  subjectName: 'Data Analytics',
});

describe('NotificationsService', () => {
  let service: NotificationsService;
  let store: JsonStoreService;
  let fcm: FakeFcmService;

  beforeEach(async () => {
    store = makeStore();
    fcm = new FakeFcmService();
    service = new NotificationsService(store, new NotificationContentService(), fcm);
    await service.registerDevice('4301', { fcmToken: 'token-a', platform: DevicePlatform.android });
  });

  afterEach(() => {
    fcm.sent = [];
  });

  it('registers multiple devices per student', async () => {
    await service.registerDevice('4301', { fcmToken: 'token-b' });
    const devices = service.getDevices('4301');
    expect(devices).toHaveLength(2);
    expect(devices.map((d) => d.fcmToken).sort()).toEqual(['token-a', 'token-b']);
  });

  it('re-registering the same token keeps a single entry', async () => {
    await service.registerDevice('4301', { fcmToken: 'token-a' });
    expect(service.getDevices('4301')).toHaveLength(1);
  });

  it('a token moved to a new student removes the old registration', async () => {
    await service.registerDevice('9999', { fcmToken: 'token-a' });
    expect(service.getDevices('9999')).toHaveLength(1);
    expect(service.getDevices('4301')).toHaveLength(0);
  });

  it('deduplicates: the same eventId is only dispatched once', async () => {
    fcm.devMode = false;
    fcm.result = { delivered: true, devMode: false };
    const first = await service.dispatchEvent('4301', event('4301|att|d|s|1'));
    const second = await service.dispatchEvent('4301', event('4301|att|d|s|1'));
    expect(first).toBe(true);
    expect(second).toBe(false);
    expect(fcm.sent).toHaveLength(1);
  });

  it('sends to every enabled device', async () => {
    await service.registerDevice('4301', { fcmToken: 'token-b' });
    fcm.devMode = false;
    fcm.result = { delivered: true, devMode: false };
    await service.dispatchEvent('4301', event('e1'));
    expect(fcm.sent).toHaveLength(2);
  });

  it('respects the master switch', async () => {
    await service.setPreferences('4301', { masterEnabled: false });
    await service.dispatchEvent('4301', event('e1'));
    expect(fcm.sent).toHaveLength(0);
    expect(service.isProcessed('e1')).toBe(false);
  });

  it('respects per-category switches', async () => {
    await service.setPreferences('4301', { attendanceEnabled: false });
    await service.dispatchEvent('4301', event('e1', 'attendanceMarkedPresent'));
    expect(fcm.sent).toHaveLength(0);
  });

  it('gates timetable updates behind timetableEnabled', async () => {
    await service.setPreferences('4301', { timetableEnabled: false });
    await service.dispatchEvent('4301', event('e1', 'timetableUpdated'));
    expect(fcm.sent).toHaveLength(0);
  });

  it('keeps an event unprocessed on a transient FCM failure (retry)', async () => {
    fcm.devMode = false;
    fcm.result = { delivered: false, devMode: false, error: 'messaging/unknown-error' };
    await service.dispatchEvent('4301', event('e1'));
    expect(service.isProcessed('e1')).toBe(false);
  });

  it('marks processed when delivered, then never resends', async () => {
    fcm.devMode = false;
    fcm.result = { delivered: true, devMode: false };
    await service.dispatchEvent('4301', event('e1'));
    expect(service.isProcessed('e1')).toBe(true);

    fcm.result = { delivered: false, devMode: false, error: 'messaging/unknown-error' };
    await service.dispatchEvent('4301', event('e1'));
    expect(fcm.sent).toHaveLength(1);
  });

  it('marks processed and deactivates the token when FCM reports it invalid', async () => {
    fcm.devMode = false;
    fcm.result = { delivered: false, devMode: false, error: 'invalid-token' };
    await service.dispatchEvent('4301', event('e1'));
    expect(service.isProcessed('e1')).toBe(true);
    expect(service.getDevices('4301').every((d) => !d.enabled)).toBe(true);
  });

  it('does not mark processed when there are no enabled devices', async () => {
    await service.unregisterDevice('4301', 'token-a');
    await service.dispatchEvent('4301', event('e1'));
    expect(service.isProcessed('e1')).toBe(false);
  });

  it('marks processed in dev mode so real delivery is idempotent later', async () => {
    fcm.devMode = true;
    await service.dispatchEvent('4301', event('e1'));
    expect(service.isProcessed('e1')).toBe(true);
  });
});
