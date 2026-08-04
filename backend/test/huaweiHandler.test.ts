import { describe, expect, it, vi } from 'vitest';
import {
  DeepSeekHttpError,
  DeepSeekRequestAbortedError,
  DeepSeekRequestError
} from '../src/ai/deepSeekClient.js';
import type { AnalyzeRequest, AnalyzeResult, RecipeDraft, ReviseRequest } from '../src/domain/recipe.js';
import { buildHuaweiHandler } from '../src/huawei/buildHuaweiHandler.js';
import { InvalidModelOutputError } from '../src/services/recipeService.js';

const recipe: RecipeDraft = {
  name: '番茄炒蛋',
  ingredients: [{ name: '番茄', amount: '2 个', isAiEstimated: false }],
  seasonings: [],
  steps: ['炒熟番茄。'],
  experience: []
};

interface RecipeServiceDependency {
  analyze(request: AnalyzeRequest): Promise<AnalyzeResult>;
  revise(request: ReviseRequest): Promise<RecipeDraft>;
}

function createService(overrides: Partial<RecipeServiceDependency> = {}): RecipeServiceDependency {
  return {
    analyze: vi.fn(async () => ({ kind: 'recipe', recipe })),
    revise: vi.fn(async () => recipe),
    ...overrides
  };
}

function createHandler(service = createService(), log = vi.fn()) {
  return {
    handler: buildHuaweiHandler({
      service,
      logger: { info: log }
    }),
    log
  };
}

function authorizedEvent(body: unknown) {
  return {
    httpMethod: 'POST',
    body: JSON.stringify(body),
    isBase64Encoded: false
  };
}

describe('Huawei AGC cloud function handler', () => {
  it('supports a health action without authorization', async () => {
    const { handler } = createHandler();
    const response = await handler({ body: JSON.stringify({ action: 'health' }) });

    expect(response.statusCode).toBe(200);
    expect(JSON.parse(response.body)).toEqual({ status: 'ok' });
  });

  it('analyzes an action envelope after AGC gateway authentication', async () => {
    const service = createService();
    const { handler } = createHandler(service);
    const response = await handler(authorizedEvent({
      action: 'analyze',
      payload: { originalText: '番茄炒蛋。' }
    }));

    expect(response.statusCode).toBe(200);
    expect(JSON.parse(response.body)).toEqual({ kind: 'recipe', recipe });
    expect(service.analyze).toHaveBeenCalledWith({ originalText: '番茄炒蛋。' });
  });

  it('revises a base64 encoded action envelope', async () => {
    const service = createService();
    const { handler } = createHandler(service);
    const body = Buffer.from(JSON.stringify({
      action: 'revise',
      payload: { currentRecipe: recipe, instruction: '多炒一会。' }
    })).toString('base64');
    const response = await handler({
      body,
      isBase64Encoded: true
    });

    expect(response.statusCode).toBe(200);
    expect(JSON.parse(response.body)).toEqual({ kind: 'recipe', recipe });
    expect(service.revise).toHaveBeenCalledWith({ currentRecipe: recipe, instruction: '多炒一会。' });
  });

  it('keeps compatibility with path-based requests', async () => {
    const service = createService();
    const { handler } = createHandler(service);
    const response = await handler({
      ...authorizedEvent({ originalText: '番茄炒蛋。' }),
      path: '/api/v1/recipes/analyze'
    });

    expect(response.statusCode).toBe(200);
    expect(service.analyze).toHaveBeenCalledWith({ originalText: '番茄炒蛋。' });
  });

  it('rejects invalid and oversized requests', async () => {
    const { handler } = createHandler();

    const invalid = await handler(authorizedEvent({ action: 'analyze', payload: { originalText: '' } }));
    expect(invalid.statusCode).toBe(400);
    expect(JSON.parse(invalid.body)).toMatchObject({ error: { code: 'INVALID_REQUEST' } });

    const oversized = await handler(authorizedEvent({
      action: 'analyze',
      payload: { originalText: 'x'.repeat(65_536) }
    }));
    expect(oversized.statusCode).toBe(413);
    expect(JSON.parse(oversized.body)).toMatchObject({ error: { code: 'PAYLOAD_TOO_LARGE' } });
  });

  it.each([
    ['invalid model output', new InvalidModelOutputError(), 502, 'AI_INVALID_RESPONSE'],
    ['DeepSeek HTTP failure', new DeepSeekHttpError(429), 503, 'AI_UNAVAILABLE'],
    ['aborted DeepSeek request', new DeepSeekRequestAbortedError(), 503, 'AI_UNAVAILABLE'],
    ['transport DeepSeek request', new DeepSeekRequestError(), 503, 'AI_UNAVAILABLE']
  ])('maps %s to a stable public response', async (_label, error, statusCode, code) => {
    const { handler } = createHandler(createService({
      analyze: vi.fn(async () => { throw error; })
    }));
    const response = await handler(authorizedEvent({
      action: 'analyze',
      payload: { originalText: '番茄炒蛋。' }
    }));

    expect(response.statusCode).toBe(statusCode);
    expect(JSON.parse(response.body)).toMatchObject({ error: { code } });
    expect(response.body).not.toContain(error.message);
  });

  it('does not log recipe text or provider errors', async () => {
    const privateText = '绝不能记录的私房菜原文';
    const privateError = 'private provider detail';
    const log = vi.fn();
    const { handler } = createHandler(createService({
      analyze: vi.fn(async () => { throw new Error(privateError); })
    }), log);

    await handler(authorizedEvent({ action: 'analyze', payload: { originalText: privateText } }));

    const logs = JSON.stringify(log.mock.calls);
    expect(logs).not.toContain(privateText);
    expect(logs).not.toContain(privateError);
    expect(log).toHaveBeenCalledWith(expect.objectContaining({
      route: 'analyze',
      statusCode: 500
    }));
  });
});
