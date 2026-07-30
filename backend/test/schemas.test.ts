import { describe, expect, it } from 'vitest';
import { AnalyzeRequestSchema, RecipeDraftSchema, ReviseRequestSchema } from '../src/domain/schemas.js';

describe('RecipeDraftSchema', () => {
  it('accepts the smallest saveable recipe', () => {
    expect(RecipeDraftSchema.parse({
      name: '葱油鸡',
      ingredients: [],
      seasonings: [],
      steps: ['鸡蒸熟后淋上葱油。'],
      experience: []
    }).name).toBe('葱油鸡');
  });

  it('rejects a recipe without a name or steps', () => {
    expect(() => RecipeDraftSchema.parse({
      name: '',
      ingredients: [],
      seasonings: [],
      steps: [],
      experience: []
    })).toThrow();
  });

  it('preserves amount estimate provenance', () => {
    const recipe = RecipeDraftSchema.parse({
      name: '番茄牛腩',
      ingredients: [{ name: '牛腩', amount: '2斤', isAiEstimated: false }],
      seasonings: [{ name: '老抽', amount: '1勺', isAiEstimated: true }],
      steps: ['牛腩焯水后炖煮。'],
      experience: ['番茄分两次放。']
    });
    expect(recipe.seasonings[0]?.isAiEstimated).toBe(true);
  });
});

describe('request schemas', () => {
  it('accepts analyze text and optional answers', () => {
    expect(AnalyzeRequestSchema.parse({
      originalText: '今天做了番茄牛腩。',
      answers: [{ questionId: 'q1', answer: '老抽一勺。' }]
    }).answers).toHaveLength(1);
  });

  it('requires a revision instruction and current recipe', () => {
    expect(() => ReviseRequestSchema.parse({ instruction: '' })).toThrow();
  });
});
