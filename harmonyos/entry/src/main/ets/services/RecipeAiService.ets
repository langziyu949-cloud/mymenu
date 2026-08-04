import { cloudFunction } from '@kit.CloudFoundationKit';

const CLOUD_FUNCTION_NAME: string = 'kitchen-master-ai';

export interface AiRecipeItem {
  name: string;
  amount: string;
  isAiEstimated: boolean;
}

export interface AiRecipeDraft {
  name: string;
  ingredients: AiRecipeItem[];
  seasonings: AiRecipeItem[];
  steps: string[];
  experience: string[];
}

export interface AiClarifyingQuestion {
  id: string;
  text: string;
  reason: string;
}

export interface AiClarifyingAnswer {
  questionId: string;
  answer: string;
}

export interface AiAnalyzeResult {
  kind: string;
  questions: AiClarifyingQuestion[];
  recipe: AiRecipeDraft | null;
}

interface AnalyzePayload {
  originalText: string;
  answers?: AiClarifyingAnswer[];
}

interface RevisePayload {
  currentRecipe: AiRecipeDraft;
  instruction: string;
}

interface CloudActionEnvelope {
  action: string;
  payload?: AnalyzePayload | RevisePayload;
}

interface RawAnalyzeResult {
  kind: string;
  questions?: AiClarifyingQuestion[];
  recipe?: AiRecipeDraft;
}

interface ApiErrorDetail {
  code?: string;
  retryable?: boolean;
}

interface ApiErrorEnvelope {
  error?: ApiErrorDetail;
}

interface CloudHttpResponse {
  statusCode?: number;
  body?: string;
}

export class RecipeAiServiceError extends Error {
  readonly code: string;
  readonly retryable: boolean;

  constructor(code: string, retryable: boolean) {
    super(code);
    this.name = 'RecipeAiServiceError';
    this.code = code;
    this.retryable = retryable;
  }
}

export class RecipeAiService {
  async isAvailable(): Promise<boolean> {
    try {
      const content: string = await this.call({ action: 'health' }, 10000);
      const health: Record<string, string> = JSON.parse(content) as Record<string, string>;
      return health.status === 'ok';
    } catch {
      return false;
    }
  }

  async analyze(originalText: string, answers?: AiClarifyingAnswer[]): Promise<AiAnalyzeResult> {
    const payload: AnalyzePayload = answers === undefined ? { originalText } : { originalText, answers };
    const raw: RawAnalyzeResult = JSON.parse(await this.call({ action: 'analyze', payload })) as RawAnalyzeResult;
    if (raw.kind === 'questions') {
      return { kind: raw.kind, questions: raw.questions ?? [], recipe: null };
    }
    if (raw.kind === 'recipe' && raw.recipe !== undefined) {
      return { kind: raw.kind, questions: [], recipe: raw.recipe };
    }
    throw new RecipeAiServiceError('AI_INVALID_RESPONSE', true);
  }

  async revise(currentRecipe: AiRecipeDraft, instruction: string): Promise<AiRecipeDraft> {
    const payload: RevisePayload = { currentRecipe, instruction };
    const raw: RawAnalyzeResult = JSON.parse(await this.call({ action: 'revise', payload })) as RawAnalyzeResult;
    if (raw.kind !== 'recipe' || raw.recipe === undefined) {
      throw new RecipeAiServiceError('AI_INVALID_RESPONSE', true);
    }
    return raw.recipe;
  }

  private async call(envelope: CloudActionEnvelope, timeout: number = 65000): Promise<string> {
    try {
      const response: cloudFunction.FunctionResult = await cloudFunction.call({
        name: CLOUD_FUNCTION_NAME,
        data: envelope,
        version: '$latest',
        timeout
      });
      return this.unwrapResponse(response.result);
    } catch (error) {
      if (error instanceof RecipeAiServiceError) {
        throw error;
      }
      throw new RecipeAiServiceError('AI_UNAVAILABLE', true);
    }
  }

  private unwrapResponse(result: string | Object): string {
    const serialized: string = typeof result === 'string' ? result : JSON.stringify(result);
    let response: CloudHttpResponse;
    try {
      response = JSON.parse(serialized) as CloudHttpResponse;
    } catch {
      throw new RecipeAiServiceError('AI_INVALID_RESPONSE', true);
    }

    if (response.statusCode === undefined || response.body === undefined) {
      return serialized;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw this.apiError(response.body, response.statusCode);
    }
    return response.body;
  }

  private apiError(content: string, statusCode: number): RecipeAiServiceError {
    try {
      const envelope: ApiErrorEnvelope = JSON.parse(content) as ApiErrorEnvelope;
      return new RecipeAiServiceError(
        envelope.error?.code ?? `HTTP_${statusCode}`,
        envelope.error?.retryable ?? statusCode >= 500
      );
    } catch {
      return new RecipeAiServiceError(`HTTP_${statusCode}`, statusCode >= 500);
    }
  }
}
