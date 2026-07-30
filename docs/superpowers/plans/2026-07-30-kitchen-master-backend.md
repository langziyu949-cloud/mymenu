# Kitchen Master AI Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a stateless Tencent Cloud Function-compatible HTTP service that protects the DeepSeek key and turns Chinese cooking descriptions or revision instructions into validated recipe JSON.

**Architecture:** A Fastify server exposes analyze, revise, and health routes. A recipe service owns prompts, DeepSeek calls, one invalid-output retry, and Zod validation; the HTTP layer owns the 64 KB body limit, bearer-token authentication, and privacy-safe errors. The same server runs locally and as a Tencent SCF Web Function on Node.js 20.19.

**Tech Stack:** Node.js 20.19, TypeScript, Fastify, Zod, native `fetch`, Vitest, Tencent SCF Function URL, DeepSeek `deepseek-v4-flash`.

## Global Constraints

- The service never accepts or uploads photos.
- `DEEPSEEK_API_KEY` exists only in server environment variables.
- Default model is exactly `deepseek-v4-flash` with thinking disabled.
- JSON mode uses `response_format: { "type": "json_object" }`.
- Invalid, empty, or truncated model output is retried exactly once.
- Request bodies are limited to 64 KB.
- Logs never contain recipe text, bearer tokens, or the DeepSeek key.
- The service stores no recipes, drafts, chat messages, or user identity.
- Analyze returns at most three questions and only one question round is performed by the client.
- Recipe name and steps are required; ingredients, seasonings, and experience are optional.
- Photo fields are absent from every backend request and response; covers exist only on the device.
- AI-created amount estimates set `isAiEstimated` to `true`.
- Experience entries only come from user-provided text.

## File Map

- `backend/package.json` — scripts, runtime floor, and dependencies.
- `backend/package-lock.json` — reproducible dependency graph.
- `backend/tsconfig.json` — strict Node.js 20 TypeScript build.
- `backend/vitest.config.ts` — deterministic test configuration.
- `backend/.env.example` — non-secret configuration names.
- `backend/src/domain/recipe.ts` — all public recipe and API types.
- `backend/src/domain/schemas.ts` — Zod input/output validation.
- `backend/src/config.ts` — validated environment configuration.
- `backend/src/ai/prompts.ts` — exact analyze and revise prompts.
- `backend/src/ai/deepSeekClient.ts` — native-fetch DeepSeek adapter.
- `backend/src/services/recipeService.ts` — analyze/revise orchestration and retry.
- `backend/src/http/errors.ts` — stable public error payloads.
- `backend/src/http/buildServer.ts` — Fastify instance, authentication, and routes.
- `backend/src/server.ts` — local/SCF process entrypoint on port 9000.
- `backend/test/schemas.test.ts` — domain contract tests.
- `backend/test/prompts.test.ts` — prompt policy tests.
- `backend/test/deepSeekClient.test.ts` — outbound request tests.
- `backend/test/recipeService.test.ts` — retry and orchestration tests.
- `backend/test/http.test.ts` — route/auth/body-limit tests.
- `backend/scf_bootstrap` — SCF Web Function startup command.
- `backend/scripts/package-scf.sh` — reproducible deployment archive.
- `backend/README.md` — local run and Tencent deployment instructions.

---

### Task 1: Scaffold the backend and lock the API contract

**Files:**
- Create: `backend/package.json`
- Create: `backend/package-lock.json`
- Create: `backend/tsconfig.json`
- Create: `backend/vitest.config.ts`
- Create: `backend/.env.example`
- Create: `backend/src/domain/recipe.ts`
- Create: `backend/src/domain/schemas.ts`
- Create: `backend/test/schemas.test.ts`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `RecipeDraft`, `RecipeItem`, `AnalyzeRequest`, `AnalyzeResult`, `ReviseRequest`, `RecipeDraftSchema`, `AnalyzeRequestSchema`, and `ReviseRequestSchema`.
- Consumes: no earlier task interfaces.

- [ ] **Step 1: Add the backend manifest and strict compiler configuration**

