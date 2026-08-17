# 厨房主理人（Kitchen Master）

厨房主理人是一套面向 HarmonyOS NEXT 的 AI 菜谱记录应用。用户可以用自然语言描述做菜过程，由 AI 整理成结构化菜谱，并继续通过对话修改；菜谱最终保存在设备本地，可添加封面、搜索、编辑和删除。

仓库同时包含：

- HarmonyOS NEXT 客户端（ArkTS / ArkUI）。
- TypeScript 后端与本地 Fastify 服务。
- 华为 AppGallery Connect 云函数入口与打包脚本。
- DeepSeek 菜谱整理与修订逻辑。
- 华为 Account Kit 登录、服务端账号校验和短期业务会话。
- 自动化测试、AppGallery 素材及当前构建包。

## 系统结构

```text
HarmonyOS 客户端
  ├─ ArkData：菜谱和草稿的本地持久化
  ├─ Asset Store Kit：短期登录会话
  ├─ Account Kit：华为账号授权码
  └─ Cloud Foundation Kit
         │
         ▼
AppGallery Connect 云函数：kitchen-master-ai
  ├─ 校验华为账号授权码并签发业务会话
  ├─ analyze：把自然语言整理为结构化菜谱
  ├─ revise：根据对话修改菜谱
  └─ DeepSeek API
```

本地开发时也可以使用 Fastify HTTP 服务调用相同的领域逻辑。生产客户端默认通过 Cloud Foundation Kit 按函数名调用云函数，不在 App 中保存固定服务地址、DeepSeek 密钥或华为 Client Secret。

## 目录说明

| 路径 | 内容 |
| --- | --- |
| `backend/` | TypeScript 后端、Fastify 本地服务、AGC/SCF 入口、测试和打包脚本 |
| `harmonyos/` | HarmonyOS NEXT 客户端工程 |
| `harmonyos/store-assets/` | AppGallery 展示图片及源图 |
| `harmonyos/dist/` | 当前调试、测试和签名构建包；正式发布前建议重新构建 |
| `docs/superpowers/` | 产品设计、后端、客户端和集成实施文档 |
| `material/` | 项目素材文件 |

更详细的模块文档：

- [后端开发与部署](backend/README.md)
- [HarmonyOS 客户端说明](harmonyos/README.md)
- [华为账号登录配置](harmonyos/HUAWEI_ACCOUNT_SETUP.md)
- [AppGallery 发布合规清单](harmonyos/RELEASE_COMPLIANCE_CHECKLIST.md)

## 开发环境

- Git。
- Node.js `>=20.19 <25`，推荐使用 Node.js 22 LTS。
- npm（依赖版本由 `backend/package-lock.json` 锁定）。
- DevEco Studio 6.1.1。
- HarmonyOS SDK 6.1.0（API 23）。
- 可访问的 DeepSeek API 账号。
- 如需部署和真机登录：华为开发者账号及对应的 AppGallery Connect 项目。

## 后端本地启动

```bash
cd backend
npm ci
cp .env.example .env
```

编辑 `backend/.env`，填入本机或测试环境的值：

```dotenv
DEEPSEEK_API_KEY=你的DeepSeek密钥
APP_ACCESS_TOKEN=本地HTTP接口使用的随机令牌
DEEPSEEK_BASE_URL=https://api.deepseek.com
DEEPSEEK_MODEL=deepseek-v4-flash
HUAWEI_ACCOUNT_CLIENT_ID=华为OAuth客户端ID
HUAWEI_ACCOUNT_CLIENT_SECRET=仅服务端保存的客户端密钥
IDENTITY_SESSION_SECRET=至少32位的随机字符串
PORT=9000
```

不要提交 `.env`，不要把密钥放进 ArkTS 客户端、命令历史、Issue 或聊天记录。

启动和验证：

```bash
npm run dev
curl http://127.0.0.1:9000/api/v1/health
```

提交或部署前运行：

```bash
npm test
npm run typecheck
npm run build
```

## 部署 AppGallery Connect 云函数

1. 安装依赖并生成部署包：

   ```bash
   cd backend
   npm ci
   npm run package:agc
   ```

2. 在 AppGallery Connect 中创建或更新事件函数：

   - 函数名：`kitchen-master-ai`
   - 入口：`index.handler`
   - 运行时：平台支持的最新 Node.js 20 运行时
   - 内存：500 MB
   - 超时：60 秒

3. 上传生成的 `backend/kitchen-master-agc.zip`。

4. 在云函数环境变量中配置：

   - `DEEPSEEK_API_KEY`
   - `DEEPSEEK_BASE_URL=https://api.deepseek.com`
   - `DEEPSEEK_MODEL=deepseek-v4-flash`
   - `HUAWEI_ACCOUNT_CLIENT_ID`
   - `HUAWEI_ACCOUNT_CLIENT_SECRET`
   - `IDENTITY_SESSION_SECRET`

