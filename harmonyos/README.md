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
- 已保存菜谱支持直接编辑、更换照片和删除；误删可在 5 秒内撤销。
- 使用 ArkData relationalStore 本地保存菜谱和未完成草稿，应用重启后仍可恢复。
- “我的”页面展示本地存储、隐私说明、AI 服务状态和版本信息。

## 演示限制

- 当前构建采用本地规则模拟 AI 整理与修改，尚未连接 DeepSeek，不会发送网络请求。
- 本地生成能力用于交互验收；接入后端后可替换为 DeepSeek 结构化生成，不影响现有页面与数据库。
- 调试 HAP 未配置发布签名，仅用于 DevEco Studio 模拟器或配置好调试签名的设备。

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
