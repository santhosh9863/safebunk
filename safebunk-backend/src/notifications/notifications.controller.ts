import { Body, Controller, Get, Post, Put, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { AuthGuard } from '../common/guards/auth.guard';
import { CurrentUser, AuthenticatedUser } from '../common/decorators/current-user.decorator';
import { AuthService } from '../auth/auth.service';
import { ApiResponse } from '../common/dto/api-response.dto';
import { NotificationsService } from './notifications.service';
import {
  RegisterDeviceDto,
  UnregisterDeviceDto,
} from './dto/register-device.dto';
import { NotificationPreferencesDto } from './dto/notification-preferences.dto';

@ApiTags('Notifications')
@Controller('notifications')
@UseGuards(AuthGuard)
@ApiBearerAuth()
export class NotificationsController {
  constructor(
    private readonly notificationsService: NotificationsService,
    private readonly authService: AuthService,
  ) {}

  @Post('register-device')
  @ApiOperation({ summary: 'Register this device for push notifications' })
  async registerDevice(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: RegisterDeviceDto,
  ): Promise<ApiResponse<unknown>> {
    const registration = await this.notificationsService.registerDevice(
      user.studentId,
      dto,
    );
    return ApiResponse.ok({
      registered: true,
      device: {
        platform: registration.platform,
        enabled: registration.enabled,
        updatedAt: registration.updatedAt,
      },
    });
  }

  @Post('unregister-device')
  @ApiOperation({ summary: 'Remove this device from push delivery' })
  async unregisterDevice(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: UnregisterDeviceDto,
  ): Promise<ApiResponse<unknown>> {
    await this.notificationsService.unregisterDevice(user.studentId, dto.fcmToken);
    return ApiResponse.ok({ unregistered: true });
  }

  @Get('preferences')
  @ApiOperation({ summary: 'Get this student\'s notification preferences' })
  async getPreferences(
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<ApiResponse<NotificationPreferencesDto>> {
    return ApiResponse.ok(this.notificationsService.getPreferences(user.studentId));
  }

  @Put('preferences')
  @ApiOperation({ summary: 'Update this student\'s notification preferences' })
  async setPreferences(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: NotificationPreferencesDto,
  ): Promise<ApiResponse<NotificationPreferencesDto>> {
    return ApiResponse.ok(
      await this.notificationsService.setPreferences(user.studentId, dto),
    );
  }

  @Get('status')
  @ApiOperation({ summary: 'Notification status for this student (devices + recent events)' })
  async status(
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<ApiResponse<unknown>> {
    const devices = this.notificationsService.getDevices(user.studentId);
    return ApiResponse.ok({
      deviceCount: devices.length,
      devices: devices.map((d) => ({
        platform: d.platform,
        enabled: d.enabled,
        updatedAt: d.updatedAt,
      })),
      preferences: this.notificationsService.getPreferences(user.studentId),
      recentEventIds: this.notificationsService.getRecentEventIds(user.studentId),
      server: {
        activeSessions: this.authService.getActiveSessions().length,
        plannedReminders: this.notificationsService.getPlannedRemindersCount(),
        devMode: this.notificationsService.isDevMode,
      },
    });
  }

  @Post('test')
  @ApiOperation({ summary: 'Send a test notification to this student\'s own devices (authenticated only)' })
  async test(
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<ApiResponse<unknown>> {
    const delivered = await this.notificationsService.sendTestNotification(
      user.studentId,
    );
    return ApiResponse.ok({ delivered });
  }
}