Create `backend/package.json` with:

```json
{
  "name": "kitchen-master-backend",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "engines": {
    "node": ">=20.19 <25"
  },
  "scripts": {
    "dev": "tsx watch src/server.ts",
    "build": "tsc -p tsconfig.json",
    "start": "node dist/server.js",
    "test": "vitest run",
    "test:watch": "vitest",
    "typecheck": "tsc -p tsconfig.json --noEmit"
  },
  "dependencies": {
    "dotenv": "^17.0.0",
    "fastify": "^5.4.0",
    "zod": "^4.0.0"
  },
  "devDependencies": {
    "@types/node": "^20.19.0",
    "tsx": "^4.20.0",
    "typescript": "^5.8.0",
    "vitest": "^3.2.0"
  }
}
```

Create `backend/tsconfig.json` with `strict`, `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`, `NodeNext` modules, `ES2023` target, `src` root, and `dist` output. Create `backend/vitest.config.ts` with a Node environment and cleared mocks.

- [ ] **Step 2: Install dependencies and generate the lockfile**

Run:

```bash
cd backend
npm install
```

Expected: `backend/package-lock.json` exists and `npm audit` reports no unresolved critical vulnerability.

- [ ] **Step 3: Add non-secret environment documentation**

Create `backend/.env.example`:

```dotenv
DEEPSEEK_API_KEY=replace-locally
APP_ACCESS_TOKEN=replace-locally
DEEPSEEK_BASE_URL=https://api.deepseek.com
DEEPSEEK_MODEL=deepseek-v4-flash
PORT=9000
```

Append these entries to the repository `.gitignore`:

```gitignore
backend/.env
backend/dist/
backend/node_modules/
backend/kitchen-master-scf.zip
```

- [ ] **Step 4: Write the failing schema tests**

Create `backend/test/schemas.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { AnalyzeRequestSchema, RecipeDraftSchema, ReviseRequestSchema } from '../src/domain/schemas.js';

describe('RecipeDraftSchema', () => {
  it('accepts the smallest saveable recipe', () => {
    expect(RecipeDraftSchema.parse({
      name: '葱油鸡',
      ingredients: [],
      seasonings: [],
      steps: ['鸡蒸熟后淋上葱油。'],
      experience: []
    }).name).toBe('葱油鸡');
  });

  it('rejects a recipe without a name or steps', () => {
    expect(() => RecipeDraftSchema.parse({
      name: '',
      ingredients: [],
      seasonings: [],
      steps: [],
      experience: []
    })).toThrow();
  });

  it('preserves amount estimate provenance', () => {
    const recipe = RecipeDraftSchema.parse({
      name: '番茄牛腩',
      ingredients: [{ name: '牛腩', amount: '2斤', isAiEstimated: false }],
      seasonings: [{ name: '老抽', amount: '1勺', isAiEstimated: true }],
      steps: ['牛腩焯水后炖煮。'],
      experience: ['番茄分两次放。']
    });
    expect(recipe.seasonings[0]?.isAiEstimated).toBe(true);
  });
});

describe('request schemas', () => {
  it('accepts analyze text and optional answers', () => {
    expect(AnalyzeRequestSchema.parse({
      originalText: '今天做了番茄牛腩。',
      answers: [{ questionId: 'q1', answer: '老抽一勺。' }]
    }).answers).toHaveLength(1);
  });

  it('requires a revision instruction and current recipe', () => {
    expect(() => ReviseRequestSchema.parse({ instruction: '' })).toThrow();
  });
});
```

- [ ] **Step 5: Run the tests to verify they fail**

Run:

```bash
cd backend
npm test -- test/schemas.test.ts
```

Expected: FAIL because `src/domain/schemas.ts` does not exist.

- [ ] **Step 6: Implement the recipe types and schemas**

Create `backend/src/domain/recipe.ts` with these exact public shapes:

