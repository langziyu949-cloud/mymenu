# 厨房主理人 HarmonyOS Demo

这是“厨房主理人”的 HarmonyOS NEXT 本地 MVP，用于验证完整的菜谱记录闭环：

`与 AI 对话 → 整理并修订菜谱卡片 → 添加封面 → 收纳进菜谱夹 → 查看与维护`

## 当前能力

- 使用 B 案“主理人印章”作为分层应用图标和启动图。
- 启动即进入 AI 对话首页；底部导航为“菜谱 / + / 我的”。
- 支持用自然语言描述做法，在对话中生成和继续修订结构化菜谱卡片。
- 菜谱结构包含菜名、食材用量、调料用量、制作步骤、经验建议、照片和创建时间；菜名与步骤为必填项。
- 食材和调料可根据描述自动补全，无法确定的用量明确标注“AI 估算”；经验建议仅记录用户明确说出的内容。
- 完成卡片后再询问照片，可拍摄、从相册选择或跳过；照片仅作封面，不用于识别菜谱。
- 保存成功后，卡片以收缩动效收入左下角“菜谱”入口。
- 菜谱夹支持按菜名、食材、调料搜索，卡片可打开详情。
- 已保存菜谱支持直接编辑、更换照片和删除；误删可在 2 秒内撤销。
- 编辑器支持食材、调料、步骤和经验的实时增删、常用用量填充与长按拖动排序。
- 使用 ArkData relationalStore 本地保存菜谱和未完成草稿，应用重启后仍可恢复。
- “我的”页面展示本地存储、隐私说明、AI 服务状态和版本信息。
- AI 入口仅保留个人开发者可用的普通华为账号登录；Account Kit 授权码由云函数核验，登录会话保存在系统关键资产存储中，不获取手机号。

## AI 接入

- 当前版本通过华为 AppGallery Connect 云函数调用 `deepseek-v4-flash`，支持首次整理、最多一轮澄清和对话式修改。
- DeepSeek API Key 仅保存在 `backend/.env` 或云函数环境变量中，不会写入 ArkTS 客户端或 HAP。
- ArkTS 客户端通过 Cloud Foundation Kit 的 `cloudFunction.call()` 调用 `kitchen-master-ai`，由系统完成应用客户端鉴权，不保存固定服务地址或访问令牌。
- 项目包名和签名 Profile 必须与 AppGallery Connect 中的 `com.ziyu.kitchenmaster` 应用一致。

## 云函数配置

在 AppGallery Connect 的 `kitchen-master-ai` 函数中配置：

```text
DEEPSEEK_API_KEY=你的密钥
DEEPSEEK_BASE_URL=https://api.deepseek.com
DEEPSEEK_MODEL=deepseek-v4-flash
HUAWEI_ACCOUNT_CLIENT_ID=华为应用的OAuth客户端ID
HUAWEI_ACCOUNT_CLIENT_SECRET=华为应用的OAuth客户端密钥
IDENTITY_SESSION_SECRET=至少32位随机字符串
```

函数入口为 `index.handler`，HTTP 触发器使用 POST、API 客户端鉴权，并关闭 decode。重新生成上传包：

```bash
cd ../backend
npm run package:agc
```

## 构建

项目使用 DevEco Studio 6.1.1 自带的 SDK、JBR 和 Hvigor：

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
