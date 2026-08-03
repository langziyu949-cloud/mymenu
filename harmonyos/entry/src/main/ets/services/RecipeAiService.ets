import { http } from '@kit.NetworkKit';

const API_BASE_URL: string = 'http://127.0.0.1:9000/api/v1';
const APP_ACCESS_TOKEN: string = 'kitchen-master-local-demo-v1';

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
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(`${API_BASE_URL}/health`, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false,
        connectTimeout: 3000,
        readTimeout: 3000
      });
      return response.responseCode === http.ResponseCode.OK;
    } catch {
      return false;
    } finally {
      request.destroy();
    }
  }

  async analyze(originalText: string, answers?: AiClarifyingAnswer[]): Promise<AiAnalyzeResult> {
    const body: string = answers === undefined ?
      JSON.stringify({ originalText }) : JSON.stringify({ originalText, answers });
    const raw: RawAnalyzeResult = JSON.parse(await this.post('/recipes/analyze', body)) as RawAnalyzeResult;
    if (raw.kind === 'questions') {
      return { kind: raw.kind, questions: raw.questions ?? [], recipe: null };
    }
    if (raw.kind === 'recipe' && raw.recipe !== undefined) {
      return { kind: raw.kind, questions: [], recipe: raw.recipe };
    }
    throw new RecipeAiServiceError('AI_INVALID_RESPONSE', true);
  }

  async revise(currentRecipe: AiRecipeDraft, instruction: string): Promise<AiRecipeDraft> {
    const body: string = JSON.stringify({ currentRecipe, instruction });
    const raw: RawAnalyzeResult = JSON.parse(await this.post('/recipes/revise', body)) as RawAnalyzeResult;
    if (raw.kind !== 'recipe' || raw.recipe === undefined) {
      throw new RecipeAiServiceError('AI_INVALID_RESPONSE', true);
    }
    return raw.recipe;
  }

  private async post(path: string, body: string): Promise<string> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(`${API_BASE_URL}${path}`, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${APP_ACCESS_TOKEN}`
        },
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false,
        connectTimeout: 8000,
        readTimeout: 40000
      });
      const content: string = typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw this.apiError(content, response.responseCode);
      }
      return content;
    } finally {
      request.destroy();
    }
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
