# 普通华为账号登录接入交接

当前 App 仅展示 Account Kit 官方“华为账号登录”按钮，不提供手机号输入、短信验证码或其他登录方式。
该方案使用个人开发者可用的普通华为账号登录，不申请企业专用的“一键登录/获取手机号”权限。

用户授权后，App 只把一次性 Authorization Code 发送给 `kitchen-master-ai` 云函数。云函数通过
华为账号 OAuth 接口换取用户级凭证、解析 OpenID/UnionID，并签发 7 天有效的应用业务会话。
华为 Access Token、Client Secret 和完整 OpenID/UnionID 均不写入 App 本地存储。App 只在
Asset Store Kit 中保存服务端签发的短期会话、显示名、头像地址和脱敏账号标识，用于“我的”页展示。

## 一、配置正式签名指纹与客户端信息

进入：`AppGallery Connect > 项目设置 > 常规 > 应用`，选择包名 `com.ziyu.kitchenmaster`。

1. 在“SHA256证书指纹”中添加并保存正式发布证书指纹：

   `2B:18:37:CB:37:2D:3F:C9:C9:2C:42:83:2B:B5:4E:3E:BE:33:A6:55:64:FE:CC:9D:93:D0:36:27:A5:E7:53:9F`

2. 记录应用级“OAuth 2.0客户端ID”中的 Client ID。
3. 复制对应 Client Secret。Client Secret 只能填入云函数环境变量，不要发到聊天、写进 App
   或提交到 Git。
4. 当前工程暂按 Client ID `6917612743137080356` 配置。如果 AGC 显示的应用级 Client ID 不同，
   只把 Client ID 发给开发人员并重新打包；不要发送 Client Secret。

App 会在普通登录成功后请求 `profile` scope 和 `serviceauthcode` permission，用于在“我的”页显示华为账号昵称/匿名账号
和头像。按照 Account Kit“申请账号权限”的范围说明，`profile` 不属于个人开发者不可申请的
一键登录、手机号或收货地址权限，无需申请企业专属的一键登录能力。用户拒绝资料授权或资料
接口暂不可用时，登录仍然有效，App 会回退显示“华为账号用户”和脱敏 OpenID。

原生 HarmonyOS 登录不使用 Web OAuth 回调，因此“华为账号服务”页面的 `redirect_uri` 保持为空。

## 二、部署云函数

进入：`开发与服务 > 云开发（Serverless）> 云函数 > kitchen-master-ai`。

在函数的“配置/环境变量”中增加或更新：

- `HUAWEI_ACCOUNT_CLIENT_ID`：上一步的应用级 OAuth Client ID
- `HUAWEI_ACCOUNT_CLIENT_SECRET`：对应 Client Secret
- `IDENTITY_SESSION_SECRET`：至少 32 位的独立随机字符串

可在本机终端运行 `openssl rand -base64 48` 生成 `IDENTITY_SESSION_SECRET`。只复制输出到环境变量，
不要写入代码或聊天。

上传 [kitchen-master-agc.zip](../backend/kitchen-master-agc.zip)，函数执行入口保持
`index.handler`，然后保存并部署。

部署后测试：

```json
{
  "body": "{\"action\":\"health\"}",
  "isBase64Encoded": false
}
```

预期返回 `statusCode: 200` 和 `{"status":"ok"}`。`analyze`、`revise` 必须携带 App 登录会话，
继续使用旧的控制台测试数据会返回 401，这是预期行为。

## 三、真机联调

1. 安装使用上述证书签名的新 App。
2. 进入“记录”，勾选协议，确认只显示“华为账号登录”。
3. 完成 Account Kit 授权，进入“我的”，确认显示昵称/匿名账号、头像（已开通 profile 时）、
   脱敏账号标识和登录时间，再发送一条菜谱内容。
4. 退出并重新打开 App，确认登录态能够恢复；七天后或令牌失效时要求重新登录。
5. 在“我的”点击“退出账号”，确认 App 清除本机会话并调用 Account Kit 取消本应用授权；
   再次登录时会重新发起授权。设备系统中已登录华为账号时，华为登录不会要求再次输入密码。

常见错误：

- `1001500001`：包名、Client ID 或签名证书指纹与 AGC 不一致。
- `1001502001`：设备尚未登录华为账号。
- `1001502005`：网络连接异常。
- `1001502012`：用户取消授权。
- 服务端登录失败：检查 Client ID、Client Secret 和云函数能否访问华为账号 OAuth 接口。

## 四、部署顺序

先配置指纹和环境变量，再部署新云函数，最后安装/发布新 App。新云函数会拒绝未登录的旧版本
AI 请求，不要在新 App 可用前单独替换线上函数。

普通华为账号登录只证明用户成功登录一个华为账号，不获取已验证手机号。如果应用审核仍要求
额外的手机号实名能力，应以华为审核/客服给出的书面结论为准，并将沟通记录随审核备注提交。
