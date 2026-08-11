import { ApiProperty } from '@nestjs/swagger';

export class StudentInfo {
  @ApiProperty({ example: '12345' })
  studentId: string;

  @ApiProperty({ example: 'John Doe' })
  name: string;

  @ApiProperty({ example: 'BCA2024C' })
  batch: string;

  @ApiProperty({ example: 'BCA24XXX' })
  username: string;
}

export class LoginResponseDto {
  @ApiProperty({ example: 'eyJhbGciOiJIUzI1NiIs...' })
  accessToken: string;

  @ApiProperty()
  student: StudentInfo;
}
