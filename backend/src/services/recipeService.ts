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
import type { AnalyzeRequest, AnalyzeResult, RecipeDraft, ReviseRequest } from '../domain/recipe.js';
import { AnalyzeResultSchema, RecipeDraftSchema } from '../domain/schemas.js';

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
      if (request.answers !== undefined && result.kind === 'questions') {
        throw new InvalidModelOutputError();
      }
      return result;
    });
  }

  async revise(request: ReviseRequest): Promise<RecipeDraft> {
    return this.completeWithRetry(
      buildReviseMessages(request),
      (value) => RecipeDraftSchema.parse(value)
    );
  }

  private async completeWithRetry<T>(
    messages: PromptMessage[],
    parse: (value: unknown) => T
  ): Promise<T> {
    for (let attempt = 0; attempt < 2; attempt += 1) {
      let content: string;

      try {
        content = await this.client.complete(messages);
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
