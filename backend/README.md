# Kitchen Master backend

## Local development

1. Copy `.env.example` to `.env` and edit the copy with your local values. Never commit `.env`.

   ```bash
   cp .env.example .env
   ```

   Keep `DEEPSEEK_API_KEY` only in this local environment file or in cloud-function environment variables. Do not place it in client code, request JSON, or shell commands/history.

2. Start the service:

   ```bash
   npm run dev
   ```

   `dotenv` reads `backend/.env` locally. In AppGallery Connect, configure the same values as function environment variables instead.

3. Verify the health endpoint:

   ```bash
   curl http://127.0.0.1:9000/api/v1/health
   ```

4. Save an analyze payload to a JSON file such as `analyze-request.json`:

   ```json
   {
     "originalText": "番茄炒蛋。"
   }
   ```

   Then enter the device token without echoing it or adding it to shell history, and send the authenticated request. The DeepSeek key is never sent to the application client.

   ```bash
   read -rs APP_ACCESS_TOKEN; printf '\n'
   curl --request POST http://127.0.0.1:9000/api/v1/recipes/analyze \
     --header "Authorization: Bearer $APP_ACCESS_TOKEN" \
     --header "Content-Type: application/json" \
     --data @analyze-request.json
   ```

## Huawei AppGallery Connect cloud-function deployment

1. Build the deployment archive:

   ```bash
   npm run package:agc
   ```

   This creates a small `kitchen-master-agc.zip` containing the bundled
   `index.handler` entry point. It never includes `.env` or the DeepSeek API key.

2. In AppGallery Connect, create one event function with these settings:

   - Name: `kitchen-master-ai`
   - Runtime: the newest supported Node.js runtime (Node.js 20 preferred)
   - Handler: `index.handler`
   - Memory: 500 MB
   - Timeout: 60 seconds

3. Upload `kitchen-master-agc.zip` and configure these environment variables:

   - `DEEPSEEK_API_KEY`
   - `DEEPSEEK_BASE_URL=https://api.deepseek.com`
   - `DEEPSEEK_MODEL=deepseek-v4-flash`

4. Add one HTTP trigger using `API client authentication (Client)` and POST.
   AppGallery Connect authenticates requests before invoking the function, so the
   AGC deployment does not duplicate the local server's bearer-token check.
   Keep decode disabled. HarmonyOS clients invoke the function by name through
   Cloud Foundation Kit; the relative trigger URL is not hard-coded in the app.

5. The single endpoint accepts an action envelope:

   ```json
   {
     "action": "analyze",
     "payload": {
       "originalText": "番茄炒蛋。"
     }
   }
   ```

   Supported actions are `health`, `analyze`, and `revise`.

## Legacy Tencent SCF Web Function deployment

1. Build the deployment archive:

   ```bash
   npm run package:scf
   ```

   This creates `kitchen-master-scf.zip` with the compiled server and production dependencies only.

2. In Tencent SCF, create a **Web Function** with these exact settings:

   - Runtime: Node.js 20.19
   - Memory: 256 MB
   - Timeout: 40 seconds
   - Maximum concurrency: 2
   - Timezone: `Asia/Shanghai`

3. Upload `kitchen-master-scf.zip`.

4. Configure these function environment variables:

   - `DEEPSEEK_API_KEY`
   - `APP_ACCESS_TOKEN`
   - `DEEPSEEK_BASE_URL`
   - `DEEPSEEK_MODEL`
   - `PORT=9000`

   For the current MVP, use `DEEPSEEK_MODEL=deepseek-v4-flash`. The older
   `deepseek-chat` and `deepseek-reasoner` aliases are no longer used by this project.

5. Create a public HTTPS Function URL. Public URL access does not replace application authentication: bearer authentication remains mandatory for analyze requests.

6. Verify the deployed health endpoint, then send an analyze request to the Function URL using the device token as the bearer token and a JSON request file. Do not expose `DEEPSEEK_API_KEY` to the client.
