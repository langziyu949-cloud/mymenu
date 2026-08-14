import { timingSafeEqual } from 'node:crypto';
import Fastify, { type FastifyInstance, type FastifyRequest } from 'fastify';
import { ZodError } from 'zod';
import {
  DeepSeekHttpError,
  DeepSeekRequestAbortedError,
  DeepSeekRequestError
} from '../ai/deepSeekClient.js';
import type { AppConfig } from '../config.js';
import type { AnalyzeRequest, AnalyzeResult, RecipeRevision, ReviseRequest } from '../domain/recipe.js';
import { AnalyzeRequestSchema, ReviseRequestSchema } from '../domain/schemas.js';
import { InvalidModelOutputError } from '../services/recipeService.js';
import { HuaweiAccountVerificationError } from '../services/huaweiAccountService.js';
import { IdentitySessionError } from '../services/identitySessionService.js';
import { createPublicError, type PublicError } from './errors.js';

interface RecipeServiceDependency {
  analyze(request: AnalyzeRequest): Promise<AnalyzeResult>;
  revise(request: ReviseRequest): Promise<RecipeRevision>;
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

export class UnauthorizedError extends Error {}

const invalidRequestFastifyErrorCodes = new Set([
  'FST_ERR_CTP_INVALID_MEDIA_TYPE',
  'FST_ERR_CTP_INVALID_CONTENT_LENGTH',
  'FST_ERR_CTP_EMPTY_JSON_BODY',
  'FST_ERR_CTP_INVALID_JSON_BODY'
]);

const bodyTooLargeFastifyErrorCode = 'FST_ERR_CTP_BODY_TOO_LARGE';

interface ErrorWithCode {
  code?: unknown;
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
    const revision = input.previousReplies === undefined ?
      await dependencies.service.revise({ currentRecipe: input.currentRecipe, instruction: input.instruction }) :
      await dependencies.service.revise({
        currentRecipe: input.currentRecipe,
        instruction: input.instruction,
        previousReplies: input.previousReplies
      });
    return { kind: 'recipe' as const, recipe: revision.recipe, reply: revision.reply };
  });

  return app;

  async function requireAuthorization(request: FastifyRequest): Promise<void> {
    if (!hasExpectedBearerToken(request.headers.authorization, dependencies.config.APP_ACCESS_TOKEN)) {
      throw new UnauthorizedError();
    }
  }
}

export function hasExpectedBearerToken(authorization: string | undefined, token: string): boolean {
  if (authorization === undefined) {
    return false;
  }

  const received = Buffer.from(authorization);
  const expected = Buffer.from(`Bearer ${token}`);
  return received.length === expected.length && timingSafeEqual(received, expected);
}

export function mapError(error: unknown): { statusCode: number; body: PublicError } {
  if (error instanceof UnauthorizedError) {
    return { statusCode: 401, body: createPublicError('UNAUTHORIZED') };
  }
  if (error instanceof ZodError || hasFastifyErrorCode(error, invalidRequestFastifyErrorCodes)) {
    return { statusCode: 400, body: createPublicError('INVALID_REQUEST') };
  }
  if (hasFastifyErrorCode(error, bodyTooLargeFastifyErrorCode)) {
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
  if (error instanceof IdentitySessionError) {
    return { statusCode: 401, body: createPublicError('IDENTITY_REQUIRED') };
  }
  if (error instanceof HuaweiAccountVerificationError) {
    return { statusCode: 503, body: createPublicError('ACCOUNT_AUTH_UNAVAILABLE') };
  }
  return { statusCode: 500, body: createPublicError('INTERNAL_ERROR') };
}

function hasFastifyErrorCode(error: unknown, expectedCode: string | Set<string>): boolean {
  if (typeof error !== 'object' || error === null) {
    return false;
  }
  const code = (error as ErrorWithCode).code;
  if (typeof code !== 'string') {
    return false;
  }
  return typeof expectedCode === 'string' ? code === expectedCode : expectedCode.has(code);
}
