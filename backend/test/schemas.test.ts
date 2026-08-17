import { describe, expect, it } from 'vitest';
import {
  AnalyzeRequestSchema,
  AnalyzeResultSchema,
  ClarifyingAnswerSchema,
  ClarifyingQuestionSchema,
  RecipeDraftSchema,
  RecipeItemSchema,
  ReviseRequestSchema
} from '../src/domain/schemas.js';

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

  it('requires product-optional recipe collections to be present, even when empty', () => {
    const recipe = {
      name: '葱油鸡',
      ingredients: [],
      seasonings: [],
      steps: ['鸡蒸熟后淋上葱油。'],
      experience: []
    };

    expect(RecipeDraftSchema.parse(recipe)).toMatchObject(recipe);
    expect(() => RecipeDraftSchema.parse({
      name: recipe.name,
      steps: recipe.steps
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

describe('strict object schemas', () => {
  it('rejects an unknown photo field on recipe items', () => {
    expect(() => RecipeItemSchema.parse({
      name: '鸡腿', amount: '1只', isAiEstimated: false, photo: 'https://example.com/chicken.jpg'
    })).toThrow();
  });

  it('rejects an unknown photo field on recipes', () => {
    expect(() => RecipeDraftSchema.parse({
      name: '葱油鸡',
      ingredients: [],
      seasonings: [],
      steps: ['鸡蒸熟后淋上葱油。'],
      experience: [],
      photo: 'https://example.com/chicken.jpg'
    })).toThrow();
  });

  it('rejects an unknown photo field on clarifying answers', () => {
    expect(() => ClarifyingAnswerSchema.parse({
      questionId: 'q1', answer: '老抽一勺。', photo: 'https://example.com/sauce.jpg'
    })).toThrow();
  });

  it('rejects an unknown photo field on clarifying questions', () => {
    expect(() => ClarifyingQuestionSchema.parse({
      id: 'q1', text: '老抽放了多少？', reason: 'critical_item', photo: 'https://example.com/sauce.jpg'
    })).toThrow();
  });

  it('rejects an unknown photo field on analyze requests', () => {
    expect(() => AnalyzeRequestSchema.parse({
      originalText: '今天做了番茄牛腩。', photo: 'https://example.com/beef.jpg'
    })).toThrow();
  });

  it('rejects an unknown photo field on question results', () => {
    expect(() => AnalyzeResultSchema.parse({
      kind: 'questions', questions: [], photo: 'https://example.com/beef.jpg'
    })).toThrow();
  });

  it('rejects an unknown photo field on recipe results', () => {
    expect(() => AnalyzeResultSchema.parse({
      kind: 'recipe',
      recipe: {
        name: '葱油鸡',
        ingredients: [],
        seasonings: [],
        steps: ['鸡蒸熟后淋上葱油。'],
        experience: []
      },
      photo: 'https://example.com/chicken.jpg'
    })).toThrow();
  });

  it('rejects an unknown photo field on revise requests', () => {
    expect(() => ReviseRequestSchema.parse({
      currentRecipe: {
        name: '葱油鸡',
        ingredients: [],
        seasonings: [],
        steps: ['鸡蒸熟后淋上葱油。'],
        experience: []
      },
      instruction: '增加葱花。',
      photo: 'https://example.com/chicken.jpg'
    })).toThrow();
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
