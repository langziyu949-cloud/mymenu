import { describe, expect, it, vi } from 'vitest';
import {
  DeepSeekHttpError,
  DeepSeekRequestAbortedError,
  DeepSeekRequestError
} from '../src/ai/deepSeekClient.js';
import type { AppConfig } from '../src/config.js';
import type { AnalyzeRequest, AnalyzeResult, RecipeDraft, RecipeRevision, ReviseRequest } from '../src/domain/recipe.js';
import { buildServer } from '../src/http/buildServer.js';
import { InvalidModelOutputError } from '../src/services/recipeService.js';

const config: AppConfig = {
  DEEPSEEK_API_KEY: 'test-deepseek-key',
  DEEPSEEK_BASE_URL: 'https://api.deepseek.com',
  DEEPSEEK_MODEL: 'deepseek-v4-flash',
  APP_ACCESS_TOKEN: 'test-device-token-1234',
  PORT: 9000
};

const recipe: RecipeDraft = {
  name: '番茄炒蛋',
  ingredients: [{ name: '番茄', amount: '2 个', isAiEstimated: false }],
  seasonings: [],
  steps: ['炒熟番茄。'],
  experience: []
};
const reply = '番茄炒蛋已经按家里的做法整理好了。';

interface RecipeServiceDependency {
  analyze(request: AnalyzeRequest): Promise<AnalyzeResult>;
  revise(request: ReviseRequest): Promise<RecipeRevision>;
}

function createService(overrides: Partial<RecipeServiceDependency> = {}): RecipeServiceDependency {
  return {
    analyze: vi.fn(async () => ({ kind: 'recipe', recipe, reply })),
    revise: vi.fn(async () => ({ recipe, reply })),
    ...overrides
  };
}

function createApp(service = createService(), log = vi.fn()) {
  return {
    app: buildServer({ config, service, logger: { info: log } }),
    log
  };
}

