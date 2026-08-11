import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { ApiOperation, ApiTags, ApiBearerAuth } from '@nestjs/swagger';
import { AuthGuard } from '../common/guards/auth.guard';
import { CurrentUser, AuthenticatedUser } from '../common/decorators/current-user.decorator';
import { ProfileService } from './profile.service';
import { ApiResponse } from '../common/dto/api-response.dto';

@ApiTags('Profile')
@Controller()
@UseGuards(AuthGuard)
@ApiBearerAuth()
export class ProfileController {
  constructor(private readonly profileService: ProfileService) {}

  @Get('profile')
  @ApiOperation({ summary: 'Get student profile information' })
  async getProfile(@CurrentUser() user: AuthenticatedUser): Promise<ApiResponse<any>> {
    const profile = await this.profileService.getProfile(user.studentId, user.cookies);
    return ApiResponse.ok(profile);
  }

  @Get('student/get-student-basic-details')
  @ApiOperation({ summary: '[Legacy] Get student basic details (Linways path)' })
  async getStudentBasicDetailsLegacy(
    @CurrentUser() user: AuthenticatedUser,
    @Query('studentId') studentIdParam?: string,
  ): Promise<any> {
    const sid = studentIdParam || user.studentId;
    const profile = await this.profileService.getProfile(sid, user.cookies);
    return { success: true, data: { properties: { currentBatchId: profile.batchId } } };
  }
}
