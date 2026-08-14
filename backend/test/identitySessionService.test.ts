import { describe, expect, it } from 'vitest';
import { IdentitySessionError, IdentitySessionService } from '../src/services/identitySessionService.js';

describe('IdentitySessionService', () => {
  const now = Date.UTC(2026, 7, 12);
  const secret = 'test-session-secret-with-at-least-32-characters';
  const profile = {
    accountLabel: '华为账号',
    displayName: '138******00',
    accountId: '•••• 12345678',
    avatarUrl: 'https://example.com/avatar.jpg',
    loginAt: now
  };

  it('issues and verifies a signed short-lived identity session', () => {
    const service = new IdentitySessionService(secret, () => now);
    const issued = service.issue('hashed-account-id', profile);

    expect(issued.expiresAt).toBeGreaterThan(now);
    expect(service.verify(issued.identityToken)).toMatchObject({
      sub: 'hashed-account-id',
      ...profile
    });
  });

  it('rejects missing, tampered, and expired sessions', () => {
    const service = new IdentitySessionService(secret, () => now);
    const issued = service.issue('hashed-account-id', profile);
    const expiredService = new IdentitySessionService(secret, () => issued.expiresAt + 1);

    expect(() => service.verify(undefined)).toThrow(IdentitySessionError);
    expect(() => service.verify(`${issued.identityToken}x`)).toThrow(IdentitySessionError);
    expect(() => expiredService.verify(issued.identityToken)).toThrow(IdentitySessionError);
  });
});