```ts
export interface RecipeItem {
  name: string;
  amount: string;
  isAiEstimated: boolean;
}

export interface RecipeDraft {
  name: string;
  ingredients: RecipeItem[];
  seasonings: RecipeItem[];
  steps: string[];
  experience: string[];
}

export interface ClarifyingAnswer {
  questionId: string;
  answer: string;
}

export interface ClarifyingQuestion {
  id: string;
  text: string;
  reason: 'missing_name' | 'missing_steps' | 'critical_item' | 'conflict';
}

export interface AnalyzeRequest {
  originalText: string;
  answers?: ClarifyingAnswer[];
}

export type AnalyzeResult =
  | { kind: 'questions'; questions: ClarifyingQuestion[] }
  | { kind: 'recipe'; recipe: RecipeDraft };

export interface ReviseRequest {
  currentRecipe: RecipeDraft;
  instruction: string;
}
```

Create `backend/src/domain/schemas.ts` using trimmed strings, minimum length 1 for name and each step, maximum three questions, maximum 20 ingredients, maximum 20 seasonings, maximum 30 steps, and maximum 20 experience entries. Export schemas matching every public interface.

- [ ] **Step 7: Run schema tests and typecheck**

Run:

```bash
cd backend
npm test -- test/schemas.test.ts
npm run typecheck
```

Expected: both commands PASS.

- [ ] **Step 8: Commit the contract**

```bash
git add .gitignore backend
git commit -m "feat(backend): define recipe API contract"
```

---

### Task 2: Implement configuration, prompts, and the DeepSeek adapter

**Files:**
- Create: `backend/src/config.ts`
- Create: `backend/src/ai/prompts.ts`
- Create: `backend/src/ai/deepSeekClient.ts`
- Create: `backend/test/prompts.test.ts`
- Create: `backend/test/deepSeekClient.test.ts`

**Interfaces:**
- Consumes: `AnalyzeRequest`, `RecipeDraft`, and `ReviseRequest`.
- Produces: `AppConfig`, `buildAnalyzeMessages()`, `buildReviseMessages()`, `ChatCompletionClient.complete(messages): Promise<string>`, and `DeepSeekClient`.

- [ ] **Step 1: Write prompt-policy tests**

Create `backend/test/prompts.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { buildAnalyzeMessages, buildReviseMessages } from '../src/ai/prompts.js';

describe('recipe prompts', () => {
  it('requires JSON and forbids invented experience', () => {
    const messages = buildAnalyzeMessages({ originalText: '放番茄炖牛腩。' });
    const text = messages.map((message) => message.content).join('\n');
    expect(text).toContain('JSON');
    expect(text).toContain('最多三个');
    expect(text).toContain('不得生成用户没有表达的经验建议');
    expect(text).toContain('放番茄炖牛腩。');
  });

  it('tells revision to preserve unrelated fields', () => {
    const messages = buildReviseMessages({
      currentRecipe: {
        name: '番茄牛腩',
        ingredients: [],
        seasonings: [],
        steps: ['炖煮。'],
        experience: []
      },
      instruction: '老抽改成半勺'
    });
    expect(messages.map((message) => message.content).join('\n'))
      .toContain('不得修改指令未涉及的字段');
  });
});
```

- [ ] **Step 2: Write the DeepSeek request test**

Create `backend/test/deepSeekClient.test.ts` with a fake `fetch` that records its URL and init. Assert:

```ts
expect(url).toBe('https://api.deepseek.com/chat/completions');
expect(body.model).toBe('deepseek-v4-flash');
expect(body.thinking).toEqual({ type: 'disabled' });
expect(body.response_format).toEqual({ type: 'json_object' });
expect(body.stream).toBe(false);
expect(init.headers.Authorization).toBe('Bearer test-deepseek-key');
```

Also assert that a non-2xx response throws `DeepSeekHttpError` without including response body or request text in the error message.

- [ ] **Step 3: Run the tests to verify they fail**

Run:

```bash
cd backend
npm test -- test/prompts.test.ts test/deepSeekClient.test.ts
```

Expected: FAIL because prompt and client modules do not exist.

- [ ] **Step 4: Implement validated configuration**

