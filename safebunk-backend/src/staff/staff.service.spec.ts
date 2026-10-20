import {
  BadRequestException,
  ConflictException,
  InternalServerErrorException,
} from '@nestjs/common';
import { StaffService } from './staff.service';
import { hashPassword, verifyPassword } from '../auth/password';

class FakePrisma {
  rows: any[] = [];
  private seq = 0;

  staffUser = {
    findUnique: jest.fn(async ({ where }: any) => {
      return this.rows.find((row) => row.username === where.username) ?? null;
    }),
    findMany: jest.fn(async ({ orderBy }: any) => {
      const sorted = [...this.rows];
      if (orderBy?.username === 'asc') {
        sorted.sort((a, b) => a.username.localeCompare(b.username));
      }
      return sorted;
    }),
    create: jest.fn(async ({ data }: any) => {
      if (this.rows.some((row) => row.username === data.username)) {
        throw new Error('Unique constraint failed');
      }
      const row = {
        id: `staff_${++this.seq}`,
        displayName: null,
        active: true,
        createdAt: new Date(),
        updatedAt: new Date(),
        ...data,
      };
      this.rows.push(row);
      return row;
    }),
  };
}

describe('StaffService', () => {
  let prisma: FakePrisma;
  let service: StaffService;

  beforeEach(() => {
    prisma = new FakePrisma();
    service = new StaffService(prisma as any);
  });

  it('provisions a staff account with a normalized username and hashed password', async () => {
    const summary = await service.createStaff({
      username: '  Maintenance.Ravi ',
      password: 'a-strong-staff-password',
      displayName: '  Ravi Kumar ',
      role: 'STAFF',
    });

    expect(summary).toMatchObject({
      username: 'maintenance.ravi',
      displayName: 'Ravi Kumar',
      role: 'STAFF',
      active: true,
    });
    expect(summary).not.toHaveProperty('passwordHash');

    const stored = prisma.rows[0];
    expect(stored.passwordHash).not.toBe('a-strong-staff-password');
    await expect(
      verifyPassword('a-strong-staff-password', stored.passwordHash),
    ).resolves.toBe(true);
  });

  it('provisions an admin account only when the role is explicitly ADMIN', async () => {
    const summary = await service.createStaff({
      username: 'campus.admin',
      password: 'another-strong-password',
      role: 'ADMIN',
    });

    expect(summary.role).toBe('ADMIN');
  });

  it('rejects a duplicate username case-insensitively', async () => {
    prisma.rows.push({
      id: 'staff_1',
      username: 'maintenance.ravi',
      displayName: null,
      passwordHash: await hashPassword('existing-password'),
      role: 'STAFF',
      active: true,
      createdAt: new Date(),
    });

    await expect(
      service.createStaff({
        username: 'MAINTENANCE.RAVI',
        password: 'another-strong-password',
        role: 'STAFF',
      }),
    ).rejects.toThrow(ConflictException);
  });

  it('rejects an invalid role instead of defaulting it', async () => {
    await expect(
      service.createStaff({
        username: 'bad.role',
        password: 'another-strong-password',
        role: 'SUPERUSER' as any,
      }),
    ).rejects.toThrow(BadRequestException);
    expect(prisma.staffUser.create).not.toHaveBeenCalled();
  });

  it('lists staff accounts without exposing password hashes', async () => {
    prisma.rows.push(
      {
        id: 'staff_2',
        username: 'z.staff',
        displayName: null,
        passwordHash: await hashPassword('existing-password-1'),
        role: 'STAFF',
        active: true,
        createdAt: new Date(),
      },
      {
        id: 'staff_1',
        username: 'a.admin',
        displayName: 'Admin',
        passwordHash: await hashPassword('existing-password-2'),
        role: 'ADMIN',
        active: true,
        createdAt: new Date(),
      },
    );

    const list = await service.listStaff();

    expect(list.map((s) => s.username)).toEqual(['a.admin', 'z.staff']);
    expect(list.every((s) => !('passwordHash' in s))).toBe(true);
  });

  it('fails closed if a stored account has an invalid role', async () => {
    prisma.rows.push({
      id: 'staff_bad',
      username: 'bad.role',
      displayName: null,
      passwordHash: await hashPassword('existing-password'),
      role: 'SUPERUSER',
      active: true,
      createdAt: new Date(),
    });

    await expect(service.listStaff()).rejects.toThrow(
      InternalServerErrorException,
    );
  });
});
