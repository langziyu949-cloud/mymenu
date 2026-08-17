import {
  buildAnalyzeMessages,
  buildReviseMessages,
  type PromptMessage
} from '../ai/prompts.js';
import {
  DeepSeekResponseError,
  DeepSeekTruncatedResponseError,
  type ChatCompletionClient
} from '../ai/deepSeekClient.js';
import type { AnalyzeRequest, AnalyzeResult, RecipeDraft, RecipeRevision, ReviseRequest } from '../domain/recipe.js';
import { AnalyzeResultSchema, RecipeRevisionSchema } from '../domain/schemas.js';

export class InvalidModelOutputError extends Error {
  constructor() {
    super('Model returned invalid recipe JSON');
    this.name = 'InvalidModelOutputError';
  }
}

export class RecipeService {
  constructor(private readonly client: ChatCompletionClient) {}

  async analyze(request: AnalyzeRequest): Promise<AnalyzeResult> {
    return this.completeWithRetry(buildAnalyzeMessages(request), (value) => {
      const result = AnalyzeResultSchema.parse(value);
      if (request.answers !== undefined && result.kind !== 'recipe') {
        throw new InvalidModelOutputError();
      }
      if (result.kind === 'questions' && questionsContradictSource(request.originalText, result)) {
        throw new InvalidModelOutputError();
      }
      return result;
    });
  }

  async revise(request: ReviseRequest): Promise<RecipeRevision> {
    const revision = await this.completeWithRetry(
      buildReviseMessages(request),
      (value) => RecipeRevisionSchema.parse(value)
    );
    const previousReplies = request.previousReplies ?? [];
    if (previousReplies.some(reply => normalizeReply(reply) === normalizeReply(revision.reply))) {
      return {
        recipe: revision.recipe,
        reply: buildRevisionFallbackReply(request.currentRecipe, revision.recipe, request.instruction)
      };
    }
    return revision;
  }

  private async completeWithRetry<T>(
    messages: PromptMessage[],
    parse: (value: unknown) => T
  ): Promise<T> {
    for (let attempt = 0; attempt < 2; attempt += 1) {
      let content: string;

      try {
        const attemptMessages: PromptMessage[] = attempt === 0 ? messages : [
          ...messages,
          {
            role: 'user',
            content: '上一次输出违反了必填字段判断或 JSON 结构规则。请重新阅读原始文本：句首菜名和简略但可执行的动作都算已提供；不要重复错误，只返回符合规则的 JSON。'
          }
        ];
        content = await this.client.complete(attemptMessages);
      } catch (error) {
        if (!this.isRetryableOutputError(error)) {
          throw error;
        }
        if (attempt === 1) {
          throw new InvalidModelOutputError();
        }
        continue;
      }

      try {
        if (content.trim().length === 0) {
          throw new InvalidModelOutputError();
        }
        return parse(JSON.parse(content));
      } catch {
        if (attempt === 1) {
          throw new InvalidModelOutputError();
        }
      }
    }

    throw new InvalidModelOutputError();
  }

  private isRetryableOutputError(error: unknown): boolean {
    return error instanceof DeepSeekResponseError || error instanceof DeepSeekTruncatedResponseError;
  }
}

function normalizeReply(value: string): string {
  return value.replace(/[\s，。！？、；：“”‘’"']/gu, '').toLocaleLowerCase();
}

function buildRevisionFallbackReply(before: RecipeDraft, after: RecipeDraft, instruction: string): string {
  const changes: string[] = [];
  if (before.name !== after.name) {
    changes.push(`菜名改为“${after.name}”`);
  }
  if (JSON.stringify(before.ingredients) !== JSON.stringify(after.ingredients)) {
    changes.push('食材及用量已更新');
  }
  if (JSON.stringify(before.seasonings) !== JSON.stringify(after.seasonings)) {
    changes.push('调料及用量已更新');
  }
  if (JSON.stringify(before.steps) !== JSON.stringify(after.steps)) {
    changes.push('制作步骤已同步调整');
  }
  if (JSON.stringify(before.experience) !== JSON.stringify(after.experience)) {
    changes.push('经验建议已更新');
  }
  const cleanInstruction = instruction.trim().replace(/[。！!？?]+$/u, '');
  const summary = cleanInstruction.length > 28 ? `${cleanInstruction.slice(0, 28)}…` : cleanInstruction;
  if (changes.length === 0) {
    return `我检查了“${summary}”，当前菜谱没有需要落地的变化。请直接说要改哪种食材、用量或步骤。`;
  }
  return `这次根据“${summary}”，${changes.slice(0, 2).join('，')}。其余内容保持不变。`;
}

function questionsContradictSource(originalText: string, result: Extract<AnalyzeResult, { kind: 'questions' }>): boolean {
  return result.questions.some(question => {
    if (question.reason === 'missing_name') {
      return hasLikelyDishName(originalText);
    }
    if (question.reason === 'missing_steps') {
      return hasActionableStep(originalText);
    }
    return false;
  });
}

function hasLikelyDishName(originalText: string): boolean {
  if (/菜名\s*(?:叫|是|为|：|:)\s*[^，,。；;\n]{2,20}/u.test(originalText)) {
    return true;
  }

  const firstSegment = originalText.trim().split(/[，,。；;：:\n]/u, 1)[0]
    ?.replace(/^(?:今天|昨晚|今晚|中午|早上|晚上)?\s*(?:做了(?:一道|个)?|做的是|做)\s*/u, '')
    .trim() ?? '';
  if (firstSegment.length < 2 || firstSegment.length > 16) {
    return false;
  }
  return /炒|炖|烧|煮|煎|炸|蒸|烤|拌|汤|羹|粥|面|饭|饼|蛋|肉|鱼|鸡|鸭|虾|豆腐/u.test(firstSegment);
}

function hasActionableStep(originalText: string): boolean {
  return /放油|下锅|加入|放入|倒入|切|炒|煮|煎|炸|蒸|炖|烤|焯|腌|拌|洗|收汁/u.test(originalText);
}
