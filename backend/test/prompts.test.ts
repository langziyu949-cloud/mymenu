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

  it('distinguishes first analysis from the completed clarification round', () => {
    const initialText = buildAnalyzeMessages({ originalText: '放番茄炖牛腩。' })
      .map((message) => message.content)
      .join('\n');
    const followUpText = buildAnalyzeMessages({
      originalText: '放番茄炖牛腩。',
      answers: []
    }).map((message) => message.content).join('\n');

    expect(initialText).toContain('首次分析');
    expect(initialText).toContain('尚未提供澄清回答');
    expect(followUpText).toContain('唯一一轮澄清已完成');
    expect(followUpText).toContain('必须返回 kind: "recipe"');
  });

  it('requires exact estimate provenance for every recipe item', () => {
    const text = buildAnalyzeMessages({ originalText: '放番茄炖牛腩。' })
      .map((message) => message.content)
      .join('\n');

    expect(text).toContain('每个 ingredients 和 seasonings 项必须输出 { name, amount, isAiEstimated }');
    expect(text).toContain('仅当 amount 是 AI 根据上下文估算的用量时，isAiEstimated 为 true；否则为 false。');
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

  it('requires revision to return a raw recipe draft without an envelope', () => {
    const text = buildReviseMessages({
      currentRecipe: {
        name: '番茄牛腩',
        ingredients: [],
        seasonings: [],
        steps: ['炖煮。'],
        experience: []
      },
      instruction: '老抽改成半勺'
    }).map((message) => message.content).join('\n');

    expect(text).toContain('{"name":"...","ingredients":[],"seasonings":[],"steps":[],"experience":[]}');
    expect(text).not.toContain('{"kind":"recipe","recipe":');
  });
});
