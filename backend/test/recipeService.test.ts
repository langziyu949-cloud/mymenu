import { describe, expect, it } from 'vitest';
import {
  DeepSeekHttpError,
  DeepSeekRequestAbortedError,
  DeepSeekRequestError,
  DeepSeekResponseError,
  DeepSeekTruncatedResponseError,
  type ChatCompletionClient,
  type ChatMessage
} from '../src/ai/deepSeekClient.js';
import type { RecipeDraft } from '../src/domain/recipe.js';
import { InvalidModelOutputError, RecipeService } from '../src/services/recipeService.js';

class FakeClient implements ChatCompletionClient {
  public calls = 0;

  constructor(private readonly responses: string[]) {}

  async complete(_messages: ChatMessage[]): Promise<string> {
    const response = this.responses[this.calls];
    this.calls += 1;
    return response ?? '';
  }
}

class ErrorThenResponseClient implements ChatCompletionClient {
  public calls = 0;

  constructor(private readonly responses: Array<Error | string>) {}

  async complete(_messages: ChatMessage[]): Promise<string> {
    const response = this.responses[this.calls];
    this.calls += 1;
    if (response instanceof Error) {
      throw response;
    }
    return response ?? '';
  }
}

const validRecipe = {
  name: '番茄炒蛋',
  ingredients: [{ name: '番茄', amount: '2 个', isAiEstimated: false }],
  seasonings: [],
  steps: ['炒熟番茄。'],
  experience: []
} satisfies RecipeDraft;

const reply = '番茄炒蛋的食材和步骤都理顺了，火候细节也可以继续告诉我。';
const recipeResponse = JSON.stringify({ kind: 'recipe', recipe: validRecipe, reply });