Create `backend/src/config.ts`:

```ts
import { z } from 'zod';

const EnvSchema = z.object({
  DEEPSEEK_API_KEY: z.string().min(1),
  APP_ACCESS_TOKEN: z.string().min(16),
  DEEPSEEK_BASE_URL: z.string().url().default('https://api.deepseek.com'),
  DEEPSEEK_MODEL: z.enum(['deepseek-v4-flash', 'deepseek-v4-pro'])
    .default('deepseek-v4-flash'),
  PORT: z.coerce.number().int().min(1).max(65535).default(9000)
});

export type AppConfig = z.infer<typeof EnvSchema>;

export function loadConfig(env: NodeJS.ProcessEnv = process.env): AppConfig {
  return EnvSchema.parse(env);
}
```

- [ ] **Step 5: Implement exact analyze and revise prompts**

Create `backend/src/ai/prompts.ts`. The analyze system prompt must state:

- Return one JSON object with either `kind: "questions"` or `kind: "recipe"`.
- Ask only for missing name, missing usable steps, critical unresolved item, or material conflict.
- Return at most three questions.
- When `answers` is present, return `kind: "recipe"` and never ask a second
  question round; use the original text plus non-empty answers to produce the
  safest complete draft.
- Infer ingredient/seasoning names from steps.
- Estimate amounts only when context supports an estimate and mark those
  amounts. Use `适量` only when it is semantically safe; otherwise ask during
  the first round or omit the optional item after a skipped answer.
- Leave optional lists empty when unsupported.
- Never generate experience not explicitly present in original text or answers.
- Questions use stable IDs `q1`, `q2`, and `q3`.

The revise prompt must include the entire current recipe JSON, the instruction, and the rule that unrelated fields remain byte-for-byte equivalent in meaning and order.

- [ ] **Step 6: Implement the native-fetch DeepSeek adapter**

Create `backend/src/ai/deepSeekClient.ts` with:

```ts
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
  }
}
```

`DeepSeekClient.complete()` sends a 30-second `AbortSignal.timeout(30_000)` request to `/chat/completions`, uses the configured model, disables thinking, sets JSON mode, sets `max_tokens` to 4096, and returns `choices[0].message.content`. It throws a privacy-safe error if the response is non-2xx, truncated, missing, or aborted.

- [ ] **Step 7: Run tests and typecheck**

Run:

```bash
cd backend
npm test -- test/prompts.test.ts test/deepSeekClient.test.ts
npm run typecheck
```

Expected: PASS.

- [ ] **Step 8: Commit the AI adapter**

```bash
git add backend
git commit -m "feat(backend): add DeepSeek JSON adapter"
```

---

### Task 3: Add recipe orchestration and one invalid-output retry

**Files:**
- Create: `backend/src/services/recipeService.ts`
- Create: `backend/test/recipeService.test.ts`

**Interfaces:**
- Consumes: `ChatCompletionClient`, prompt builders, and Zod result schemas.
- Produces: `RecipeService.analyze(request): Promise<AnalyzeResult>` and `RecipeService.revise(request): Promise<RecipeDraft>`.

- [ ] **Step 1: Write retry and policy tests**

Create `backend/test/recipeService.test.ts` with a queue-backed fake client:

```ts
class FakeClient {
  public calls = 0;
  constructor(private readonly responses: string[]) {}

  async complete(): Promise<string> {
    const response = this.responses[this.calls];
    this.calls += 1;
    return response ?? '';
  }
}
```

Add tests that prove:

- A valid `kind: "recipe"` response returns after one call.
- Empty content followed by valid content returns after two calls.
- Invalid JSON followed by valid content returns after two calls.
- Two invalid contents throw `InvalidModelOutputError`.
- Four returned questions are rejected and retried.
- `revise()` rejects a result with an empty name or steps.
- `revise()` accepts a valid recipe and returns it.

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
cd backend
npm test -- test/recipeService.test.ts
```

Expected: FAIL because `RecipeService` does not exist.

- [ ] **Step 3: Implement the service**

Create `backend/src/services/recipeService.ts` with:

```ts
export class InvalidModelOutputError extends Error {
  constructor() {
    super('Model returned invalid recipe JSON');
  }
}

