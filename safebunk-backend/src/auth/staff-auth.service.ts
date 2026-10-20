import { Injectable, Logger, UnauthorizedException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { AuthService } from './auth.service';
import { isStaffRole, StaffSession } from './session.types';
import { verifyPassword } from './password';
import {
  normalizeStaffUsername,
  StaffIdentity,
} from '../staff/staff.types';

export interface StaffLoginResult {
  session: StaffSession;
  staff: StaffIdentity;
}

@Injectable()
export class StaffAuthService {
  private readonly logger = new Logger(StaffAuthService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly authService: AuthService,
  ) {}

  async login(username: string, password: string): Promise<StaffLoginResult> {
    const normalizedUsername = normalizeStaffUsername(username);

    const user = await this.prisma.staffUser.findUnique({
      where: { username: normalizedUsername },
    });

    // Always perform a password derivation, even for an unknown username, so
    // account existence is not trivially distinguishable by response timing.
    const passwordValid = await verifyPassword(
      password,
      user?.passwordHash ?? null,
    );

    if (!user || !user.active || !passwordValid) {
      this.logger.warn('Staff login failed');
      throw new UnauthorizedException('Invalid staff credentials');
    }

    if (!isStaffRole(user.role)) {
      // Never fall back to a default role for a malformed account row.
      this.logger.error(`Staff account ${user.id} has an invalid role`);
      throw new UnauthorizedException('Invalid staff credentials');
    }

    const session = this.authService.createStaffSession({
      staffId: user.id,
      username: user.username,
      role: user.role,
    });

    return {
      session,
      staff: {
        id: user.id,
        username: user.username,
        displayName: user.displayName,
        role: user.role,
      },
    };
  }
}
