import { randomBytes, scrypt, timingSafeEqual } from 'crypto';

/**
 * Password hashing for locally managed staff/admin accounts.
 *
 * Format: scrypt$N$r$p$<salt base64>$<derived key base64>
 *
 * Node's built-in scrypt is used deliberately: no plaintext password is ever
 * stored, logged or returned, and no extra native dependency is required.
 */
const SCRYPT_N = 16384;
const SCRYPT_R = 8;
const SCRYPT_P = 1;
const KEY_LENGTH = 64;
const MAX_MEM = 64 * 1024 * 1024;
const SALT_BYTES = 16;

/** Used only to keep unknown-account logins from returning much faster. */
const DUMMY_SALT = Buffer.alloc(SALT_BYTES, 0x42);

interface ParsedHash {
  n: number;
  r: number;
  p: number;
  salt: Buffer;
  hash: Buffer;
}

function deriveKey(
  password: string,
  salt: Buffer,
  n: number,
  r: number,
  p: number,
): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    scrypt(
      password,
      salt,
      KEY_LENGTH,
      { N: n, r, p, maxmem: MAX_MEM },
      (error, derivedKey) => {
        if (error) {
          reject(error);
          return;
        }
        resolve(derivedKey);
      },
    );
  });
}

function parseHash(stored: string): ParsedHash | null {
  const parts = stored.split('$');
  if (parts.length !== 6 || parts[0] !== 'scrypt') return null;

  const n = Number(parts[1]);
  const r = Number(parts[2]);
  const p = Number(parts[3]);

  // Pin the work factors in the stored format. A malformed/tampered row must
  // not be able to make verification arbitrarily expensive.
  if (n !== SCRYPT_N || r !== SCRYPT_R || p !== SCRYPT_P) return null;

  const salt = Buffer.from(parts[4], 'base64');
  const hash = Buffer.from(parts[5], 'base64');
  if (salt.length !== SALT_BYTES || hash.length !== KEY_LENGTH) return null;

  return { n, r, p, salt, hash };
}

export async function hashPassword(password: string): Promise<string> {
  if (!password) throw new Error('Password must not be empty');

  const salt = randomBytes(SALT_BYTES);
  const hash = await deriveKey(password, salt, SCRYPT_N, SCRYPT_R, SCRYPT_P);
  return [
    'scrypt',
    SCRYPT_N,
    SCRYPT_R,
    SCRYPT_P,
    salt.toString('base64'),
    hash.toString('base64'),
  ].join('$');
}

export async function verifyPassword(
  password: string,
  stored: string | null | undefined,
): Promise<boolean> {
  const parsed = stored ? parseHash(stored) : null;

  if (!parsed) {
    // Burn a comparable scrypt derivation for missing/malformed accounts so
    // login timing does not trivially reveal whether a username exists.
    await deriveKey(password, DUMMY_SALT, SCRYPT_N, SCRYPT_R, SCRYPT_P).catch(
      () => undefined,
    );
    return false;
  }

  const candidate = await deriveKey(
    password,
    parsed.salt,
    parsed.n,
    parsed.r,
    parsed.p,
  );
  return (
    candidate.length === parsed.hash.length &&
    timingSafeEqual(candidate, parsed.hash)
  );
}
