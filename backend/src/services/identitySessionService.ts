import { createHmac, timingSafeEqual } from 'node:crypto';

export interface IdentitySessionPayload {
  sub: string;
  accountLabel: string;
  displayName: string;
  accountId: string;
  avatarUrl: string;
  loginAt: number;
  exp: number;
}

export interface IdentitySessionProfile {
  accountLabel: string;
  displayName: string;
  accountId: string;
  avatarUrl: string;
  loginAt: number;
}

export interface IssuedIdentitySession {
  identityToken: string;
  expiresAt: number;
}

const SESSION_LIFETIME_SECONDS = 7 * 24 * 60 * 60;

export class IdentitySessionError extends Error {
  constructor() {
    super('Identity session is missing, expired, or invalid');
    this.name = 'IdentitySessionError';
  }
}

export class IdentitySessionService {
  constructor(private readonly secret: string, private readonly now: () => number = Date.now) {}

  issue(subject: string, profile: IdentitySessionProfile): IssuedIdentitySession {
    if (
      subject.length === 0 || profile.accountLabel.length === 0 ||
      profile.displayName.length === 0 || profile.accountId.length === 0 ||
      !Number.isSafeInteger(profile.loginAt) || profile.loginAt <= 0
    ) {
      throw new IdentitySessionError();
    }
    const expiresAt = this.now() + SESSION_LIFETIME_SECONDS * 1000;
    const payload: IdentitySessionPayload = {
      sub: subject,
      accountLabel: profile.accountLabel,
      displayName: profile.displayName,
      accountId: profile.accountId,
      avatarUrl: profile.avatarUrl,
      loginAt: profile.loginAt,
      exp: Math.floor(expiresAt / 1000)
    };
    const encodedPayload = Buffer.from(JSON.stringify(payload), 'utf8').toString('base64url');
    return {
      identityToken: `${encodedPayload}.${this.sign(encodedPayload)}`,
      expiresAt
    };
  }

  verify(token: string | undefined): IdentitySessionPayload {
    if (token === undefined) {
      throw new IdentitySessionError();
    }
    const parts = token.split('.');
    if (parts.length !== 2) {
      throw new IdentitySessionError();
    }
    const encodedPayload = parts[0];
    const encodedSignature = parts[1];
    if (
      encodedPayload === undefined || encodedPayload.length === 0 ||
      encodedSignature === undefined || encodedSignature.length === 0
    ) {
      throw new IdentitySessionError();
    }
    const expected = Buffer.from(this.sign(encodedPayload));
    const received = Buffer.from(encodedSignature);
    if (received.length !== expected.length || !timingSafeEqual(received, expected)) {
      throw new IdentitySessionError();
    }

    try {
      const parsed = JSON.parse(Buffer.from(encodedPayload, 'base64url').toString('utf8')) as Partial<IdentitySessionPayload>;
      if (
        typeof parsed.sub !== 'string' || parsed.sub.length === 0 ||
        typeof parsed.accountLabel !== 'string' || parsed.accountLabel.length === 0 ||
        typeof parsed.displayName !== 'string' || parsed.displayName.length === 0 ||
        typeof parsed.accountId !== 'string' || parsed.accountId.length === 0 ||
        typeof parsed.avatarUrl !== 'string' ||
        typeof parsed.loginAt !== 'number' || !Number.isSafeInteger(parsed.loginAt) || parsed.loginAt <= 0 ||
        typeof parsed.exp !== 'number' || parsed.exp * 1000 <= this.now()
      ) {
        throw new IdentitySessionError();
      }
      return parsed as IdentitySessionPayload;
    } catch (error) {
      if (error instanceof IdentitySessionError) {
        throw error;
      }
      throw new IdentitySessionError();
    }
  }

  private sign(payload: string): string {
    return createHmac('sha256', this.secret).update(payload).digest('base64url');
  }
}
