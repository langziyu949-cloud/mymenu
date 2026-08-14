import { describe, expect, it, vi } from 'vitest';
import {
  HuaweiAccountService,
  HuaweiAccountVerificationError
} from '../src/services/huaweiAccountService.js';

const config = {
  clientId: '123456789',
  clientSecret: 'server-only-secret'
};

describe('HuaweiAccountService', () => {
  it('exchanges the one-time code and resolves the Huawei account identifiers', async () => {
    const fetcher = vi.fn<typeof fetch>()
      .mockResolvedValueOnce(new Response(JSON.stringify({
        access_token: 'user-access-token',
        expires_in: 3600,
        token_type: 'Bearer'
      }), { status: 200, headers: { 'Content-Type': 'application/json' } }))
      .mockResolvedValueOnce(new Response(JSON.stringify({
        open_id: 'open-id',
        union_id: 'union-id'
      }), { status: 200, headers: { 'Content-Type': 'application/json' } }))
      .mockResolvedValueOnce(new Response(JSON.stringify({
        displayName: '138******00',
        displayNameFlag: 1,
        headPictureURL: 'https://example.com/avatar.jpg'
      }), { status: 200, headers: { 'Content-Type': 'application/json' } }));
    const service = new HuaweiAccountService(config, fetcher);

    await expect(service.verifyAuthorizationCode('authorization-code')).resolves.toEqual({
      accountLabel: '华为账号',
      displayName: '138******00',
      accountId: '•••• open-id',
      avatarUrl: 'https://example.com/avatar.jpg',
      openID: 'open-id',
      unionID: 'union-id'
    });

    expect(fetcher).toHaveBeenCalledTimes(3);
    expect(fetcher.mock.calls[0]?.[0]).toBe(
      'https://oauth-login.cloud.huawei.com/oauth2/v3/token'
    );
    expect(fetcher.mock.calls[0]?.[1]?.body).toBe(
      'grant_type=authorization_code&code=authorization-code&client_id=123456789&client_secret=server-only-secret'
    );
    expect(fetcher.mock.calls[1]?.[0]).toBe(
      'https://oauth-api.cloud.huawei.com/rest.php?nsp_fmt=JSON&nsp_svc=huawei.oauth2.user.getTokenInfo'
    );
    expect(fetcher.mock.calls[1]?.[1]?.body).toBe('open_id=OPENID&access_token=user-access-token');
    expect(fetcher.mock.calls[2]?.[0]).toBe(
      'https://account.cloud.huawei.com/rest.php?nsp_svc=GOpen.User.getInfo'
    );
    expect(fetcher.mock.calls[2]?.[1]?.body).toBe('access_token=user-access-token&getNickName=0');
  });

  it('keeps a verified login usable when optional profile permission is unavailable', async () => {
    const fetcher = vi.fn<typeof fetch>()
      .mockResolvedValueOnce(new Response(JSON.stringify({
        access_token: 'user-access-token'
      }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({
        open_id: 'very-long-open-id',
        union_id: ''
      }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ error: 'forbidden' }), {
        status: 200,
        headers: { NSP_STATUS: '403' }
      }));
    const service = new HuaweiAccountService(config, fetcher);

    await expect(service.verifyAuthorizationCode('authorization-code')).resolves.toMatchObject({
      accountLabel: '华为账号',
      displayName: '华为账号用户',
      accountId: '•••• -open-id',
      avatarUrl: ''
    });
  });

  it('fails closed when Account Kit does not return a user access token', async () => {
    const fetcher = vi.fn<typeof fetch>()
      .mockResolvedValueOnce(new Response(JSON.stringify({
        error: 1101,
        sub_error: 12304
      }), { status: 200 }));
    const service = new HuaweiAccountService(config, fetcher);

    await expect(service.verifyAuthorizationCode('authorization-code'))
      .rejects.toBeInstanceOf(HuaweiAccountVerificationError);
  });

  it('rejects a token that cannot be resolved to OpenID or UnionID', async () => {
    const fetcher = vi.fn<typeof fetch>()
      .mockResolvedValueOnce(new Response(JSON.stringify({
        access_token: 'user-access-token'
      }), { status: 200 }))
      .mockResolvedValueOnce(new Response(JSON.stringify({
        scope: 'openid'
      }), { status: 200 }));
    const service = new HuaweiAccountService(config, fetcher);

    await expect(service.verifyAuthorizationCode('authorization-code'))
      .rejects.toBeInstanceOf(HuaweiAccountVerificationError);
  });
});
