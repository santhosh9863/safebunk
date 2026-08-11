import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { ApiOperation, ApiTags, ApiBearerAuth, ApiQuery } from '@nestjs/swagger';
import { AuthGuard } from '../common/guards/auth.guard';
import { CurrentUser, AuthenticatedUser } from '../common/decorators/current-user.decorator';
import { TimetableService } from './timetable.service';
import { ApiResponse } from '../common/dto/api-response.dto';

@ApiTags('Timetable')
@Controller()
@UseGuards(AuthGuard)
@ApiBearerAuth()
export class TimetableController {
  constructor(private readonly timetableService: TimetableService) {}

  @Get('timetable/today')
  @ApiOperation({ summary: 'Get today\'s class schedule' })
  async getTodaySchedule(@CurrentUser() user: AuthenticatedUser): Promise<ApiResponse<any>> {
    const data = await this.timetableService.getTodaySchedule(user.studentId, user.cookies);
    return ApiResponse.ok(data);
  }

  @Get('timetable/weekly')
  @ApiOperation({ summary: 'Get weekly timetable for a date range' })
  async getWeeklyTimetable(
    @CurrentUser() user: AuthenticatedUser,
    @Query('batchId') batchId: string,
    @Query('fromDate') fromDate: string,
    @Query('toDate') toDate: string,
  ): Promise<ApiResponse<any>> {
    const data = await this.timetableService.getWeeklyTimetable(batchId, fromDate, toDate, user.cookies);
    return ApiResponse.ok(data);
  }

  @Get('timetable/day-hours')
  @ApiOperation({ summary: 'Get timetable day hour slots' })
  async getDayHours(@CurrentUser() user: AuthenticatedUser): Promise<ApiResponse<any>> {
    const data = await this.timetableService.getDayHours(user.cookies);
    return ApiResponse.ok(data);
  }

  @Get('timetable/day-orders')
  @ApiOperation({ summary: 'Get timetable day order types' })
  async getDayOrders(@CurrentUser() user: AuthenticatedUser): Promise<ApiResponse<any>> {
    const data = await this.timetableService.getDayOrders(user.cookies);
    return ApiResponse.ok(data);
  }

  @Get('student/get-my-daily-schedule')
  @ApiOperation({ summary: '[Legacy] Get today schedule (Linways path)' })
  async getTodayScheduleLegacy(
    @CurrentUser() user: AuthenticatedUser,
    @Query('studentId') studentIdParam?: string,
  ): Promise<any> {
    const sid = studentIdParam || user.studentId;
    return this.timetableService.getTodaySchedule(sid, user.cookies);
  }

  @Get('timetable')
  @ApiOperation({ summary: '[Legacy] Get timetable (Linways path)' })
  async getTimetableLegacy(
    @CurrentUser() user: AuthenticatedUser,
    @Query('batchId') batchId?: string,
    @Query('fromDate') fromDate?: string,
    @Query('toDate') toDate?: string,
  ): Promise<any> {
    if (batchId && fromDate && toDate) {
      return this.timetableService.getWeeklyTimetable(batchId, fromDate, toDate, user.cookies);
    }
    return [];
  }
}
