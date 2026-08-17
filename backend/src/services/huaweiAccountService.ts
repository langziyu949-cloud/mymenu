export interface HuaweiAccountConfig {
  clientId: string;
  clientSecret: string;
}

export interface HuaweiAccountVerification {
  accountLabel: string;
  displayName: string;
  accountId: string;
  avatarUrl: string;
  openID: string;
  unionID: string;
}

interface HuaweiUserTokenResponse {
  access_token?: unknown;
  error?: unknown;
  sub_error?: unknown;
}

interface HuaweiTokenInfoResponse {
  open_id?: unknown;
  union_id?: unknown;
  error?: unknown;
}

interface HuaweiUserInfoResponse {
  displayName?: unknown;
  headPictureURL?: unknown;
  error?: unknown;
}

export class HuaweiAccountVerificationError extends Error {
  constructor() {
    super('Huawei account verification failed');
    this.name = 'HuaweiAccountVerificationError';
  }
}

/**
 * Verifies the one-time Authorization Code returned by ordinary Huawei ID sign-in.
 * The Client Secret stays in the cloud function and is never sent to the app.
 */
export class HuaweiAccountService {
  constructor(
    private readonly config: HuaweiAccountConfig,
    private readonly fetcher: typeof fetch = fetch
  ) {}

  async verifyAuthorizationCode(authorizationCode: string): Promise<HuaweiAccountVerification> {
    try {
      const tokenResponse = await this.fetcher(
        'https://oauth-login.cloud.huawei.com/oauth2/v3/token',
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams({
            grant_type: 'authorization_code',
            code: authorizationCode,
            client_id: this.config.clientId,
            client_secret: this.config.clientSecret
          }).toString(),
          signal: AbortSignal.timeout(10_000)
        }
      );
      const token = await this.parseJson<HuaweiUserTokenResponse>(tokenResponse);
      if (!tokenResponse.ok || token.error !== undefined || typeof token.access_token !== 'string' ||
        token.access_token.length === 0) {
        throw new HuaweiAccountVerificationError();
      }

      const identityResponse = await this.fetcher(
        'https://oauth-api.cloud.huawei.com/rest.php?nsp_fmt=JSON&nsp_svc=huawei.oauth2.user.getTokenInfo',
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams({
            open_id: 'OPENID',
            access_token: token.access_token
          }).toString(),
          signal: AbortSignal.timeout(10_000)
        }
      );
      const identity = await this.parseJson<HuaweiTokenInfoResponse>(identityResponse);
      if (!identityResponse.ok || identity.error !== undefined) {
        throw new HuaweiAccountVerificationError();
      }
      const openID = typeof identity.open_id === 'string' ? identity.open_id : '';
      const unionID = typeof identity.union_id === 'string' ? identity.union_id : '';
      if (openID.length === 0 && unionID.length === 0) {
        throw new HuaweiAccountVerificationError();
      }
      const profile = await this.fetchUserProfile(token.access_token);
      const identifier = openID.length > 0 ? openID : unionID;
      return {
        accountLabel: '华为账号',
        displayName: this.safeText(profile?.displayName, 80) || '华为账号用户',
        accountId: this.maskIdentifier(identifier),
        avatarUrl: this.safeAvatarUrl(profile?.headPictureURL),
        openID,
        unionID
      };
    } catch (error) {
      if (error instanceof HuaweiAccountVerificationError) {
        throw error;
      }
      throw new HuaweiAccountVerificationError();
    }
  }

  private async parseJson<T>(response: Response): Promise<T> {
    try {
      return await response.json() as T;
    } catch {
      throw new HuaweiAccountVerificationError();
    }
  }


  /**
   * Profile access is optional. Ordinary Huawei Account sign-in remains valid
   * when the app has not yet been granted the profile scope in AGC.
   */
  private async fetchUserProfile(accessToken: string): Promise<HuaweiUserInfoResponse | null> {
    try {
      const response = await this.fetcher(
        'https://account.cloud.huawei.com/rest.php?nsp_svc=GOpen.User.getInfo',
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body: new URLSearchParams({
            access_token: accessToken,
            getNickName: '0'
          }).toString(),
          signal: AbortSignal.timeout(10_000)
        }
      );
      const profile = await response.json() as HuaweiUserInfoResponse;
      const status = response.headers.get('NSP_STATUS');
      if (!response.ok || (status !== null && status !== '' && status !== '0') || profile.error !== undefined) {
        return null;
      }
      return profile;
    } catch {
      return null;
    }
  }

  private safeText(value: unknown, maxLength: number): string {
    if (typeof value !== 'string') {
      return '';
    }
    return value.trim().slice(0, maxLength);
  }

  private safeAvatarUrl(value: unknown): string {
    const candidate = this.safeText(value, 2_048);
    if (candidate.length === 0) {
      return '';
    }
    try {
      const parsed = new URL(candidate);
      return parsed.protocol === 'https:' ? candidate : '';
    } catch {
      return '';
    }
  }

  private maskIdentifier(identifier: string): string {
    const visible = identifier.slice(-8);
    return `•••• ${visible}`;
  }
}
