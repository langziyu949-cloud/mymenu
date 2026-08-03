# 厨房主理人 HarmonyOS Demo

这是“厨房主理人”的 HarmonyOS NEXT 本地 MVP，用于验证完整的菜谱记录闭环：

`与 AI 对话 → 整理并修订菜谱卡片 → 添加封面 → 收纳进菜谱夹 → 查看与维护`

## 当前能力

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

## AI 接入

- 当前版本通过项目内的 Node.js 后端调用 `deepseek-v4-flash`，支持首次整理、最多一轮澄清和对话式修改。
- DeepSeek API Key 仅保存在 `backend/.env` 或云函数环境变量中，不会写入 ArkTS 客户端或 HAP。
- 本地模拟器使用 HDC 反向端口连接 `http://127.0.0.1:9000`；明文访问仅对回环地址放行。
- 准备真机长期使用时，应把同一后端部署到腾讯云 HTTPS 地址，并替换客户端的调试地址和访问令牌。
- 调试 HAP 未配置发布签名，仅用于 DevEco Studio 模拟器或配置好调试签名的设备。

## 本地联调

在 `backend` 目录准备被 Git 忽略的 `.env`，至少配置：

```text
DEEPSEEK_API_KEY=你的本地密钥
APP_ACCESS_TOKEN=长度不少于16位的客户端访问令牌
DEEPSEEK_BASE_URL=https://api.deepseek.com
DEEPSEEK_MODEL=deepseek-v4-flash
PORT=9000
```

安装依赖并启动后端：

```bash
cd ../backend
npm install
npm run build
npm start
```

模拟器启动后建立反向端口，再运行应用：

```bash
hdc -t 127.0.0.1:5555 rport tcp:9000 tcp:9000
```

## 构建

项目使用 DevEco Studio 6.1.1 自带的 SDK、JBR 和 Hvigor：

```bash
DEVECO_SDK_HOME="/Applications/DevEco-Studio.app/Contents/sdk" \
JAVA_HOME="/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home" \
"/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw" \
  --mode module \
  -p product=default \
  -p module=entry@default \
  -p buildMode=debug \
  assembleHap
```
