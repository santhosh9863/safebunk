import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { ApiOperation, ApiTags, ApiBearerAuth } from '@nestjs/swagger';
import { AuthGuard } from '../common/guards/auth.guard';
import { CurrentUser, AuthenticatedUser } from '../common/decorators/current-user.decorator';
import { AttendanceService } from './attendance.service';
import { ApiResponse } from '../common/dto/api-response.dto';

@ApiTags('Attendance')
@Controller()
@UseGuards(AuthGuard)
@ApiBearerAuth()
export class AttendanceController {
  constructor(private readonly attendanceService: AttendanceService) {}

  @Get('attendance/daily')
  @ApiOperation({ summary: 'Get daily attendance records' })
  async getDailyAttendance(
    @CurrentUser() user: AuthenticatedUser,
    @Query('fromDate') fromDate?: string,
    @Query('toDate') toDate?: string,
  ): Promise<ApiResponse<any>> {
    const data = await this.attendanceService.getDailyAttendance(
      user.studentId, user.cookies, fromDate, toDate,
    );
    return ApiResponse.ok(data);
  }

  @Get('attendance/subjects')
  @ApiOperation({ summary: 'Get subject-wise attendance report' })
  async getSubjectAttendance(
    @CurrentUser() user: AuthenticatedUser,
    @Query('studentId') studentIdParam?: string,
  ): Promise<ApiResponse<any>> {
    const sid = studentIdParam || user.studentId;
    const data = await this.attendanceService.getSubjectWiseAttendance(sid, user.cookies);
    return ApiResponse.ok(data);
  }

  @Get('attendance/daily-attendance')
  @ApiOperation({ summary: '[Legacy] Get daily attendance (Linways path)' })
  async getDailyAttendanceLegacy(
    @CurrentUser() user: AuthenticatedUser,
    @Query('studentId') studentIdParam?: string,
    @Query('fromDate') fromDate?: string,
    @Query('toDate') toDate?: string,
  ): Promise<any> {
    const sid = studentIdParam || user.studentId;
    return this.attendanceService.getDailyAttendance(sid, user.cookies, fromDate, toDate);
  }

  @Get('attendance/subject-wise-attendance-report')
  @ApiOperation({ summary: '[Legacy] Get subject-wise attendance (Linways path)' })
  async getSubjectAttendanceLegacy(
    @CurrentUser() user: AuthenticatedUser,
    @Query('studentId') studentIdParam?: string,
  ): Promise<any> {
    const sid = studentIdParam || user.studentId;
    return this.attendanceService.getSubjectWiseAttendance(sid, user.cookies);
  }
}
