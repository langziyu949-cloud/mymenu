import { util } from '@kit.ArkTS';
import { cloudFunction } from '@kit.CloudFoundationKit';
import { asset } from '@kit.AssetStoreKit';

const CLOUD_FUNCTION_NAME: string = 'kitchen-master-ai';
const IDENTITY_ASSET_ALIAS: string = 'kitchen-master-huawei-identity';

interface HuaweiAccountPayload {
  authorizationCode: string;
}

interface HuaweiAccountEnvelope {
  action: string;
  payload: HuaweiAccountPayload;
}

interface ValidateIdentityEnvelope {
  action: string;
  identityToken: string;
}

interface CloudHttpResponse {
  statusCode?: number;
  body?: string;
}

interface HuaweiAccountResponse {
  verified?: boolean;
  accountLabel?: string;
  displayName?: string;
  accountId?: string;
  avatarUrl?: string;
  loginAt?: number;
  identityToken?: string;
  expiresAt?: number;
}

interface StoredIdentitySession {
  identityToken: string;
  accountLabel: string;
  displayName: string;
  accountId: string;
  avatarUrl: string;
  loginAt: number;
  expiresAt: number;
}

export interface IdentityVerificationResult {
  accountLabel: string;
  displayName: string;
  accountId: string;
  avatarUrl: string;
  loginAt: number;
}

export class IdentityVerificationService {
  private session: StoredIdentitySession | null = null;

  async verifyHuaweiAccount(authorizationCode: string): Promise<IdentityVerificationResult> {
    const envelope: HuaweiAccountEnvelope = {
      action: 'verifyHuaweiAccount',
      payload: { authorizationCode }
    };
    const result: HuaweiAccountResponse = await this.call(envelope);
    if (
      result.verified !== true ||
      result.accountLabel === undefined || result.accountLabel.length === 0 ||
      result.displayName === undefined || result.displayName.length === 0 ||
      result.accountId === undefined || result.accountId.length === 0 ||
      result.avatarUrl === undefined ||
      result.loginAt === undefined || result.loginAt <= 0 ||
      result.identityToken === undefined || result.identityToken.length === 0 ||
      result.expiresAt === undefined || result.expiresAt <= Date.now()
    ) {
      throw new Error('ACCOUNT_AUTH_INVALID_RESPONSE');
    }
    this.session = {
      identityToken: result.identityToken,
      accountLabel: result.accountLabel,
      displayName: result.displayName,
      accountId: result.accountId,
      avatarUrl: result.avatarUrl,
      loginAt: result.loginAt,
      expiresAt: result.expiresAt
    };
    await this.persistSession(this.session);
    return this.toVerificationResult(this.session);
  }

  async restoreIdentity(): Promise<IdentityVerificationResult | null> {
    const stored: StoredIdentitySession | null = await this.loadSession();
    if (stored === null || stored.expiresAt <= Date.now()) {
      await this.clearIdentity();
      return null;
    }
    try {
      const result: HuaweiAccountResponse = await this.call({
        action: 'validateIdentity',
        identityToken: stored.identityToken
      });
      if (
        result.verified !== true ||
        result.accountLabel === undefined || result.accountLabel.length === 0 ||
        result.displayName === undefined || result.displayName.length === 0 ||
        result.accountId === undefined || result.accountId.length === 0 ||
        result.avatarUrl === undefined ||
        result.loginAt === undefined || result.loginAt <= 0 ||
        result.expiresAt === undefined || result.expiresAt <= Date.now()
      ) {
        throw new Error('ACCOUNT_AUTH_INVALID_RESPONSE');
      }
      this.session = {
        identityToken: stored.identityToken,
        accountLabel: result.accountLabel,
        displayName: result.displayName,
        accountId: result.accountId,
        avatarUrl: result.avatarUrl,
        loginAt: result.loginAt,
        expiresAt: result.expiresAt
      };
      await this.persistSession(this.session);
      return this.toVerificationResult(this.session);
    } catch {
      await this.clearIdentity();
      return null;
    }
  }

  async getIdentityToken(): Promise<string> {
    if (this.session === null) {
      this.session = await this.loadSession();
    }
    if (this.session === null || this.session.expiresAt <= Date.now()) {
      await this.clearIdentity();
      throw new Error('IDENTITY_REQUIRED');
    }
    return this.session.identityToken;
  }

  async clearIdentity(): Promise<void> {
    this.session = null;
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, this.encode(IDENTITY_ASSET_ALIAS));
    try {
      await asset.remove(query);
    } catch {
      // Removing an already absent session is intentionally idempotent.
    }
  }

  private async call(envelope: HuaweiAccountEnvelope | ValidateIdentityEnvelope): Promise<HuaweiAccountResponse> {
    const response: cloudFunction.FunctionResult = await cloudFunction.call({
      name: CLOUD_FUNCTION_NAME,
      data: envelope,
      version: '$latest',
      timeout: 20000
    });
    const content: string = this.unwrapResponse(response.result);
    return JSON.parse(content) as HuaweiAccountResponse;
  }

  private async persistSession(session: StoredIdentitySession): Promise<void> {
    const attributes: asset.AssetMap = new Map();
    attributes.set(asset.Tag.ALIAS, this.encode(IDENTITY_ASSET_ALIAS));
    attributes.set(asset.Tag.SECRET, this.encode(JSON.stringify(session)));
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
    attributes.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    await asset.add(attributes);
  }

  private async loadSession(): Promise<StoredIdentitySession | null> {
    const query: asset.AssetMap = new Map();
    query.set(asset.Tag.ALIAS, this.encode(IDENTITY_ASSET_ALIAS));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const result: Array<asset.AssetMap> = await asset.query(query);
      const secret: asset.Value | undefined = result[0]?.get(asset.Tag.SECRET);
      if (!(secret instanceof Uint8Array)) {
        return null;
      }
      const parsed: StoredIdentitySession = JSON.parse(this.decode(secret)) as StoredIdentitySession;
      if (
        typeof parsed.identityToken !== 'string' || parsed.identityToken.length === 0 ||
        typeof parsed.accountLabel !== 'string' || parsed.accountLabel.length === 0 ||
        typeof parsed.displayName !== 'string' || parsed.displayName.length === 0 ||
        typeof parsed.accountId !== 'string' || parsed.accountId.length === 0 ||
        typeof parsed.avatarUrl !== 'string' ||
        typeof parsed.loginAt !== 'number' || parsed.loginAt <= 0 ||
        typeof parsed.expiresAt !== 'number'
      ) {
        return null;
      }
      return parsed;
    } catch {
      return null;
    }
  }

  private unwrapResponse(result: string | Object): string {
    const serialized: string = typeof result === 'string' ? result : JSON.stringify(result);
    const response: CloudHttpResponse = JSON.parse(serialized) as CloudHttpResponse;
    if (response.statusCode === undefined || response.body === undefined) {
      return serialized;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw new Error(response.statusCode === 401 ? 'IDENTITY_REQUIRED' : 'ACCOUNT_AUTH_UNAVAILABLE');
    }
    return response.body;
  }

  private encode(value: string): Uint8Array {
    return new util.TextEncoder().encodeInto(value);
  }

  private decode(value: Uint8Array): string {
    return new util.TextDecoder().decodeToString(value);
  }

  private toVerificationResult(session: StoredIdentitySession): IdentityVerificationResult {
    return {
      accountLabel: session.accountLabel,
      displayName: session.displayName,
      accountId: session.accountId,
      avatarUrl: session.avatarUrl,
      loginAt: session.loginAt
    };
  }
}

export const identityVerificationService: IdentityVerificationService = new IdentityVerificationService();
