import {
  Injectable,
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  UnauthorizedException,
} from '@nestjs/common';
import { AuthService } from '../../auth/auth.service';
import { AuthenticatedUser } from '../decorators/current-user.decorator';

@Injectable()
export class AuthGuard implements CanActivate {
  constructor(private readonly authService: AuthService) {}

  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest();
    const authHeader = request.headers.authorization;

    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      throw new UnauthorizedException('Missing or invalid authorization header');
    }

    const token = authHeader.slice(7);
    const session = this.authService.validateSession(token);

    if (!session) {
      throw new UnauthorizedException('Session expired or invalid');
    }

    // Staff/admin sessions must never be usable against student-only routes.
    if (session.role !== 'STUDENT') {
      throw new ForbiddenException('Student access required');
    }

    request.user = {
      role: 'STUDENT',
      studentId: session.studentId,
      cookies: session.cookies,
      username: session.username,
    } as AuthenticatedUser;

    return true;
  }
}
