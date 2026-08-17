import 'dotenv/config';
import { DeepSeekClient } from './ai/deepSeekClient.js';
import { loadDeepSeekConfig, loadHuaweiAccountConfig } from './config.js';
import {
  buildHuaweiHandler,
  type HuaweiHttpEvent,
  type HuaweiHttpResponse
} from './huawei/buildHuaweiHandler.js';
import { RecipeService } from './services/recipeService.js';
import { HuaweiAccountService } from './services/huaweiAccountService.js';
import { IdentitySessionService } from './services/identitySessionService.js';

type RuntimeHandler = (event: HuaweiHttpEvent) => Promise<HuaweiHttpResponse>;
type AgcCallback = (response: HuaweiHttpResponse) => void;

interface AgcLogger {
  error?(message: string): void;
}

let runtimeHandler: RuntimeHandler | undefined;
let recipeService: RecipeService | undefined;
let accountService: HuaweiAccountService | undefined;
let identitySessionService: IdentitySessionService | undefined;

function getRuntimeHandler(): RuntimeHandler {
  if (runtimeHandler === undefined) {
    runtimeHandler = buildHuaweiHandler({
      service: {
        analyze: request => getRecipeService().analyze(request),
        revise: request => getRecipeService().revise(request)
      },
      accountService: {
        verifyAuthorizationCode: code => getAccountService().verifyAuthorizationCode(code)
      },
      identitySessionService: {
        issue: (subject, profile) => getIdentitySessionService().issue(subject, profile),
        verify: token => getIdentitySessionService().verify(token)
      }
    });
  }
  return runtimeHandler;
}

function getAccountService(): HuaweiAccountService {
  if (accountService === undefined) {
    const config = loadHuaweiAccountConfig();
    accountService = new HuaweiAccountService({
      clientId: config.HUAWEI_ACCOUNT_CLIENT_ID,
      clientSecret: config.HUAWEI_ACCOUNT_CLIENT_SECRET
    });
  }
  return accountService;
}

function getIdentitySessionService(): IdentitySessionService {
  if (identitySessionService === undefined) {
    const config = loadHuaweiAccountConfig();
    identitySessionService = new IdentitySessionService(config.IDENTITY_SESSION_SECRET);
  }
  return identitySessionService;
}

function getRecipeService(): RecipeService {
  if (recipeService === undefined) {
    const config = loadDeepSeekConfig();
    const client = new DeepSeekClient(config);
    recipeService = new RecipeService(client);
  }
  return recipeService;
}

// AGC WiseFunction completes Node.js invocations through the callback argument.
// Returning only a Promise leaves the console test waiting until the platform
// reports a generic 140500 error.
export function handler(
  event: HuaweiHttpEvent,
  _context: unknown,
  callback: AgcCallback,
  logger?: AgcLogger
): void {
  void Promise.resolve()
    .then(() => getRuntimeHandler()(event))
    .then(response => callback(response))
    .catch(() => {
      logger?.error?.('Kitchen Master handler failed before producing a response.');
      callback({
        statusCode: 500,
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Cache-Control': 'no-store'
        },
        isBase64Encoded: false,
        body: JSON.stringify({
          error: {
            code: 'INTERNAL_ERROR',
            message: '服务暂时不可用，请稍后重试。'
          }
        })
      });
    });
}
