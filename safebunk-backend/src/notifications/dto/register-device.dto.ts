import { IsBoolean, IsEnum, IsNotEmpty, IsOptional, IsString } from 'class-validator';

export enum DevicePlatform {
  android = 'android',
  ios = 'ios',
  web = 'web',
}

export class RegisterDeviceDto {
  @IsString()
  @IsNotEmpty()
  fcmToken: string;

  @IsOptional()
  @IsEnum(DevicePlatform)
  platform?: DevicePlatform;

  @IsOptional()
  @IsBoolean()
  enabled?: boolean;
}

export class UnregisterDeviceDto {
  @IsString()
  @IsNotEmpty()
  fcmToken: string;
}
