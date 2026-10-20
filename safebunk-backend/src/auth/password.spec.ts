import { hashPassword, verifyPassword } from './password';

describe('staff password hashing', () => {
  it('hashes a password with scrypt and verifies it', async () => {
    const hash = await hashPassword('correct horse battery staple');

    expect(hash).toMatch(/^scrypt\$\d+\$\d+\$\d+\$/);
    expect(hash).not.toContain('correct horse battery staple');
    await expect(
      verifyPassword('correct horse battery staple', hash),
    ).resolves.toBe(true);
  });

  it('uses a unique salt for every hash', async () => {
    const first = await hashPassword('same-password-123');
    const second = await hashPassword('same-password-123');

    expect(first).not.toBe(second);
    await expect(verifyPassword('same-password-123', first)).resolves.toBe(true);
    await expect(verifyPassword('same-password-123', second)).resolves.toBe(
      true,
    );
  });

  it('rejects a wrong password', async () => {
    const hash = await hashPassword('correct-password');
    await expect(verifyPassword('wrong-password', hash)).resolves.toBe(false);
  });

  it('rejects missing, empty and malformed stored hashes', async () => {
    await expect(verifyPassword('anything', null)).resolves.toBe(false);
    await expect(verifyPassword('anything', '')).resolves.toBe(false);
    await expect(verifyPassword('anything', 'bcrypt$not-supported')).resolves.toBe(
      false,
    );
    await expect(
      verifyPassword('anything', 'scrypt$1$1$1$bad$bad'),
    ).resolves.toBe(false);
  });
});