5. 创建 POST HTTP 触发器，使用 API 客户端鉴权并关闭 decode。客户端仍通过 Cloud Foundation Kit 调用函数名，不要把密钥写入客户端。

6. 在控制台测试以下事件，确认返回 `statusCode: 200` 和 `{"status":"ok"}`：

   ```json
   {
     "body": "{\"action\":\"health\"}",
     "isBase64Encoded": false
   }
   ```

项目仍保留腾讯云 SCF Web Function 打包流程；如需使用，运行 `npm run package:scf` 并参照 [backend/README.md](backend/README.md) 配置。

## 构建 HarmonyOS 应用

1. 安装 DevEco Studio 6.1.1 和 HarmonyOS SDK 6.1.0（API 23）。
2. 在 DevEco Studio 中打开 `harmonyos/`，等待 ohpm/Hvigor 同步完成。
3. 确认 AppGallery Connect 中存在包名 `com.ziyu.kitchenmaster` 的应用。
4. 在新电脑上重新配置调试或发布签名；仓库不会保存私钥、证书口令或本机绝对路径。
5. 按 [华为账号登录配置](harmonyos/HUAWEI_ACCOUNT_SETUP.md) 配置 OAuth Client ID、正式证书指纹和云函数变量。
6. 在 DevEco Studio 中运行 `entry` 模块，或在 macOS 终端执行：

   ```bash
   DEVECO_SDK_HOME="/Applications/DevEco-Studio.app/Contents/sdk" \
   JAVA_HOME="/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home" \
   PATH="/Applications/DevEco-Studio.app/Contents/tools/node/bin:/usr/bin:/bin" \
   "/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw" \
     --no-daemon \
     --mode module \
     -p product=default \
     -p module=entry@default \
     -p buildMode=debug \
     assembleHap
   ```

正式发布前必须重新检查签名、账号登录、AI 内容标识、隐私政策、备案信息和安全评估材料，详见 [AppGallery 发布合规清单](harmonyos/RELEASE_COMPLIANCE_CHECKLIST.md)。

## 换电脑后的完整恢复

### 1. 旧电脑：单独迁移敏感文件

以下文件不会上传到 GitHub，必须使用加密 U 盘、加密磁盘映像或可信密码管理器单独迁移：

- `backend/.env`
- `~/Documents/kitchen-master-signing/` 中的发布签名材料
- `~/.ohos/config/` 中的 DevEco/HarmonyOS 调试签名材料
- 尚未导出的云平台环境变量和 Client Secret

不要使用普通未加密压缩包，不要把这些文件临时提交到 Git。

`node_modules/`、`backend/dist/`、部署 ZIP、DevEco 缓存和模拟器备份无需迁移，可以在新电脑重新生成。设备中的 ArkData 菜谱数据也不属于代码仓库；如需保留真实用户数据，应另行使用设备备份或应用提供的导出机制。

### 2. 新电脑：克隆仓库

```bash
git clone https://github.com/langziyu949-cloud/mymenu.git
cd mymenu
git status
```

仓库是私有的，新电脑需要先登录有权限的 GitHub 账号。也可以使用 GitHub CLI：

```bash
gh auth login -h github.com -p https -w
gh repo clone langziyu949-cloud/mymenu
cd mymenu
```

### 3. 恢复后端

```bash
cd backend
npm ci
cp .env.example .env
```

将加密备份中的变量安全地填回 `.env`，然后执行：

```bash
npm test
npm run typecheck
npm run build
npm run dev
```

不要直接复制旧电脑的 `node_modules`，应使用 `npm ci` 根据锁文件重新安装。

### 4. 恢复 HarmonyOS 工程

1. 安装相同或兼容版本的 DevEco Studio 与 SDK。
2. 打开 `harmonyos/` 并完成依赖同步。
3. 通过 DevEco Studio 重新导入或配置迁移过来的签名材料。
4. 检查 `harmonyos/build-profile.json5`，不要提交 DevEco 自动写入的证书口令和本机绝对路径。
5. 重新构建并在真机验证登录、云函数调用、菜谱保存和图片选择。

### 5. 恢复云端配置

GitHub 只保存代码，不保存 AppGallery Connect、DeepSeek 或腾讯云控制台中的密钥。换机后逐项确认：

- `kitchen-master-ai` 云函数仍存在且已部署正确版本。
- 六个服务端环境变量已经配置。
- 包名、OAuth Client ID、签名证书指纹与 AGC 应用一致。
- Cloud Foundation Kit、Account Kit 及所需权限仍处于启用状态。
- 线上健康检查、账号登录、`analyze` 和 `revise` 均正常。

## Git 与安全约定

- `main` 保存可恢复的完整项目版本。
- 功能开发使用独立分支并通过 Pull Request 合并。
- 禁止提交 `.env`、签名私钥、证书口令、云平台密钥和真实用户数据。
- 构建包可用于留档，但正式发布前应基于已审计源码重新签名和构建。
- 每次换机或大改前确认 `git status` 干净，并在 GitHub 上核对最新提交。
