import 'dotenv/config';
import * as readline from 'readline';
import { PrismaClient } from '@prisma/client';
import { hashPassword, verifyPassword } from '../auth/password';
import { isStaffRole, STAFF_ROLES } from '../auth/session.types';
import {
  normalizeStaffUsername,
  STAFF_PASSWORD_MAX_LENGTH,
  STAFF_PASSWORD_MIN_LENGTH,
  STAFF_USERNAME_MAX_LENGTH,
  STAFF_USERNAME_MIN_LENGTH,
} from './staff.types';

/**
 * One-time provisioning for the first admin (and emergency local recovery).
 * Normal account creation is admin-only via POST /api/staff/users.
 *
 * Usage:
 *   npm run staff:create -- --username campus.admin --role ADMIN --name "Campus Admin"
 *
 * The password is read from a hidden prompt. It is never accepted as a CLI
 * argument, so it does not land in shell history.
 */

function argValue(name: string): string | undefined {
  const eqPrefix = `--${name}=`;
  const eq = process.argv.find((arg) => arg.startsWith(eqPrefix));
  if (eq) return eq.slice(eqPrefix.length);

  const index = process.argv.indexOf(`--${name}`);
  if (index >= 0) return process.argv[index + 1];
  return undefined;
}

function rejectPasswordArguments(): void {
  const hasPasswordArgument = process.argv.some(
    (arg) => arg === '--password' || arg.startsWith('--password='),
  );
  if (hasPasswordArgument) {
    throw new Error(
      'Passwords are not accepted as command-line arguments. The CLI will prompt for the password.',
    );
  }
}

async function promptHiddenPair(): Promise<{
  password: string;
  confirmation: string;
}> {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    terminal: Boolean(process.stdin.isTTY),
  });

  const mutable = rl as readline.Interface & {
    stdoutMuted?: boolean;
    _writeToOutput?: (text: string) => void;
    output: NodeJS.WritableStream;
  };

  mutable._writeToOutput = (text: string) => {
    if (mutable.stdoutMuted) {
      mutable.output.write('*');
    } else {
      mutable.output.write(text);
    }
  };

  return new Promise((resolve, reject) => {
    let settled = false;

    const cancel = (): void => {
      if (settled) return;
      settled = true;
      mutable.stdoutMuted = false;
      reject(new Error('Password prompt cancelled'));
    };

    rl.on('close', cancel);
    rl.on('SIGINT', () => {
      rl.close();
    });

    process.stdout.write('Password: ');
    mutable.stdoutMuted = true;
    rl.question('', (password) => {
      mutable.stdoutMuted = false;
      process.stdout.write('\n');

      // Ask for the confirmation synchronously from the first callback. Awaiting
      // between prompts can miss a second line that is already buffered when
      // stdin is piped, then readline closes before the next question registers.
      process.stdout.write('Confirm password: ');
      mutable.stdoutMuted = true;
      rl.question('', (confirmation) => {
        if (settled) return;
        settled = true;
        mutable.stdoutMuted = false;
        process.stdout.write('\n');
        rl.close();
        resolve({ password, confirmation });
      });
    });
  });
}

async function main(): Promise<void> {
  rejectPasswordArguments();

  const username = normalizeStaffUsername(argValue('username') ?? '');
  const role = argValue('role') ?? '';
  const displayName = argValue('name')?.trim() || null;

  if (
    username.length < STAFF_USERNAME_MIN_LENGTH ||
    username.length > STAFF_USERNAME_MAX_LENGTH ||
    !/^[a-z0-9._-]+$/.test(username)
  ) {
    throw new Error(
      `--username must be ${STAFF_USERNAME_MIN_LENGTH}-${STAFF_USERNAME_MAX_LENGTH} characters (letters, numbers, dot, underscore, hyphen)`,
    );
  }

  if (!isStaffRole(role)) {
    throw new Error(`--role must be one of: ${STAFF_ROLES.join(', ')}`);
  }

  const { password, confirmation } = await promptHiddenPair();
  if (
    password.length < STAFF_PASSWORD_MIN_LENGTH ||
    password.length > STAFF_PASSWORD_MAX_LENGTH
  ) {
    throw new Error(
      `Password must be ${STAFF_PASSWORD_MIN_LENGTH}-${STAFF_PASSWORD_MAX_LENGTH} characters`,
    );
  }

  if (password !== confirmation) {
    throw new Error('Passwords do not match');
  }

  const prisma = new PrismaClient();
  try {
    const existing = await prisma.staffUser.findUnique({
      where: { username },
      select: { id: true },
    });
    if (existing) {
      throw new Error(`Staff username already exists: ${username}`);
    }

    const passwordHash = await hashPassword(password);
    if (!(await verifyPassword(password, passwordHash))) {
      throw new Error('Password hash self-check failed');
    }

    const created = await prisma.staffUser.create({
      data: {
        username,
        displayName,
        passwordHash,
        role,
      },
      select: { id: true, username: true, role: true },
    });

    process.stdout.write(
      `Created ${created.role} account "${created.username}" (id ${created.id}).\n`,
    );
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : 'Unknown error';
  process.stderr.write(`staff:create failed: ${message}\n`);
  process.exitCode = 1;
});
