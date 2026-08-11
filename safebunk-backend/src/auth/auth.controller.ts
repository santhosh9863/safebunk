import { Controller, Post, Body, HttpCode, HttpStatus, Headers, UnauthorizedException } from '@nestjs/common';
import { ApiOperation, ApiTags, ApiBearerAuth } from '@nestjs/swagger';
import { AuthService } from './auth.service';
import { LoginDto } from './dto/login.dto';
import { LoginResponseDto } from './dto/login-response.dto';
import { ApiResponse } from '../common/dto/api-response.dto';

@ApiTags('Auth')
@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post('login')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Login with Linways credentials' })
  async login(@Body() dto: LoginDto): Promise<ApiResponse<LoginResponseDto>> {
    const { session, studentInfo } = await this.authService.login(dto.username, dto.password);

    return ApiResponse.ok({
      accessToken: session.token,
      student: {
        studentId: studentInfo.studentId,
        name: studentInfo.name,
        batch: studentInfo.batch,
        username: studentInfo.username,
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
