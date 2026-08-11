import { Injectable, Logger } from '@nestjs/common';
import { JsonStoreService } from '../common/store/json-store.service';
import { NotificationContentService } from './notification-content.service';
import { FcmService } from './fcm.service';
import { NotificationEventPayload } from './notification-events';
import {
  DEFAULT_PREFERENCES,
  NotificationPreferencesDto,
} from './dto/notification-preferences.dto';
import { DevicePlatform, RegisterDeviceDto } from './dto/register-device.dto';

export interface DeviceRegistration {
  studentId: string;
  fcmToken: string;
  platform: DevicePlatform;
  createdAt: number;
  updatedAt: number;
  enabled: boolean;
}

interface ProcessedEvent {
  processedAt: number;
}

const STORE_DEVICES = 'devices';
const STORE_PREFERENCES = 'preferences';
const STORE_EVENTS = 'processedEvents';

/**
 * Device registrations, per-student preferences and deterministic event
 * deduplication. A student may have multiple devices — every active device
 * receives each event exactly once.
 */
@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);

  constructor(
    private readonly store: JsonStoreService,
    private readonly contentService: NotificationContentService,
    private readonly fcmService: FcmService,
  ) {}

  // ── Devices ─────────────────────────────────────────────────

  getDevices(studentId: string): DeviceRegistration[] {
    const devices = this.store.getOr<DeviceRegistration[]>(STORE_DEVICES, []);
    return devices.filter((d) => d.studentId === studentId);
  }

  async registerDevice(
    studentId: string,
    dto: RegisterDeviceDto,
  ): Promise<DeviceRegistration> {
    const devices = this.store.getOr<DeviceRegistration[]>(STORE_DEVICES, []);
    const now = Date.now();

    // A token belongs to exactly one device: drop any other entry carrying
    // this token (e.g. re-registration after reinstall, or token rotation).
    const otherDevices = devices.filter((d) => d.fcmToken !== dto.fcmToken);
    const existing = devices.find(
      (d) => d.studentId === studentId && d.fcmToken === dto.fcmToken,
    );

    const registration: DeviceRegistration = existing
      ? { ...existing, enabled: dto.enabled ?? existing.enabled, updatedAt: now }
      : {
          studentId,
          fcmToken: dto.fcmToken,
          platform: dto.platform ?? DevicePlatform.android,
          createdAt: now,
          updatedAt: now,
          enabled: dto.enabled ?? true,
        };

    this.store.set(STORE_DEVICES, [...otherDevices, registration]);
    this.logger.log(`Device registered for student ${studentId} (${devices.length + (existing ? 0 : 1)} total)`);
    return registration;
  }

  async unregisterDevice(studentId: string, fcmToken: string): Promise<void> {
    const devices = this.store.getOr<DeviceRegistration[]>(STORE_DEVICES, []);
    this.store.set(
      STORE_DEVICES,
      devices.filter((d) => !(d.studentId === studentId && d.fcmToken === fcmToken)),
    );
    this.logger.log(`Device unregistered for student ${studentId}`);
  }

  /** Remove a token reported as invalid by FCM (called from FcmService flow). */
  async deactivateToken(studentId: string, fcmToken: string): Promise<void> {
    const devices = this.store.getOr<DeviceRegistration[]>(STORE_DEVICES, []);
    this.store.set(
      STORE_DEVICES,
      devices.map((d) =>
        d.studentId === studentId && d.fcmToken === fcmToken
          ? { ...d, enabled: false }
          : d,
      ),
    );
  }

  // ── Preferences ─────────────────────────────────────────────

  getPreferences(studentId: string): NotificationPreferencesDto {
    const prefs = this.store.get<Record<string, NotificationPreferencesDto>>(STORE_PREFERENCES);
    const stored = prefs?.[studentId];
    return stored ? { ...DEFAULT_PREFERENCES, ...stored } : { ...DEFAULT_PREFERENCES };
  }

  async setPreferences(
    studentId: string,
    patch: NotificationPreferencesDto,
  ): Promise<NotificationPreferencesDto> {
    const prefs = this.store.getOr<Record<string, NotificationPreferencesDto>>(STORE_PREFERENCES, {});
    prefs[studentId] = { ...DEFAULT_PREFERENCES, ...prefs[studentId], ...patch };
    this.store.set(STORE_PREFERENCES, prefs);
    return this.getPreferences(studentId);
  }

  // ── Deduplication ───────────────────────────────────────────

  isProcessed(eventId: string): boolean {
    const events = this.store.getOr<Record<string, ProcessedEvent>>(STORE_EVENTS, {});
    return eventId in events;
  }

  async markProcessed(eventId: string): Promise<void> {
    const events = this.store.getOr<Record<string, ProcessedEvent>>(STORE_EVENTS, {});
    events[eventId] = { processedAt: Date.now() };
    this.store.set(STORE_EVENTS, events);
  }

  getRecentEventIds(studentId: string, limit = 10): string[] {
    const events = this.store.getOr<Record<string, ProcessedEvent>>(STORE_EVENTS, {});
    return Object.entries(events)
      .filter(([id]) => id.startsWith(`${studentId}|`))
      .sort((a, b) => b[1].processedAt - a[1].processedAt)
      .slice(0, limit)
      .map(([id]) => id);
  }

  // ── Dispatch ────────────────────────────────────────────────

  /**
   * Build the message (respecting preferences + roasting mode) and deliver to
   * EVERY enabled device of the student. Events must carry a deterministic
   * `eventId` — duplicates are silently dropped here.
   */
  async dispatchEvent(
    studentId: string,
    event: NotificationEventPayload,
  ): Promise<boolean> {
    const eventId = event.eventId as string;
    if (!eventId) {
      this.logger.warn(`Event without eventId dropped for ${studentId}: ${event.type}`);
      return false;
    }

    if (this.isProcessed(eventId)) return false;

    const preferences = this.getPreferences(studentId);
    if (preferences.masterEnabled === false) return false;

    if (!this.eventEnabled(preferences, event.type)) return false;

    const devices = this.getDevices(studentId).filter((d) => d.enabled);
    if (devices.length === 0) {
      // No reachable device yet (user logged out / token not registered).
      // Leave the event unprocessed so it can be delivered later if a device
      // registers while the event is still meaningful. Watchers and the
      // scheduler re-attempt on their next tick.
      return false;
    }

    const content = this.contentService.build(event, preferences);
    const fullEvent: NotificationEventPayload = {
      ...event,
      eventId,
      studentId,
    };

    let anyDelivered = false;
    let anyInvalidToken = false;
    for (const device of devices) {
      const result = await this.fcmService.sendToDevice(device.fcmToken, fullEvent, content);
      if (result.error === 'invalid-token') {
        anyInvalidToken = true;
        await this.deactivateToken(studentId, device.fcmToken);
      }
      if (result.delivered) anyDelivered = true;
    }

    if (this.fcmService.isDevMode) {
      // Dev mode: mark processed so delivery is idempotent once real FCM
      // credentials are configured.
      await this.markProcessed(eventId);
      return anyDelivered;
    }

    // Only mark the event processed once it actually reached FCM (or every
    // device token was invalid). Transient failures stay unprocessed so the
    // watchers / scheduler retry — FCM itself queues the message for offline
    // phones until the per-type TTL expires.
    if (anyDelivered || anyInvalidToken) {
      await this.markProcessed(eventId);
    }
    return anyDelivered;
  }

  async sendTestNotification(studentId: string): Promise<boolean> {
    return this.dispatchEvent(studentId, {
      type: 'testNotification',
      eventId: `${studentId}|test|${Date.now()}`,
    });
  }

  private eventEnabled(
    preferences: NotificationPreferencesDto,
    type: string,
  ): boolean {
    switch (type) {
      case 'attendanceMarkedPresent':
      case 'attendanceMarkedAbsent':
      case 'attendanceImproved':
      case 'attendanceDropped':
      case 'enteredSafeZone':
      case 'leftSafeZone':
      case 'enteredDangerZone':
      case 'recoveredFromDanger':
      case 'perfectAttendance':
        return preferences.attendanceEnabled !== false;
      case 'reached80':
      case 'reached90':
      case 'reached95':
        return (
          preferences.attendanceEnabled !== false &&
          preferences.milestonesEnabled !== false
        );
      case 'classReminder30Min':
      case 'classReminder10Min':
      case 'classReminder5Min':
      case 'classStarting':
      case 'classMissed':
      case 'nextClass':
        return preferences.classRemindersEnabled !== false;
      case 'timetableUpdated':
        return preferences.timetableEnabled !== false;
      default:
        return true;
    }
  }
}
