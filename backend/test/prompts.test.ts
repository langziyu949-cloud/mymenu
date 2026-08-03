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

  it('does not interrupt a complete recipe for optional details', () => {
    const text = buildAnalyzeMessages({ originalText: '番茄炒蛋：先炒鸡蛋，再炒番茄，最后混合。' })
      .map((message) => message.content)
      .join('\n');

    expect(text).toContain('只要菜名和至少一个可执行步骤已具备，必须直接返回 kind: "recipe"');
    expect(text).toContain('绝不为可选做法、口味偏好、是否去皮、火候细节、食材或调料用量追问');
  });

  it('keeps retrospective experience out of cooking steps', () => {
    const text = buildAnalyzeMessages({ originalText: '下次番茄要炒出汁再放鸡蛋。' })
      .map((message) => message.content)
      .join('\n');

    expect(text).toContain('已经放入 experience 的内容不得同时出现在 steps');
    expect(text).toContain('steps 只保留本次制作所需的可执行步骤');
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

  it('requires revisions to update every reference to the changed fact', () => {
    const text = buildReviseMessages({
      currentRecipe: {
        name: '番茄炒蛋',
        ingredients: [],
        seasonings: [{ name: '糖', amount: '半勺', isAiEstimated: false }],
        steps: ['放半勺糖。'],
        experience: []
      },
      instruction: '糖改成四分之一勺。'
    }).map((message) => message.content).join('\n');

    expect(text).toContain('必须同步更新所有相关引用以避免菜谱自相矛盾');
    expect(text).toContain('同时更新 seasonings 和 steps 中出现的该用量');
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
