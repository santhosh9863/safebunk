import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import { StaffRole } from '../../auth/session.types';

export interface AuthenticatedUser {
  role: 'STUDENT';
  studentId: string;
  cookies: string;
  username: string;
}

export interface AuthenticatedStaff {
  staffId: string;
  username: string;
  role: StaffRole;
}

export const CurrentUser = createParamDecorator(
  (data: keyof AuthenticatedUser | undefined, ctx: ExecutionContext): AuthenticatedUser | string => {
    const request = ctx.switchToHttp().getRequest();
    const user = request.user as AuthenticatedUser;
    return data ? user?.[data] : user;
  },
);

export const CurrentStaff = createParamDecorator(
  (data: keyof AuthenticatedStaff | undefined, ctx: ExecutionContext): AuthenticatedStaff | string => {
    const request = ctx.switchToHttp().getRequest();
    const user = request.user as AuthenticatedStaff;
    return data ? user?.[data] : user;
  },
);
