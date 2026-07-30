# Kitchen Master Deployment and Mate X5 Integration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy the tested backend to Tencent Cloud, connect the HarmonyOS client without exposing secrets, install it directly on the Mate X5, and complete one end-to-end MVP acceptance pass.

**Architecture:** The device talks over HTTPS to a stateless Tencent SCF Web Function protected by a high-entropy application bearer token. The function alone holds the DeepSeek key. DevEco signs and installs a debug HAP directly on the user's device; AppGallery and Huawei internal testing are not required for this MVP.

**Tech Stack:** Tencent Cloud SCF Web Function, DeepSeek API, HTTPS Function URL, DevEco Studio 6.1.0, HarmonyOS SDK API 23, HDC, Mate X5.

## Preconditions

- Backend completion check passes and `backend/kitchen-master-scf.zip` exists.
- Harmony client completion check passes.
- User has a valid Tencent Cloud account and DeepSeek API key.
- DevEco Studio 6.1.0 and SDK API 23 are installed.
- Mate X5 is on HarmonyOS 6.1 with developer mode and USB debugging enabled.
- Secrets are entered only in local ignored files or Tencent environment-variable fields, never in chat or Git.

---

### Task 1: Create local secrets and verify DeepSeek through the backend

**Files:**
- Create locally: `backend/.env`
- Read: `backend/.env.example`

- [ ] **Step 1: Generate the app bearer token**

Run locally:

```bash
openssl rand -hex 32
```

Paste the result into `APP_ACCESS_TOKEN` in `backend/.env`. Do not paste it into issue trackers, chat, source code, or shell commands.

- [ ] **Step 2: Add the DeepSeek key locally**

Copy `backend/.env.example` to `backend/.env` and set:

```dotenv
DEEPSEEK_API_KEY=<user's key>
APP_ACCESS_TOKEN=<generated 64-hex-character token>
DEEPSEEK_BASE_URL=https://api.deepseek.com
DEEPSEEK_MODEL=deepseek-v4-flash
PORT=9000
```

Verify:

```bash
git check-ignore backend/.env
git status --short
```

Expected: `.env` is ignored and no secret-bearing file is staged.

- [ ] **Step 3: Run a real local analysis**

Start `npm run dev` from `backend/`. Put the bearer token only in a temporary local header file or environment variable and submit:

```json
{
  "originalText": "番茄牛腩：牛腩先焯水，番茄分两次放，加水小火炖一个半小时，最后用盐调味。"
}
```

Expected: HTTP 200 with either at most three justified questions or a valid `kind: "recipe"` response. If questions are returned, send exactly one second request with their answers and verify the result contains a non-empty name and steps.

- [ ] **Step 4: Inspect privacy-safe logs**

Confirm the server log contains request metadata but not `番茄牛腩`, the bearer token, or any part of the DeepSeek key.

---

### Task 2: Deploy the SCF Web Function

**Files:**
- Produce: `backend/kitchen-master-scf.zip`
- Update locally: Tencent SCF configuration

- [ ] **Step 1: Build the verified archive**

```bash
cd backend
npm run package:scf
unzip -l kitchen-master-scf.zip
```

Expected: archive has compiled server, production dependencies, lockfile, manifest, and executable `scf_bootstrap`; it has no `.env`, tests, or source maps containing secrets.

- [ ] **Step 2: Create the Tencent function**

In the Tencent Cloud console:

- create a **Web Function** named `kitchen-master-api`;
- region: the nearest mainland China region available to the user;
- runtime: Node.js 20.19;
- memory: 256 MB;
- timeout: 40 seconds;
- maximum instance concurrency: 2;
- timezone: `Asia/Shanghai`;
- upload `kitchen-master-scf.zip`.

- [ ] **Step 3: Set protected environment variables**

Enter the five values from local `.env` in the function environment-variable UI. Mark secrets as encrypted where Tencent offers the option. Do not create a recipe database or logging payload sink.

- [ ] **Step 4: Enable and verify the HTTPS URL**

Create a public HTTPS Function URL. The function still requires the application bearer token for both recipe endpoints.

Verify:

