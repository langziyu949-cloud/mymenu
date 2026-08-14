# AppGallery 发布前合规切换清单

正式代码不包含本地假登录分支，华为账号登录只能通过 Account Kit 官方组件完成。

发布前必须完成：

- 在 AGC 配置普通 Account Kit 华为账号登录所需的正式签名证书指纹和应用级 Client ID；个人开发者不申请“一键登录/获取手机号”。
- 在云函数配置 `HUAWEI_ACCOUNT_CLIENT_ID`、`HUAWEI_ACCOUNT_CLIENT_SECRET`、`IDENTITY_SESSION_SECRET`；客户端取得的 `authorizationCode` 由服务端换取用户级凭证并解析 OpenID/UnionID。Client Secret 禁止写入 App。
- AI 请求鉴权由云函数签发并校验短期登录会话；客户端会话保存在 Asset Store Kit，不保存华为 Access Token 或完整 OpenID/UnionID，仅保存“我的”页所需的显示名、头像地址和脱敏账号标识。
- 登录后由 Account Kit 请求 `profile` 用户授权以展示昵称头像；用户拒绝或资料不可用时，确认脱敏标识回退显示正常，不得阻断登录。
- 恢复并验证 `kitchen-master-ai` 云函数，确保正式包不返回本地假菜谱。
- 在应用中填入实际使用的模型名称、备案号或上线编号。
- 补齐可点击的《AI 服务规则》《隐私政策》页面及投诉举报入口。
- 用正式签名包验证：未登录不能调用 AI，华为账号授权码由服务端校验，登录成功后才可以调用。
- 提交《安全评估报告》、全国互联网安全管理服务平台审核通过截图、AI 标识截图和 APP 备案信息。

产品风险确认：

- 当前按产品决定，只在“我的 > AI 内容说明”集中披露 AI 生成内容，对话、记录页和菜谱卡片不再逐条显示显式标识。这种做法仍可能不满足 AppGallery 要求的“应用内已添加内容显式标识截图”，正式提交前应向审核人员确认；如未获得明确认可，应恢复生成内容旁的显式标识。

快速自检：

```bash
rg "REVIEW_DEMO_MODE|completeDemoHuaweiAccountVerification" entry/src/main/ets
```

命令有输出时，说明假登录代码被重新引入，禁止生成或提交正式上架包。