export class RecipeService {
  constructor(private readonly client: ChatCompletionClient) {}

  async analyze(request: AnalyzeRequest): Promise<AnalyzeResult> {
    return this.completeWithRetry(
      buildAnalyzeMessages(request),
      (value) => AnalyzeResultSchema.parse(value)
    );
  }

  async revise(request: ReviseRequest): Promise<RecipeDraft> {
    return this.completeWithRetry(
      buildReviseMessages(request),
      (value) => RecipeDraftSchema.parse(value)
    );
  }
}
```

`completeWithRetry()` loops exactly twice, rejects blank strings before `JSON.parse`, applies the passed parser, and throws only `InvalidModelOutputError` after the second invalid result. DeepSeek HTTP errors pass through without automatic retry so the client can show an actionable network/service error.

- [ ] **Step 4: Run service tests and the whole suite**

Run:

```bash
cd backend
npm test -- test/recipeService.test.ts
npm test
npm run typecheck
```

Expected: all commands PASS.

- [ ] **Step 5: Commit orchestration**

```bash
git add backend
git commit -m "feat(backend): orchestrate recipe analysis and revision"
```

---

### Task 4: Expose authenticated HTTP routes

**Files:**
- Create: `backend/src/http/errors.ts`
- Create: `backend/src/http/buildServer.ts`
- Create: `backend/src/server.ts`
- Create: `backend/test/http.test.ts`

**Interfaces:**
- Consumes: `RecipeService`, request schemas, and `AppConfig`.
- Produces: `buildServer(dependencies): FastifyInstance` and the process entrypoint.

- [ ] **Step 1: Write route tests with a fake recipe service**

Create `backend/test/http.test.ts`. Use `FastifyInstance.inject()` and assert:

```ts
expect((await app.inject({ method: 'GET', url: '/api/v1/health' })).statusCode)
  .toBe(200);

expect((await app.inject({
  method: 'POST',
  url: '/api/v1/recipes/analyze',
  payload: { originalText: '番茄炒蛋。' }
})).statusCode).toBe(401);

expect((await app.inject({
  method: 'POST',
  url: '/api/v1/recipes/analyze',
  headers: { authorization: 'Bearer test-device-token-1234' },
  payload: { originalText: '番茄炒蛋。' }
})).statusCode).toBe(200);
```

Add cases for malformed payload `400`, wrong token `401`, invalid model output `502`, DeepSeek HTTP error `503`, and a payload larger than 64 KB `413`. Capture logger output and assert the original recipe text is absent.

- [ ] **Step 2: Run the route tests to verify they fail**

Run:

```bash
cd backend
npm test -- test/http.test.ts
```

Expected: FAIL because `buildServer` does not exist.

- [ ] **Step 3: Implement stable public errors**

Create `backend/src/http/errors.ts` with these codes:

```ts
export type PublicErrorCode =
  | 'INVALID_REQUEST'
  | 'UNAUTHORIZED'
  | 'PAYLOAD_TOO_LARGE'
  | 'AI_INVALID_RESPONSE'
  | 'AI_UNAVAILABLE'
  | 'INTERNAL_ERROR';

export interface PublicError {
  error: {
    code: PublicErrorCode;
    message: string;
    retryable: boolean;
  };
}
```

Messages must be generic Chinese copy and must not include exception messages from DeepSeek or user input.

- [ ] **Step 4: Implement the server builder**

Create `backend/src/http/buildServer.ts`:

- Construct Fastify with `bodyLimit: 65_536`.
- Expose unauthenticated `GET /api/v1/health` returning `{ status: "ok" }`.
- Require `Authorization: Bearer <APP_ACCESS_TOKEN>` for both recipe routes.
- Validate request bodies with Zod before calling the service.
- Return analyze results unchanged.
- Return revise results as `{ kind: "recipe", recipe }`.
- Map Zod errors to `400`, auth errors to `401`, oversized bodies to `413`, invalid model output to `502`, DeepSeek/abort errors to `503`, and unexpected errors to `500`.
- Log only request ID, route, response code, latency, and model usage counts when available.

- [ ] **Step 5: Implement the local and SCF entrypoint**

Create `backend/src/server.ts`:

```ts
import 'dotenv/config';
import { DeepSeekClient } from './ai/deepSeekClient.js';
import { loadConfig } from './config.js';
import { buildServer } from './http/buildServer.js';
import { RecipeService } from './services/recipeService.js';

