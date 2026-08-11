import { IsBoolean, IsEnum, IsOptional } from 'class-validator';

export enum ReminderTiming {
  minutes30 = '30',
  minutes10 = '10',
  minutes5 = '5',
}

export class NotificationPreferencesDto {
  @IsOptional()
  @IsBoolean()
  masterEnabled?: boolean;

  @IsOptional()
  @IsBoolean()
  attendanceEnabled?: boolean;

  @IsOptional()
  @IsBoolean()
  bunkEnabled?: boolean;

  @IsOptional()
  @IsBoolean()
  classRemindersEnabled?: boolean;

  @IsOptional()
  @IsBoolean()
  milestonesEnabled?: boolean;

  @IsOptional()
  @IsBoolean()
  timetableEnabled?: boolean;

  @IsOptional()
  @IsBoolean()
  roastingEnabled?: boolean;

  @IsOptional()
  @IsEnum(ReminderTiming)
  reminderTiming?: ReminderTiming;
}

export const DEFAULT_PREFERENCES: NotificationPreferencesDto = {
  masterEnabled: true,
  attendanceEnabled: true,
  bunkEnabled: true,
  classRemindersEnabled: true,
  milestonesEnabled: true,
  timetableEnabled: true,
  roastingEnabled: true,
  reminderTiming: ReminderTiming.minutes10,
};