describe('RecipeService', () => {
  it('returns a valid analyzed recipe after one completion', async () => {
    const client = new FakeClient([recipeResponse]);

    await expect(new RecipeService(client).analyze({ originalText: '番茄炒蛋。' }))
      .resolves.toEqual({ kind: 'recipe', recipe: validRecipe, reply });
    expect(client.calls).toBe(1);
  });

  it('retries empty completion content once', async () => {
    const client = new FakeClient(['', recipeResponse]);

    await expect(new RecipeService(client).analyze({ originalText: '番茄炒蛋。' }))
      .resolves.toEqual({ kind: 'recipe', recipe: validRecipe, reply });
    expect(client.calls).toBe(2);
  });

  it('retries malformed JSON once', async () => {
    const client = new FakeClient(['{"kind":', recipeResponse]);

    await expect(new RecipeService(client).analyze({ originalText: '番茄炒蛋。' }))
      .resolves.toEqual({ kind: 'recipe', recipe: validRecipe, reply });
    expect(client.calls).toBe(2);
  });

  it('throws InvalidModelOutputError after two invalid completions', async () => {
    const client = new FakeClient(['', 'not JSON']);

    await expect(new RecipeService(client).analyze({ originalText: '番茄炒蛋。' }))
      .rejects.toBeInstanceOf(InvalidModelOutputError);
    expect(client.calls).toBe(2);
  });

  it('retries four returned clarifying questions once', async () => {
    const fourQuestions = JSON.stringify({
      kind: 'questions',
      questions: [
        { id: 'q1', text: '菜名？', reason: 'missing_name' },
        { id: 'q2', text: '步骤？', reason: 'missing_steps' },
        { id: 'q3', text: '食材？', reason: 'critical_item' },
        { id: 'q4', text: '冲突？', reason: 'conflict' }
      ]
    });
    const client = new FakeClient([fourQuestions, recipeResponse]);

    await expect(new RecipeService(client).analyze({ originalText: '番茄炒蛋。' }))
      .resolves.toEqual({ kind: 'recipe', recipe: validRecipe, reply });
    expect(client.calls).toBe(2);
  });

  it('retries questions returned after answers were provided', async () => {
    const questions = JSON.stringify({
      kind: 'questions',
      questions: [{ id: 'q1', text: '还需要补充吗？', reason: 'critical_item' }]
    });
    const client = new FakeClient([questions, recipeResponse]);

    await expect(new RecipeService(client).analyze({
      originalText: '番茄炒蛋。',
      answers: []
    })).resolves.toEqual({ kind: 'recipe', recipe: validRecipe, reply });
    expect(client.calls).toBe(2);
  });

  it('retries questions that contradict an explicit dish name and cooking action', async () => {
    const questions = JSON.stringify({
      kind: 'questions',
      questions: [
        { id: 'q1', text: '这道菜叫什么名字？', reason: 'missing_name' },
        { id: 'q2', text: '请提供具体的制作步骤。', reason: 'missing_steps' }
      ]
    });
    const client = new FakeClient([questions, recipeResponse]);

    await expect(new RecipeService(client).analyze({
      originalText: '番茄炒蛋，用两个鸡蛋和两个番茄，锅里放油炒熟。'
    })).resolves.toEqual({ kind: 'recipe', recipe: validRecipe, reply });
    expect(client.calls).toBe(2);
  });

  it.each([
    ['response error', new DeepSeekResponseError()],
    ['truncated response', new DeepSeekTruncatedResponseError()]
  ])('retries a retryable adapter %s once', async (_label, error) => {
    const client = new ErrorThenResponseClient([error, recipeResponse]);

    await expect(new RecipeService(client).analyze({ originalText: '番茄炒蛋。' }))
      .resolves.toEqual({ kind: 'recipe', recipe: validRecipe, reply });
    expect(client.calls).toBe(2);
  });

  it.each([
    ['HTTP', new DeepSeekHttpError(429)],
    ['aborted request', new DeepSeekRequestAbortedError()],
    ['transport request', new DeepSeekRequestError()]
  ])('passes through %s errors without retrying', async (_label, error) => {
    const client = new ErrorThenResponseClient([error, recipeResponse]);

    await expect(new RecipeService(client).analyze({ originalText: '番茄炒蛋。' }))
      .rejects.toBe(error);
    expect(client.calls).toBe(1);
  });

  it('rejects a revised recipe with an empty name', async () => {
    const client = new FakeClient([
      JSON.stringify({ recipe: { ...validRecipe, name: '   ' }, reply }),
      JSON.stringify({ recipe: { ...validRecipe, name: '' }, reply })
    ]);

    await expect(new RecipeService(client).revise({ currentRecipe: validRecipe, instruction: '换个名字。' }))
      .rejects.toBeInstanceOf(InvalidModelOutputError);
  });

  it('rejects a revised recipe without steps', async () => {
    const client = new FakeClient([
      JSON.stringify({ recipe: { ...validRecipe, steps: [] }, reply }),
      JSON.stringify({ recipe: { ...validRecipe, steps: [] }, reply })
    ]);

    await expect(new RecipeService(client).revise({ currentRecipe: validRecipe, instruction: '简化步骤。' }))
      .rejects.toBeInstanceOf(InvalidModelOutputError);
  });

  it('returns a valid revised recipe', async () => {
    const revisedRecipe = { ...validRecipe, name: '番茄滑蛋' };
    const revisedReply = '菜名已经换成“番茄滑蛋”，其余做法保持原样。';
    const client = new FakeClient([JSON.stringify({ recipe: revisedRecipe, reply: revisedReply })]);

    await expect(new RecipeService(client).revise({ currentRecipe: validRecipe, instruction: '改为番茄滑蛋。' }))
      .resolves.toEqual({ recipe: revisedRecipe, reply: revisedReply });
    expect(client.calls).toBe(1);
  });

  it('returns a specific diff reply when the model repeats an earlier revision reply', async () => {
    const revisedRecipe = {
      ...validRecipe,
      seasonings: [{ name: '盐', amount: '两勺', isAiEstimated: false }]
    };
    const repeatedReply = '辣椒少放让口味更温和。';
    const client = new FakeClient([JSON.stringify({ recipe: revisedRecipe, reply: repeatedReply })]);

    await expect(new RecipeService(client).revise({
      currentRecipe: validRecipe,
      instruction: '盐改成两勺',
      previousReplies: [repeatedReply]
    })).resolves.toEqual({
      recipe: revisedRecipe,
      reply: '这次根据“盐改成两勺”，调料及用量已更新。其余内容保持不变。'
    });
  });

  it('accepts a guidance response for clearly out-of-scope first input', async () => {
    const guidance = {
      kind: 'guidance',
      reply: '我只能帮你整理家常菜谱。可以告诉我菜名、食材和制作步骤。'
    } as const;
    const client = new FakeClient([JSON.stringify(guidance)]);

    await expect(new RecipeService(client).analyze({ originalText: '帮我写一段代码。' }))
      .resolves.toEqual(guidance);
  });
});
