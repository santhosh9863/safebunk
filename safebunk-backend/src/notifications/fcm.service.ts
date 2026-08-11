import { Injectable, Logger } from '@nestjs/common';
import { initializeApp, getApps, cert } from 'firebase-admin/app';
import { getMessaging, TokenMessage } from 'firebase-admin/messaging';
import { NotificationContent } from './notification-content.service';
import {
  channelIdFor,
  NotificationEventPayload,
  NotificationEventType,
  ttlSecondsFor,
} from './notification-events';

export interface FcmSendResult {
  delivered: boolean;
  devMode: boolean;
  error?: string;
}

/**
 * Wraps firebase-admin FCM. The Admin SDK initializes lazily from
 * `FCM_SERVICE_ACCOUNT_PATH` (or the standard `GOOGLE_APPLICATION_CREDENTIALS`
 * env var). When no credentials are configured the service runs in dev mode:
 * it logs the would-be message instead of sending, so the whole pipeline is
 * testable before real FCM credentials exist.
 */
@Injectable()
export class FcmService {
  private readonly logger = new Logger(FcmService.name);

  private ensureInitialized(): void {
    if (getApps().length > 0) return;

    const serviceAccountPath =
      process.env.FCM_SERVICE_ACCOUNT_PATH || process.env.GOOGLE_APPLICATION_CREDENTIALS;

    if (!serviceAccountPath) {
      this.logger.warn(
        'FCM credentials not configured (FCM_SERVICE_ACCOUNT_PATH / GOOGLE_APPLICATION_CREDENTIALS). ' +
          'Running in dev mode — notifications will be logged, not pushed.',
      );
      return;
    }

    try {
      initializeApp({
        credential: cert(serviceAccountPath),
      });
      this.logger.log('Firebase Admin SDK initialized for FCM.');
    } catch (error) {
      this.logger.error(`Firebase Admin SDK initialization failed: ${error}`);
    }
  }

  async sendToDevice(
    token: string,
    event: NotificationEventPayload,
    content: NotificationContent,
  ): Promise<FcmSendResult> {
    this.ensureInitialized();

    if (getApps().length === 0) {
      this.logger.log(
        `[FCM][dev] ${event.type} -> ${token.slice(0, 12)}... | ${content.title} | ${content.body}`,
      );
      return { delivered: false, devMode: true };
    }

    const type: NotificationEventType = event.type;
    const message: TokenMessage = {
      token,
      notification: {
        title: content.title,
        body: content.body,
      },
      data: {
        type: event.type,
        eventId: (event.eventId as string) || '',
        studentId: (event.studentId as string) || '',
        subjectName: event.subjectName || '',
      },
      android: {
        priority: 'high',
        ttl: ttlSecondsFor(type) * 1000,
        notification: {
          channelId: channelIdFor(type),
          priority: type === 'enteredDangerZone' ? ('high' as const) : ('default' as const),
        },
      },
    };

    try {
      const messageId = await getMessaging().send(message);
      this.logger.log(`[FCM] Sent ${event.type} (${messageId})`);
      return { delivered: true, devMode: false };
    } catch (error) {
      const code = (error as { code?: string }).code;
      if (
        code === 'messaging/registration-token-not-registered' ||
        code === 'messaging/invalid-registration-token' ||
        code === 'messaging/invalid-argument'
      ) {
        this.logger.warn(`[FCM] Invalid token for ${event.type}: ${code}`);
        return { delivered: false, devMode: false, error: 'invalid-token' };
      }
      this.logger.error(`[FCM] Send failed for ${event.type}: ${error}`);
      return { delivered: false, devMode: false, error: code || 'unknown' };
    }
  }
}
