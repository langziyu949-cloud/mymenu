import { afterEach, describe, expect, it, vi } from 'vitest';
import {
  DeepSeekClient,
  DeepSeekHttpError,
  DeepSeekRequestAbortedError,
  DeepSeekRequestError
} from '../src/ai/deepSeekClient.js';

const config = {
  DEEPSEEK_API_KEY: 'test-deepseek-key',
  DEEPSEEK_BASE_URL: 'https://api.deepseek.com/',
  DEEPSEEK_MODEL: 'deepseek-v4-flash' as const
};

describe('DeepSeekClient', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it('sends a JSON-mode non-streaming completion request', async () => {
    const fetch = vi.fn(async () => new Response(JSON.stringify({
      choices: [{ message: { content: '{"kind":"recipe"}' }, finish_reason: 'stop' }]
    }), { status: 200, headers: { 'content-type': 'application/json' } }));
    vi.stubGlobal('fetch', fetch);

    const result = await new DeepSeekClient(config).complete([
      { role: 'system', content: 'Return JSON.' },
      { role: 'user', content: 'Make a recipe.' }
    ]);

    expect(result).toBe('{"kind":"recipe"}');
    const [url, init] = fetch.mock.calls[0] ?? [];
    const body = JSON.parse(String((init as RequestInit).body));
    expect(url).toBe('https://api.deepseek.com/chat/completions');
    expect(body.model).toBe('deepseek-v4-flash');
    expect(body.thinking).toEqual({ type: 'disabled' });
    expect(body.response_format).toEqual({ type: 'json_object' });
    expect(body.stream).toBe(false);
    expect((init as RequestInit).headers).toMatchObject({
      Authorization: 'Bearer test-deepseek-key'
    });
  });

  it('throws a privacy-safe HTTP error for non-success responses', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => new Response(
      'provider detail: original recipe content',
      { status: 429 }
    )));

    await expect(new DeepSeekClient(config).complete([
      { role: 'user', content: 'private request text' }
    ])).rejects.toBeInstanceOf(DeepSeekHttpError);

    await expect(new DeepSeekClient(config).complete([
      { role: 'user', content: 'private request text' }
    ])).rejects.not.toThrow('provider detail: original recipe content');
    await expect(new DeepSeekClient(config).complete([
      { role: 'user', content: 'private request text' }
    ])).rejects.not.toThrow('private request text');
  });

  it('preserves an aborted response-body read as a non-retryable request abort', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => ({
      ok: true,
      json: async () => {
        throw new DOMException('The operation was aborted.', 'AbortError');
      }
    } as Response)));

    await expect(new DeepSeekClient(config).complete([
      { role: 'user', content: 'private request text' }
    ])).rejects.toBeInstanceOf(DeepSeekRequestAbortedError);
  });

  it('preserves other response-body transport failures as non-retryable request errors', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => ({
      ok: true,
      json: async () => {
        throw new TypeError('socket closed');
      }
    } as Response)));

    await expect(new DeepSeekClient(config).complete([
      { role: 'user', content: 'private request text' }
    ])).rejects.toBeInstanceOf(DeepSeekRequestError);
  });

  it('classifies a body-read failure as aborted when the request timeout has fired', async () => {
    vi.spyOn(AbortSignal, 'timeout').mockReturnValue(AbortSignal.abort());
    vi.stubGlobal('fetch', vi.fn(async () => ({
      ok: true,
      json: async () => {
        throw new TypeError('socket closed');
      }
    } as Response)));

    await expect(new DeepSeekClient(config).complete([
      { role: 'user', content: 'private request text' }
    ])).rejects.toBeInstanceOf(DeepSeekRequestAbortedError);
  });
});
