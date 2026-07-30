import { describe, expect, it } from 'vitest';
import { buildAnalyzeMessages, buildReviseMessages } from '../src/ai/prompts.js';

describe('recipe prompts', () => {
  it('requires JSON and forbids invented experience', () => {
    const messages = buildAnalyzeMessages({ originalText: '放番茄炖牛腩。' });
    const text = messages.map((message) => message.content).join('\n');
    expect(text).toContain('JSON');
    expect(text).toContain('最多三个');
    expect(text).toContain('不得生成用户没有表达的经验建议');
    expect(text).toContain('放番茄炖牛腩。');
  });

  it('tells revision to preserve unrelated fields', () => {
    const messages = buildReviseMessages({
      currentRecipe: {
        name: '番茄牛腩',
        ingredients: [],
        seasonings: [],
        steps: ['炖煮。'],
        experience: []
      },
      instruction: '老抽改成半勺'
    });
    expect(messages.map((message) => message.content).join('\n'))
      .toContain('不得修改指令未涉及的字段');
  });
});
