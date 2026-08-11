import { ApiProperty } from '@nestjs/swagger';

export class ApiResponse<T = unknown> {
  @ApiProperty({ example: true })
  success: boolean;

  @ApiProperty({ required: false })
  data?: T;

  @ApiProperty({ required: false, example: null })
  message?: string | null;

  @ApiProperty({ required: false, example: 200 })
  statusCode?: number;

  constructor(partial: Partial<ApiResponse<T>>) {
    Object.assign(this, partial);
  }

  static ok<T>(data: T, message?: string): ApiResponse<T> {
    return new ApiResponse({ success: true, data, message: message ?? null, statusCode: 200 });
  }

  static fail(message: string, statusCode = 400): ApiResponse<null> {
    return new ApiResponse({ success: false, data: null, message, statusCode });
  }
}

export class PaginatedResponse<T> {
  @ApiProperty({ example: true })
  success: boolean;

  data: T[];

  @ApiProperty()
  total: number;

  @ApiProperty()
  page: number;

  @ApiProperty()
  limit: number;
}
