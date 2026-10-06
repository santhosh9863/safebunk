import { IsBoolean, IsEnum, IsIn, IsOptional } from 'class-validator';

export enum ReminderTiming {
  minutes30 = '30',
  minutes10 = '10',
  minutes5 = '5',
}

/** Direct-address gender for message personalization ('' = unknown). */
export const GENDERS = ['', 'male', 'female'] as const;
export type Gender = (typeof GENDERS)[number];

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

  @IsOptional()
  @IsIn(GENDERS)
  gender?: Gender;

  @IsOptional()
  @IsBoolean()
  wrapUpEnabled?: boolean;
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
  gender: '',
  wrapUpEnabled: true,
};
