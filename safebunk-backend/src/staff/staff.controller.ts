import { Body, Controller, Get, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiOperation, ApiTags } from '@nestjs/swagger';
import { StaffAuthGuard } from '../common/guards/staff-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { ApiResponse } from '../common/dto/api-response.dto';
import { CreateStaffUserDto } from './dto/create-staff-user.dto';
import { StaffService } from './staff.service';

@ApiTags('Staff')
@Controller('staff')
@UseGuards(StaffAuthGuard, RolesGuard)
@Roles('STAFF', 'ADMIN')
@ApiBearerAuth()
export class StaffController {
  constructor(private readonly staffService: StaffService) {}

  @Get('users')
  @Roles('ADMIN')
  @ApiOperation({ summary: 'List staff/admin accounts (admin only; no password hashes)' })
  async listStaff(): Promise<ApiResponse<unknown>> {
    return ApiResponse.ok(await this.staffService.listStaff());
  }

  @Post('users')
  @Roles('ADMIN')
  @ApiOperation({ summary: 'Provision a staff/admin account (admin only)' })
  async createStaff(
    @Body() dto: CreateStaffUserDto,
  ): Promise<ApiResponse<unknown>> {
    const staff = await this.staffService.createStaff(dto);
    return ApiResponse.ok(staff, 'Staff account created');
  }
}