- `GET /api/v1/health` returns `{"status":"ok"}`;
- unauthenticated analyze returns 401;
- authenticated analyze returns 200;
- Tencent logs do not contain request bodies.

Record the HTTPS base URL locally; do not commit it together with the token.

---

### Task 3: Configure, sign, and install the HarmonyOS app

**Files:**
- Create locally: `harmonyos/entry/src/main/ets/config/LocalSecrets.ets`
- Update locally: DevEco signing profile

- [ ] **Step 1: Connect the client to SCF**

Copy `LocalSecrets.example.ets` to the ignored `LocalSecrets.ets` and set the deployed HTTPS base URL and the same `APP_ACCESS_TOKEN`.

Run:

```bash
git check-ignore harmonyos/entry/src/main/ets/config/LocalSecrets.ets
rg -n "DEEPSEEK_API_KEY|sk-" harmonyos backend/src
```

Expected: local secrets file is ignored; DeepSeek key patterns have zero matches in application/backend source.

- [ ] **Step 2: Prepare the Mate X5**

On the phone:

1. Enable developer mode.
2. Enable USB debugging.
3. Connect by a data-capable USB cable.
4. Accept the computer authorization prompt.

Verify:

```bash
hdc list targets
```

Expected: exactly the intended Mate X5 target is listed.

- [ ] **Step 3: Sign and install**

Use DevEco automatic debug signing for `com.ziyu.kitchenmaster`. Choose the connected Mate X5 and click Run, or build then install the generated debug HAP with HDC.

Expected: `厨房主理人` launches directly without AppGallery, internal testing, or a Huawei distribution fee.

- [ ] **Step 4: Confirm release-secret hygiene**

Before every shared HAP or source archive:

- confirm it is a debug/internal artifact;
- confirm `.env`, `LocalSecrets.ets`, signing passwords, and certificates are excluded;
- rotate `APP_ACCESS_TOKEN` if an artifact containing it leaves the user's control;
- never ship the DeepSeek key in the HAP.

---

### Task 4: Run end-to-end MVP acceptance

- [ ] **Step 1: Core happy path**

Record a recipe from conversation input, resolve or skip the single question round, edit the resulting card, decline a photo, and save. Verify one recipe appears after the 900 ms card-to-library motion.

- [ ] **Step 2: Cover-photo paths**

Save one recipe using camera and another using gallery. Disable network afterward and confirm both covers and all saved recipe details still open, proving the photos and recipes are local.

- [ ] **Step 3: Revision and data paths**

Verify local section edit, saved-card AI revision preview, search by name/ingredient/seasoning, five-second delete undo, permanent deletion, and photo cleanup.

- [ ] **Step 4: Failure and recovery paths**

Verify:

- offline analyze preserves the draft and offers retry;
- backend 503 preserves the draft;
- app kill restores the single draft;
- fold/unfold preserves content and layout;
- app kill after delete eventually finishes tombstone cleanup;
- reduced-motion system setting uses the short transition;
- `我的 → AI 服务状态` reflects health availability.

- [ ] **Step 5: Privacy and scope audit**

Confirm:

- conversation has no photo/microphone button;
- post-draft sheet says photos are only local covers and not recognition input;
- the HAP never calls DeepSeek directly;
- no photo bytes or URI appear in network capture;
- no login, sync, backup, export, family sharing, or motion toggle exists;
- uninstall warning accurately states that local recipes and photos will be removed.

- [ ] **Step 6: Record the accepted build**

Add a non-secret acceptance record at `docs/acceptance/2026-07-30-mate-x5.md` containing:

- Git commit SHA;
- backend function version identifier, not secrets;
- DevEco/SDK versions;
- phone OS version;
- checklist results and known non-blocking limitations.

Commit:

```bash
git add docs/acceptance/2026-07-30-mate-x5.md
git commit -m "test: record Mate X5 MVP acceptance"
```

---

## Integration Completion Check

The MVP is complete only when:

- the backend completion check passes;
- the Harmony client completion check passes;
- the deployed health and authenticated analyze endpoints succeed;
- a DevEco-signed debug HAP installs and runs on the Mate X5;
- all acceptance paths above are recorded;
- no DeepSeek key, bearer token, signing secret, recipe text log, or photo upload is present in Git or cloud logs.
