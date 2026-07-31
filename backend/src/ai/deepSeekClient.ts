import type { AppConfig } from '../config.js';

export interface ChatMessage {
  role: 'system' | 'user';
  content: string;
}

export interface ChatCompletionClient {
  complete(messages: ChatMessage[]): Promise<string>;
}

export class DeepSeekHttpError extends Error {
  constructor(public readonly status: number) {
    super(`DeepSeek request failed with status ${status}`);
    this.name = 'DeepSeekHttpError';
  }
}

export class DeepSeekTruncatedResponseError extends Error {
  constructor() {
    super('DeepSeek response was truncated');
    this.name = 'DeepSeekTruncatedResponseError';
  }
}

export class DeepSeekResponseError extends Error {
  constructor() {
    super('DeepSeek response was invalid');
    this.name = 'DeepSeekResponseError';
  }
}

export class DeepSeekRequestAbortedError extends Error {
  constructor() {
    super('DeepSeek request was aborted');
    this.name = 'DeepSeekRequestAbortedError';
  }
}

export class DeepSeekRequestError extends Error {
  constructor() {
    super('DeepSeek request failed');
    this.name = 'DeepSeekRequestError';
  }
}

interface CompletionPayload {
  choices?: Array<{
    message?: { content?: unknown };
    finish_reason?: unknown;
  }>;
}

type DeepSeekConfig = Pick<AppConfig, 'DEEPSEEK_API_KEY' | 'DEEPSEEK_BASE_URL' | 'DEEPSEEK_MODEL'>;

export class DeepSeekClient implements ChatCompletionClient {
  constructor(private readonly config: DeepSeekConfig) {}

  async complete(messages: ChatMessage[]): Promise<string> {
    const timeout = AbortSignal.timeout(30_000);
    let response: Response;

    try {
      response = await fetch(this.completionsUrl(), {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${this.config.DEEPSEEK_API_KEY}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          model: this.config.DEEPSEEK_MODEL,
          messages,
          thinking: { type: 'disabled' },
          response_format: { type: 'json_object' },
          max_tokens: 4096,
          stream: false
        }),
        signal: timeout
      });
    } catch {
      if (timeout.aborted) {
        throw new DeepSeekRequestAbortedError();
      }
      throw new DeepSeekRequestError();
    }

    if (!response.ok) {
      throw new DeepSeekHttpError(response.status);
    }

    const payload = await this.parsePayload(response, timeout);
    const choice = payload.choices?.[0];
    if (choice?.finish_reason === 'length') {
      throw new DeepSeekTruncatedResponseError();
    }

    const content = choice?.message?.content;
    if (typeof content !== 'string' || content.trim().length === 0) {
      throw new DeepSeekResponseError();
    }

    return content;
  }

  private completionsUrl(): string {
    return `${this.config.DEEPSEEK_BASE_URL.replace(/\/+$/, '')}/chat/completions`;
  }

  private async parsePayload(response: Response, timeout: AbortSignal): Promise<CompletionPayload> {
    try {
      const payload: unknown = await response.json();
      if (typeof payload !== 'object' || payload === null || Array.isArray(payload)) {
        throw new DeepSeekResponseError();
      }
      return payload as CompletionPayload;
    } catch (error) {
      if (error instanceof DeepSeekResponseError) {
        throw error;
      }
      if (timeout.aborted || this.isAbortError(error)) {
        throw new DeepSeekRequestAbortedError();
      }
      throw new DeepSeekRequestError();
    }
  }

  private isAbortError(error: unknown): boolean {
    return typeof error === 'object' && error !== null &&
      'name' in error && error.name === 'AbortError';
  }
}
