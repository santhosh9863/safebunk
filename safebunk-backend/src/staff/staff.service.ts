import {
  BadRequestException,
  ConflictException,
  Injectable,
  InternalServerErrorException,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { hashPassword } from '../auth/password';
import { isStaffRole } from '../auth/session.types';
import { CreateStaffUserDto } from './dto/create-staff-user.dto';
import {
  normalizeStaffUsername,
  StaffAccountSummary,
} from './staff.types';

interface StaffUserRow {
  id: string;
  username: string;
  displayName: string | null;
  role: string;
  active: boolean;
  createdAt: Date;
}

@Injectable()
export class StaffService {
  constructor(private readonly prisma: PrismaService) {}

  async listStaff(): Promise<StaffAccountSummary[]> {
    const rows = await this.prisma.staffUser.findMany({
      orderBy: { username: 'asc' },
      select: {
        id: true,
        username: true,
        displayName: true,
        role: true,
        active: true,
        createdAt: true,
      },
    });

    return rows.map((row) => this.toSummary(row));
  }

  async createStaff(dto: CreateStaffUserDto): Promise<StaffAccountSummary> {
    if (!isStaffRole(dto.role)) {
      throw new BadRequestException('Invalid staff role');
    }

    const username = normalizeStaffUsername(dto.username);
    const existing = await this.prisma.staffUser.findUnique({
      where: { username },
      select: { id: true },
    });

    if (existing) {
      throw new ConflictException('Staff username already exists');
    }

    const passwordHash = await hashPassword(dto.password);
    const displayName = dto.displayName?.trim() || null;

    try {
      const created = await this.prisma.staffUser.create({
        data: {
          username,
          displayName,
          passwordHash,
          role: dto.role,
        },
      });

      return this.toSummary(created);
    } catch (error) {
      if (
        error instanceof Prisma.PrismaClientKnownRequestError &&
        error.code === 'P2002'
      ) {
        throw new ConflictException('Staff username already exists');
      }
      throw error;
    }
  }

  private toSummary(row: StaffUserRow): StaffAccountSummary {
    if (!isStaffRole(row.role)) {
      throw new InternalServerErrorException('Staff account has an invalid role');
    }

    return {
      id: row.id,
      username: row.username,
      displayName: row.displayName,
      role: row.role,
      active: row.active,
      createdAt: row.createdAt,
    };
  }
}
