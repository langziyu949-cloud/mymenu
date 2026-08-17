import type { AnalyzeRequest, AnalyzeResult, RecipeRevision, ReviseRequest } from '../domain/recipe.js';
import { createHash } from 'node:crypto';
import {
  AnalyzeRequestSchema,
  HuaweiAccountVerificationRequestSchema,
  ReviseRequestSchema
} from '../domain/schemas.js';
import { mapError, type RequestLogEntry } from '../http/buildServer.js';
import type { HuaweiAccountVerification } from '../services/huaweiAccountService.js';
import { HuaweiAccountVerificationError } from '../services/huaweiAccountService.js';
import type { IdentitySessionService } from '../services/identitySessionService.js';

interface RecipeServiceDependency {
  analyze(request: AnalyzeRequest): Promise<AnalyzeResult>;
  revise(request: ReviseRequest): Promise<RecipeRevision>;
}

interface HuaweiAccountServiceDependency {
  verifyAuthorizationCode(authorizationCode: string): Promise<HuaweiAccountVerification>;
}

type IdentitySessionDependency = Pick<IdentitySessionService, 'issue' | 'verify'>;

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
  service: RecipeServiceDependency;
  accountService?: HuaweiAccountServiceDependency;
  identitySessionService?: IdentitySessionDependency;
  logger?: { info(entry: RequestLogEntry): void };
}

type Action = 'health' | 'analyze' | 'revise' | 'verifyHuaweiAccount' | 'validateIdentity';

interface ActionEnvelope {
  action: Action;
  payload?: unknown;
  identityToken?: string;
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

      if (request.action === 'analyze') {
        requireIdentitySession(dependencies.identitySessionService, request.identityToken);
        const input = AnalyzeRequestSchema.parse(request.payload);
        const result = input.answers === undefined ?
          await dependencies.service.analyze({ originalText: input.originalText }) :
          await dependencies.service.analyze({ originalText: input.originalText, answers: input.answers });
        statusCode = 200;
        return jsonResponse(statusCode, result);
      }

      if (request.action === 'verifyHuaweiAccount') {
        if (dependencies.accountService === undefined || dependencies.identitySessionService === undefined) {
          throw new HuaweiAccountVerificationError();
        }
        const input = HuaweiAccountVerificationRequestSchema.parse(request.payload);
        const verification = await dependencies.accountService.verifyAuthorizationCode(input.authorizationCode);
        const loginAt = Date.now();
        const session = dependencies.identitySessionService.issue(
          hashAccountIdentifier(verification.unionID.length > 0 ? verification.unionID : verification.openID),
          {
            accountLabel: verification.accountLabel,
            displayName: verification.displayName,
            accountId: verification.accountId,
            avatarUrl: verification.avatarUrl,
            loginAt
          }
        );
        statusCode = 200;
        return jsonResponse(statusCode, {
          verified: true,
          accountLabel: verification.accountLabel,
          displayName: verification.displayName,
          accountId: verification.accountId,
          avatarUrl: verification.avatarUrl,
          loginAt,
          identityToken: session.identityToken,
          expiresAt: session.expiresAt
        });
      }

      if (request.action === 'validateIdentity') {
        const identity = requireIdentitySession(dependencies.identitySessionService, request.identityToken);
        statusCode = 200;
        return jsonResponse(statusCode, {
          verified: true,
          accountLabel: identity.accountLabel,
          displayName: identity.displayName,
          accountId: identity.accountId,
          avatarUrl: identity.avatarUrl,
          loginAt: identity.loginAt,
          expiresAt: identity.exp * 1000
        });
      }

      requireIdentitySession(dependencies.identitySessionService, request.identityToken);
      const input = ReviseRequestSchema.parse(request.payload);
      const revision = input.previousReplies === undefined ?
        await dependencies.service.revise({ currentRecipe: input.currentRecipe, instruction: input.instruction }) :
        await dependencies.service.revise({
          currentRecipe: input.currentRecipe,
          instruction: input.instruction,
          previousReplies: input.previousReplies
        });
      statusCode = 200;
      return jsonResponse(statusCode, { kind: 'recipe' as const, recipe: revision.recipe, reply: revision.reply });
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
    const resolved: ActionEnvelope = { action: body.action, payload: body.payload };
    if (typeof body.identityToken === 'string') {
      resolved.identityToken = body.identityToken;
    }
    return resolved;
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
  if (path.endsWith('/identity/huawei-account')) {
    return { action: 'verifyHuaweiAccount', payload: body };
  }

  throw invalidRequestError();
}

function isAction(value: unknown): value is Action {
  return value === 'health' || value === 'analyze' || value === 'revise' ||
    value === 'verifyHuaweiAccount' || value === 'validateIdentity';
}

function requireIdentitySession(
  sessionService: IdentitySessionDependency | undefined,
  token: string | undefined
): ReturnType<IdentitySessionDependency['verify']> {
  if (sessionService === undefined) {
    throw new HuaweiAccountVerificationError();
  }
  return sessionService.verify(token);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
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

function hashAccountIdentifier(identifier: string): string {
  return createHash('sha256').update(identifier, 'utf8').digest('base64url');
}

function invalidRequestError(): Error {
  const error = new Error('Invalid request') as Error & { code?: string };
  error.code = 'FST_ERR_CTP_INVALID_JSON_BODY';
  return error;
}