describe('HTTP API', () => {
  it('exposes an unauthenticated health check', async () => {
    const { app } = createApp();

    const response = await app.inject({ method: 'GET', url: '/api/v1/health' });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ status: 'ok' });
  });

  it('rejects missing and incorrect bearer tokens without calling the service', async () => {
    const service = createService();
    const { app } = createApp(service);

    for (const authorization of [undefined, 'Bearer wrong-device-token-1234']) {
      const response = await app.inject({
        method: 'POST',
        url: '/api/v1/recipes/analyze',
        headers: authorization === undefined ? {} : { authorization },
        payload: { originalText: '番茄炒蛋。' }
      });

      expect(response.statusCode).toBe(401);
      expect(response.json()).toMatchObject({
        error: { code: 'UNAUTHORIZED', retryable: false }
      });
    }

    expect(service.analyze).not.toHaveBeenCalled();
  });

  it('validates authenticated analyze requests before calling the service', async () => {
    const service = createService();
    const { app } = createApp(service);

    const response = await app.inject({
      method: 'POST',
      url: '/api/v1/recipes/analyze',
      headers: { authorization: `Bearer ${config.APP_ACCESS_TOKEN}` },
      payload: { originalText: '', extra: 'not allowed' }
    });

    expect(response.statusCode).toBe(400);
    expect(response.json()).toMatchObject({
      error: { code: 'INVALID_REQUEST', retryable: false }
    });
    expect(service.analyze).not.toHaveBeenCalled();
  });

  it('returns analyzed recipes unchanged for an authenticated request', async () => {
    const service = createService();
    const { app } = createApp(service);

    const response = await app.inject({
      method: 'POST',
      url: '/api/v1/recipes/analyze',
      headers: { authorization: `Bearer ${config.APP_ACCESS_TOKEN}` },
      payload: { originalText: '番茄炒蛋。' }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ kind: 'recipe', recipe, reply });
    expect(service.analyze).toHaveBeenCalledWith({ originalText: '番茄炒蛋。' });
  });

  it('wraps revised recipes in the recipe result envelope', async () => {
    const service = createService();
    const { app } = createApp(service);

    const response = await app.inject({
      method: 'POST',
      url: '/api/v1/recipes/revise',
      headers: { authorization: `Bearer ${config.APP_ACCESS_TOKEN}` },
      payload: { currentRecipe: recipe, instruction: '多炒一会。' }
    });

    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ kind: 'recipe', recipe, reply });
    expect(service.revise).toHaveBeenCalledWith({ currentRecipe: recipe, instruction: '多炒一会。' });
  });

  it.each([
    ['invalid model output', new InvalidModelOutputError(), 502, 'AI_INVALID_RESPONSE'],
    ['DeepSeek HTTP failure', new DeepSeekHttpError(429), 503, 'AI_UNAVAILABLE'],
    ['aborted DeepSeek request', new DeepSeekRequestAbortedError(), 503, 'AI_UNAVAILABLE'],
    ['transport DeepSeek request', new DeepSeekRequestError(), 503, 'AI_UNAVAILABLE']
  ])('maps %s to a stable public error', async (_label, error, statusCode, code) => {
    const { app } = createApp(createService({
      analyze: vi.fn(async () => { throw error; })
    }));

    const response = await app.inject({
      method: 'POST',
      url: '/api/v1/recipes/analyze',
      headers: { authorization: `Bearer ${config.APP_ACCESS_TOKEN}` },
      payload: { originalText: '番茄炒蛋。' }
    });

    expect(response.statusCode).toBe(statusCode);
    expect(response.json()).toMatchObject({
      error: { code, retryable: statusCode === 503 }
    });
    expect(response.body).not.toContain(error.message);
  });

  it('treats an unexpected service error with a statusCode as an internal error', async () => {
    const serviceError = Object.assign(new Error('service failure'), { statusCode: 400 });
    const { app } = createApp(createService({
      analyze: vi.fn(async () => { throw serviceError; })
    }));

    const response = await app.inject({
      method: 'POST',
      url: '/api/v1/recipes/analyze',
      headers: { authorization: `Bearer ${config.APP_ACCESS_TOKEN}` },
      payload: { originalText: '番茄炒蛋。' }
    });

    expect(response.statusCode).toBe(500);
    expect(response.json()).toMatchObject({
      error: { code: 'INTERNAL_ERROR', retryable: false }
    });
  });

  it.each([
    ['malformed JSON', 'application/json', '{"originalText":'],
    ['unsupported media type', 'application/xml', '<recipe />']
  ])('maps %s parser input to INVALID_REQUEST', async (_label, contentType, payload) => {
    const { app } = createApp();

    const response = await app.inject({
      method: 'POST',
      url: '/api/v1/recipes/analyze',
      headers: {
        authorization: `Bearer ${config.APP_ACCESS_TOKEN}`,
        'content-type': contentType
      },
      payload
    });

    expect(response.statusCode).toBe(400);
    expect(response.json()).toMatchObject({
      error: { code: 'INVALID_REQUEST', retryable: false }
    });
  });

  it('rejects a payload larger than 64 KB', async () => {
    const { app } = createApp();

    const response = await app.inject({
      method: 'POST',
      url: '/api/v1/recipes/analyze',
      headers: {
        authorization: `Bearer ${config.APP_ACCESS_TOKEN}`,
        'content-type': 'application/json'
      },
      payload: JSON.stringify({ originalText: 'x'.repeat(65_536) })
    });

    expect(response.statusCode).toBe(413);
    expect(response.json()).toMatchObject({
      error: { code: 'PAYLOAD_TOO_LARGE', retryable: false }
    });
  });

  it('never logs recipe text, authorization, provider details, or error messages', async () => {
    const privateRecipeText = '绝不能记录的私房菜原文';
    const privateProviderMessage = 'provider detail should stay private';
    const log = vi.fn();
    const { app } = createApp(createService({
      analyze: vi.fn(async () => {
        throw new Error(privateProviderMessage);
      })
    }), log);

    const response = await app.inject({
      method: 'POST',
      url: '/api/v1/recipes/analyze',
      headers: { authorization: `Bearer ${config.APP_ACCESS_TOKEN}` },
      payload: { originalText: privateRecipeText }
    });

    expect(response.statusCode).toBe(500);
    expect(response.json()).toMatchObject({
      error: { code: 'INTERNAL_ERROR', retryable: false }
    });
    const logs = JSON.stringify(log.mock.calls);
    expect(logs).not.toContain(privateRecipeText);
    expect(logs).not.toContain(privateProviderMessage);
    expect(logs).not.toContain(config.APP_ACCESS_TOKEN);
    expect(log).toHaveBeenCalledWith(expect.objectContaining({
      route: '/api/v1/recipes/analyze',
      statusCode: 500
    }));
  });
});
