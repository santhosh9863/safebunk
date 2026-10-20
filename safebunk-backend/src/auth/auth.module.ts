import { Global, Module } from '@nestjs/common';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { StaffAuthService } from './staff-auth.service';
import { LoginRateLimiterService } from './login-rate-limiter.service';
import { NotificationsModule } from '../notifications/notifications.module';

@Global()
@Module({
  imports: [NotificationsModule],
  controllers: [AuthController],
  providers: [AuthService, StaffAuthService, LoginRateLimiterService],
  exports: [AuthService],
})
export class AuthModule {}
