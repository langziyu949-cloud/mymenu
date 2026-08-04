import type { AppConfig } from '../config.js';
import type { AnalyzeRequest, AnalyzeResult, RecipeDraft, ReviseRequest } from '../domain/recipe.js';
import { AnalyzeRequestSchema, ReviseRequestSchema } from '../domain/schemas.js';
import {
  hasExpectedBearerToken,
  mapError,
  type RequestLogEntry,
  UnauthorizedError
} from '../http/buildServer.js';
import { createPublicError } from '../http/errors.js';

interface RecipeServiceDependency {
  analyze(request: AnalyzeRequest): Promise<AnalyzeResult>;
  revise(request: ReviseRequest): Promise<RecipeDraft>;
}

export interface HuaweiHttpEvent {
  path?: unknown;
  httpMethod?: unknown;
  headers?: unknown;
  body?: unknown;
  isBase64Encoded?: unknown;
}

export interface HuaweiHttpResponse {
  statusCode: number;
  headers: Record<string, string>;
  isBase64Encoded: false;
  body: string;
}

export interface BuildHuaweiHandlerDependencies {
  config: Pick<AppConfig, 'APP_ACCESS_TOKEN'>;
  service: RecipeServiceDependency;
  logger?: { info(entry: RequestLogEntry): void };
}

type Action = 'health' | 'analyze' | 'revise';

interface ActionEnvelope {
  action: Action;
  payload?: unknown;
}

const MAX_BODY_BYTES = 65_536;

export function buildHuaweiHandler(dependencies: BuildHuaweiHandlerDependencies) {
  const logger = dependencies.logger ?? {
    info(entry: RequestLogEntry): void {
      process.stdout.write(`${JSON.stringify(entry)}\n`);
    }
  };

  return async function handle(event: HuaweiHttpEvent): Promise<HuaweiHttpResponse> {
    const startedAt = Date.now();
    const requestId = createRequestId();
    let route = 'unmatched';
    let statusCode = 500;

    try {
      const parsedBody = parseBody(event);
      const request = resolveRequest(event.path, parsedBody);
      route = request.action;

      if (request.action === 'health') {
        statusCode = 200;
        return jsonResponse(statusCode, { status: 'ok' });
      }

      const authorization = readHeader(event.headers, 'authorization');
      if (!hasExpectedBearerToken(authorization, dependencies.config.APP_ACCESS_TOKEN)) {
        throw new UnauthorizedError();
      }

      if (request.action === 'analyze') {
        const input = AnalyzeRequestSchema.parse(request.payload);
        const result = input.answers === undefined ?
          await dependencies.service.analyze({ originalText: input.originalText }) :
          await dependencies.service.analyze({ originalText: input.originalText, answers: input.answers });
        statusCode = 200;
        return jsonResponse(statusCode, result);
      }

      const input = ReviseRequestSchema.parse(request.payload);
      const recipe = await dependencies.service.revise(input);
      statusCode = 200;
      return jsonResponse(statusCode, { kind: 'recipe' as const, recipe });
    } catch (error) {
      const mapped = mapError(error);
      statusCode = mapped.statusCode;
      return jsonResponse(statusCode, mapped.body);
    } finally {
      logger.info({
        requestId,
        route,
        statusCode,
        latencyMs: Date.now() - startedAt
      });
    }
  };
}

function parseBody(event: HuaweiHttpEvent): unknown {
  if (event.body === undefined || event.body === null || event.body === '') {
    return {};
  }

  if (typeof event.body === 'object') {
    const serialized = JSON.stringify(event.body);
    assertBodySize(serialized);
    return event.body;
  }

  if (typeof event.body !== 'string') {
    throw new SyntaxError('Unsupported request body');
  }

  const decoded = event.isBase64Encoded === true ?
    Buffer.from(event.body, 'base64').toString('utf8') : event.body;
  assertBodySize(decoded);
  try {
    return JSON.parse(decoded) as unknown;
  } catch {
    throw invalidRequestError();
  }
}

function assertBodySize(body: string): void {
  if (Buffer.byteLength(body, 'utf8') > MAX_BODY_BYTES) {
    const error = new Error('Request body too large') as Error & { code?: string };
    error.code = 'FST_ERR_CTP_BODY_TOO_LARGE';
    throw error;
  }
}

function resolveRequest(pathValue: unknown, body: unknown): ActionEnvelope {
  if (isRecord(body) && isAction(body.action)) {
    return { action: body.action, payload: body.payload };
  }

  const path = typeof pathValue === 'string' ? pathValue : '';
  if (path.endsWith('/health')) {
    return { action: 'health' };
  }
  if (path.endsWith('/recipes/analyze')) {
    return { action: 'analyze', payload: body };
  }
  if (path.endsWith('/recipes/revise')) {
    return { action: 'revise', payload: body };
  }

  throw invalidRequestError();
}

function isAction(value: unknown): value is Action {
  return value === 'health' || value === 'analyze' || value === 'revise';
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function readHeader(headersValue: unknown, expectedName: string): string | undefined {
  if (!isRecord(headersValue)) {
    return undefined;
  }
  const entry = Object.entries(headersValue)
    .find(([name]) => name.toLowerCase() === expectedName.toLowerCase());
  return typeof entry?.[1] === 'string' ? entry[1] : undefined;
}

function jsonResponse(statusCode: number, body: unknown): HuaweiHttpResponse {
  return {
    statusCode,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store'
    },
    isBase64Encoded: false,
    body: JSON.stringify(body)
  };
}

function createRequestId(): string {
  return `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
}

function invalidRequestError(): Error {
  const error = new Error('Invalid request') as Error & { code?: string };
  error.code = 'FST_ERR_CTP_INVALID_JSON_BODY';
  return error;
}
