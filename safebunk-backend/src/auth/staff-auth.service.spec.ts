import { UnauthorizedException } from '@nestjs/common';
import { StaffAuthService } from './staff-auth.service';
import { hashPassword } from './password';

interface FakeStaffRow {
  id: string;
  username: string;
  displayName: string | null;
  passwordHash: string;
  role: string;
  active: boolean;
}

class FakePrisma {
  rows: FakeStaffRow[] = [];
  staffUser = {
    findUnique: jest.fn(async ({ where }: any) => {
      return this.rows.find((row) => row.username === where.username) ?? null;
    }),
  };
}

function makeAuth() {
  return {
    createStaffSession: jest.fn((input: any) => ({
      token: 'staff-session-token',
      role: input.role,
      staffId: input.staffId,
      username: input.username,
      createdAt: Date.now(),
    })),
  };
}

describe('StaffAuthService', () => {
  let prisma: FakePrisma;
  let auth: ReturnType<typeof makeAuth>;
  let service: StaffAuthService;
  let staffHash: string;
  let adminHash: string;

  beforeAll(async () => {
    staffHash = await hashPassword('staff-password-123');
    adminHash = await hashPassword('admin-password-123');
  });

  beforeEach(() => {
    prisma = new FakePrisma();
    auth = makeAuth();
    service = new StaffAuthService(prisma as any, auth as any);
    prisma.rows = [
      {
        id: 'staff-1',
        username: 'maintenance.ravi',
        displayName: 'Ravi Kumar',
        passwordHash: staffHash,
        role: 'STAFF',
        active: true,
      },
      {
        id: 'admin-1',
        username: 'campus.admin',
        displayName: null,
        passwordHash: adminHash,
        role: 'ADMIN',
        active: true,
      },
      {
        id: 'inactive-1',
        username: 'inactive.staff',
        displayName: null,
        passwordHash: staffHash,
        role: 'STAFF',
        active: false,
      },
      {
        id: 'bad-role-1',
        username: 'bad.role',
        displayName: null,
        passwordHash: staffHash,
        role: 'SUPERUSER',
        active: true,
      },
    ];
  });

  it('authenticates a valid staff account and takes the role from the database', async () => {
    const result = await service.login(' Maintenance.Ravi ', 'staff-password-123');

    expect(prisma.staffUser.findUnique).toHaveBeenCalledWith({
      where: { username: 'maintenance.ravi' },
    });
    expect(result.session.role).toBe('STAFF');
    expect(result.staff).toEqual({
      id: 'staff-1',
      username: 'maintenance.ravi',
      displayName: 'Ravi Kumar',
      role: 'STAFF',
    });
    expect(result.staff).not.toHaveProperty('passwordHash');
    expect(auth.createStaffSession).toHaveBeenCalledWith({
      staffId: 'staff-1',
      username: 'maintenance.ravi',
      role: 'STAFF',
    });
  });

  it('authenticates an admin account with the ADMIN role from the database', async () => {
    const result = await service.login('campus.admin', 'admin-password-123');

    expect(result.session.role).toBe('ADMIN');
    expect(result.staff.role).toBe('ADMIN');
  });

  it('rejects a wrong password without creating a session', async () => {
    await expect(
      service.login('maintenance.ravi', 'wrong-password'),
    ).rejects.toThrow(UnauthorizedException);
    expect(auth.createStaffSession).not.toHaveBeenCalled();
  });

  it('rejects an unknown username without creating a session', async () => {
    await expect(service.login('nobody', 'some-password')).rejects.toThrow(
      UnauthorizedException,
    );
    expect(auth.createStaffSession).not.toHaveBeenCalled();
  });

  it('rejects an inactive account even with the correct password', async () => {
    await expect(
      service.login('inactive.staff', 'staff-password-123'),
    ).rejects.toThrow(UnauthorizedException);
    expect(auth.createStaffSession).not.toHaveBeenCalled();
  });

  it('rejects a malformed database role instead of defaulting it', async () => {
    await expect(
      service.login('bad.role', 'staff-password-123'),
    ).rejects.toThrow(UnauthorizedException);
    expect(auth.createStaffSession).not.toHaveBeenCalled();
  });
});
