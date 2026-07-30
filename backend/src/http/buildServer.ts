import { timingSafeEqual } from 'node:crypto';
import Fastify, { type FastifyInstance, type FastifyRequest } from 'fastify';
import { ZodError } from 'zod';
import {
  DeepSeekHttpError,
  DeepSeekRequestAbortedError,
  DeepSeekRequestError
} from '../ai/deepSeekClient.js';
import type { AppConfig } from '../config.js';
import type { AnalyzeRequest, AnalyzeResult, RecipeDraft, ReviseRequest } from '../domain/recipe.js';
import { AnalyzeRequestSchema, ReviseRequestSchema } from '../domain/schemas.js';
import { InvalidModelOutputError } from '../services/recipeService.js';
import { createPublicError, type PublicError, type PublicErrorCode } from './errors.js';

interface RecipeServiceDependency {
  analyze(request: AnalyzeRequest): Promise<AnalyzeResult>;
  revise(request: ReviseRequest): Promise<RecipeDraft>;
}

export interface RequestLogEntry {
  requestId: string;
  route: string;
  statusCode: number;
  latencyMs: number;
  modelUsage?: Record<string, number>;
}

export interface BuildServerDependencies {
  config: Pick<AppConfig, 'APP_ACCESS_TOKEN'>;
  service: RecipeServiceDependency;
  logger?: { info(entry: RequestLogEntry): void };
}

class UnauthorizedError extends Error {}

interface ErrorWithStatusCode {
  statusCode?: unknown;
}

export function buildServer(dependencies: BuildServerDependencies): FastifyInstance {
  const app = Fastify({ bodyLimit: 65_536, logger: false });
  const logger = dependencies.logger ?? {
    info(entry: RequestLogEntry): void {
      process.stdout.write(`${JSON.stringify(entry)}\n`);
    }
  };

  app.addHook('onResponse', (request, reply, done) => {
    logger.info({
      requestId: request.id,
      route: request.routeOptions.url ?? 'unmatched',
      statusCode: reply.statusCode,
      latencyMs: Math.round(reply.elapsedTime)
    });
    done();
  });

  app.setErrorHandler((error, _request, reply) => {
    const { statusCode, body } = mapError(error);
    reply.code(statusCode).send(body);
  });

  app.get('/api/v1/health', async () => ({ status: 'ok' }));

  app.post('/api/v1/recipes/analyze', { preHandler: requireAuthorization }, async (request) => {
    const input = AnalyzeRequestSchema.parse(request.body);
    if (input.answers === undefined) {
      return dependencies.service.analyze({ originalText: input.originalText });
    }
    return dependencies.service.analyze({ originalText: input.originalText, answers: input.answers });
  });

  app.post('/api/v1/recipes/revise', { preHandler: requireAuthorization }, async (request) => {
    const input = ReviseRequestSchema.parse(request.body);
    const recipe = await dependencies.service.revise(input);
    return { kind: 'recipe' as const, recipe };
  });

  return app;

  async function requireAuthorization(request: FastifyRequest): Promise<void> {
    if (!hasExpectedBearerToken(request.headers.authorization, dependencies.config.APP_ACCESS_TOKEN)) {
      throw new UnauthorizedError();
    }
  }
}

function hasExpectedBearerToken(authorization: string | undefined, token: string): boolean {
  if (authorization === undefined) {
    return false;
  }

  const received = Buffer.from(authorization);
  const expected = Buffer.from(`Bearer ${token}`);
  return received.length === expected.length && timingSafeEqual(received, expected);
}

function mapError(error: unknown): { statusCode: number; body: PublicError } {
  if (error instanceof UnauthorizedError) {
    return { statusCode: 401, body: createPublicError('UNAUTHORIZED') };
  }
  if (error instanceof ZodError || getStatusCode(error) === 400) {
    return { statusCode: 400, body: createPublicError('INVALID_REQUEST') };
  }
  if (getStatusCode(error) === 413) {
    return { statusCode: 413, body: createPublicError('PAYLOAD_TOO_LARGE') };
  }
  if (error instanceof InvalidModelOutputError) {
    return { statusCode: 502, body: createPublicError('AI_INVALID_RESPONSE') };
  }
  if (
    error instanceof DeepSeekHttpError ||
    error instanceof DeepSeekRequestAbortedError ||
    error instanceof DeepSeekRequestError
  ) {
    return { statusCode: 503, body: createPublicError('AI_UNAVAILABLE') };
  }
  return { statusCode: 500, body: createPublicError('INTERNAL_ERROR') };
}

function getStatusCode(error: unknown): number | undefined {
  if (typeof error !== 'object' || error === null) {
    return undefined;
  }
  const statusCode = (error as ErrorWithStatusCode).statusCode;
  return typeof statusCode === 'number' ? statusCode : undefined;
}
