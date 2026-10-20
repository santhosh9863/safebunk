import {
  Controller,
  Post,
  Body,
  HttpCode,
  HttpStatus,
  Headers,
  Ip,
  UnauthorizedException,
} from '@nestjs/common';
import { ApiOperation, ApiTags, ApiBearerAuth } from '@nestjs/swagger';
import { AuthService } from './auth.service';
import { StaffAuthService } from './staff-auth.service';
import { LoginRateLimiterService } from './login-rate-limiter.service';
import { LoginDto } from './dto/login.dto';
import { LoginResponseDto } from './dto/login-response.dto';
import { StaffLoginDto } from './dto/staff-login.dto';
import { StaffLoginResponseDto } from './dto/staff-login-response.dto';
import { ApiResponse } from '../common/dto/api-response.dto';
import { NotificationsService } from '../notifications/notifications.service';

@ApiTags('Auth')
@Controller('auth')
export class AuthController {
  constructor(
    private readonly authService: AuthService,
    private readonly staffAuthService: StaffAuthService,
    private readonly notificationsService: NotificationsService,
    private readonly loginRateLimiter: LoginRateLimiterService,
  ) {}

  @Post('login')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Login with Linways credentials' })
  async login(
    @Body() dto: LoginDto,
    @Ip() ip: string,
  ): Promise<ApiResponse<LoginResponseDto>> {
    this.loginRateLimiter.consume('student', ip, dto.username);

    const { session, studentInfo } = await this.authService.login(dto.username, dto.password);
    this.loginRateLimiter.resetAccount('student', dto.username);

    // Auto-detect gender from Linways and store it — but never override a
    // gender the user already picked manually.
    if (studentInfo.gender) {
      const prefs = this.notificationsService.getPreferences(studentInfo.studentId);
      if (!prefs.gender) {
        await this.notificationsService.setPreferences(studentInfo.studentId, {
          gender: studentInfo.gender,
        });
      }
    }

    return ApiResponse.ok({
      accessToken: session.token,
      student: {
        studentId: studentInfo.studentId,
        name: studentInfo.name,
        gender: studentInfo.gender,
        batch: studentInfo.batch,
        username: studentInfo.username,
      },
    });
  }

  @Post('staff/login')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Login with a locally provisioned staff/admin account' })
  async staffLogin(
    @Body() dto: StaffLoginDto,
    @Ip() ip: string,
  ): Promise<ApiResponse<StaffLoginResponseDto>> {
    this.loginRateLimiter.consume('staff', ip, dto.username);

    const { session, staff } = await this.staffAuthService.login(
      dto.username,
      dto.password,
    );
    this.loginRateLimiter.resetAccount('staff', dto.username);

    return ApiResponse.ok({
      accessToken: session.token,
      staff: {
        id: staff.id,
        username: staff.username,
        displayName: staff.displayName,
        role: staff.role,
      },
    });
  }

  @Post('logout')
  @HttpCode(HttpStatus.OK)
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Logout and invalidate session' })
  async logout(@Headers('authorization') auth: string): Promise<ApiResponse<null>> {
    if (!auth?.startsWith('Bearer ')) {
      throw new UnauthorizedException('Invalid token');
    }
    const token = auth.slice(7);
    await this.authService.logout(token);
    return ApiResponse.ok(null, 'Logged out successfully');
  }
}