const config = loadConfig();
const client = new DeepSeekClient(config);
const service = new RecipeService(client);
const server = buildServer({ config, service });

await server.listen({ host: '0.0.0.0', port: config.PORT });
```

- [ ] **Step 6: Run every backend verification**

Run:

```bash
cd backend
npm test
npm run typecheck
npm run build
```

Expected: all commands PASS and `backend/dist/server.js` exists.

- [ ] **Step 7: Commit the HTTP API**

```bash
git add backend
git commit -m "feat(backend): expose authenticated recipe API"
```

---

### Task 5: Package the Tencent SCF Web Function

**Files:**
- Create: `backend/scf_bootstrap`
- Create: `backend/scripts/package-scf.sh`
- Create: `backend/README.md`
- Modify: `backend/package.json`

**Interfaces:**
- Consumes: compiled `backend/dist/server.js` and production dependencies.
- Produces: `backend/kitchen-master-scf.zip` and exact Tencent console configuration.

- [ ] **Step 1: Add the SCF bootstrap**

Create executable `backend/scf_bootstrap`:

```bash
#!/bin/bash
exec /var/lang/node20/bin/node dist/server.js
```

The server already listens on `0.0.0.0:9000`, which is required by a Web Function.

- [ ] **Step 2: Add the deployment archive script**

Create executable `backend/scripts/package-scf.sh`:

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
npm ci
npm run test
npm run build
npm prune --omit=dev
zip -qr kitchen-master-scf.zip dist node_modules package.json package-lock.json scf_bootstrap
npm install
```

Add `"package:scf": "bash scripts/package-scf.sh"` to `package.json`.

- [ ] **Step 3: Write exact local and Tencent instructions**

Create `backend/README.md` documenting:

1. Copy `.env.example` to `.env` without committing it.
2. Run `npm run dev`; `dotenv` reads `backend/.env` for local development while
   Tencent SCF supplies the same values as function environment variables.
3. Verify health with `curl http://127.0.0.1:9000/api/v1/health`.
4. Send one authenticated analyze request with a JSON file, not shell history containing the DeepSeek key.
5. Run `npm run package:scf`.
6. Create a Tencent SCF Web Function using Node.js 20.19, 256 MB memory, 40-second timeout, maximum concurrency 2, and timezone `Asia/Shanghai`.
7. Upload `kitchen-master-scf.zip`.
8. Configure `DEEPSEEK_API_KEY`, `APP_ACCESS_TOKEN`, `DEEPSEEK_BASE_URL`, `DEEPSEEK_MODEL`, and `PORT=9000`.
9. Create a public HTTPS Function URL. Application bearer auth remains mandatory.
10. Verify health, then analyze with the device token.

- [ ] **Step 4: Verify packaging**

Run:

```bash
cd backend
npm run package:scf
unzip -l kitchen-master-scf.zip
```

Expected: tests pass; the archive contains `dist/server.js`, production `node_modules`, `package.json`, lockfile, and executable `scf_bootstrap`, and contains neither `.env` nor test files.

- [ ] **Step 5: Commit deployment support**

```bash
git add backend
git commit -m "ops(backend): package Tencent SCF function"
```

---

## Backend Completion Check

Run:

```bash
cd backend
npm ci
npm test
npm run typecheck
npm run build
npm run package:scf
```

Expected: every command exits 0. Inspect the archive and verify no `.env`, recipe fixture text beyond tests, or secret is included.
