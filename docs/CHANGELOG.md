# Changelog

按时间倒序记录对本机用户可见、或协议层重要的变更。
未发布前用日期 + 主题归类；正式发版时可改成语义化版本号。

---

## 2026-07-18 — Session 管理

- 会话状态：`无 / 有效 / 可刷新 / 已过期`（JWT `exp` + refresh 判断）
- **清除会话**：删除本地 access/refresh/cookie，可选同时清记住的密码；Guard 保留
- **重新登录**：确认页账号行、账号详情均可进入登录 Sheet
- 过期会话不再计入「可处理确认」，需重新登录
- 详情页展示「登录会话」状态行与操作按钮

---

## 2026-07-18 — 现代 Session + 应用内登录（方法 B）

### 背景

精简版 SteamTools `accounts` JSON 通常只有 Guard 密钥（`shared_secret` / `identity_secret` 等），**没有** `Session`。
以前只能出 5 位验证码，不能向 Steam 拉交易确认。
本轮对齐 **WinAuth / SteamTools** 的现代登录态，并补上「在本 App 用密码登录换 Session」。

### 功能

1. **现代 Session 存储与确认请求**
   - Secrets 增加 `accessToken` / `refreshToken`
   - `hasMobileSession`：有 `steamLoginSecure` **或** `accessToken` 即可（不强制 `sessionid`）
   - 请求前解析 Cookie（`SteamMobileSession`）：
     - 无 `sessionid` → 本地生成 32 hex（同 WinAuth）
     - 有 token → 拼 `steamLoginSecure = steamId%7C%7CaccessToken（兼容导入的 || 形式）`
   - mobileconf 使用 `m=react`；Cookie 带 `mobileClient=android`
   - Access JWT 过期时调用
     `IAuthenticationService/GenerateAccessTokenForApp` 刷新并回写

2. **应用内 Steam 登录（方法 B）**
   - 新功能模块 `lib/features/auth_session/`
   - 协议：Steam Auth V2（protobuf + RSA 密码加密）
     - GetPasswordRSAPublicKey
     - BeginAuthSessionViaCredentials（platform = MobileApp）
     - UpdateAuthSessionWithSteamGuardCode（本机自动填 2FA）
     - PollAuthSessionStatus → access / refresh token
   - 成功后加密写入 Session；可选「记住密码」
   - 入口：
     - **确认**页账号状态行旁「登录」
     - **账号详情**「登录获取会话」

3. **导入**
   - 解析 WinAuth 风格 `Session`：`access_token` / `refresh_token` / `steamid`
   - 仅 AccessToken 时自动推导 `steamLoginSecure`

### 主要文件

| 路径 | 说明 |
|------|------|
| `lib/features/auth_session/` | 登录客户端、protobuf、登录服务、登录 Sheet |
| `lib/features/confirmations/domain/steam_mobile_session.dart` | Cookie / JWT 解析 |
| `lib/features/confirmations/data/http_steam_confirmations_client.dart` | mobileconf + token 刷新 |
| `lib/features/confirmations/data/steam_confirmations_repository.dart` | 就绪判定与请求前 Session 准备 |
| `lib/features/accounts/models/steam_account_secrets.dart` | tokens + `hasMobileSession` |
| `lib/app/app_services.dart` | `loginSteamSession` / prefill API |
| `pubspec.yaml` | 依赖 `pointycastle`（RSA） |

### 使用说明

1. 导入现有 Guard JSON（无需 Session）
2. 打开「确认」→ 账号旁点「登录」
3. 输入 Steam 密码 → 本机自动提交手机令牌码
4. 成功后账号变为可处理确认；列表可刷新

邮箱验证码会多一步手输；纯 Guard 设备码路径全自动。

### 风险与限制

- Steam 接口非官方，可能变更或限流（如 `X-eresult` 84）
- 浏览器端仍不支持确认/登录
- 密码默认不落盘；勾选「记住」后与 secrets 同加密仓存储
- 勿把真实 token/密码写进 git、Issue、日志

### 测试

- 相关单测：`test/features/auth_session/`、`steam_mobile_session_test`、parser / backup / confirmations client
- 本轮合入时全量 `flutter test` 通过（约 124 项）

---

## 更早（摘要，已在 git 历史）

- `020d57f` — 第六轮 review：mobileconf 协议、Face ID fail-closed、Android
- `504c9e1` — 确认页文案软化
- `33a1617` — SteamTools `accounts` map + `uuid_key` 导入
- 此前：maFile 导入、加密备份、Guard 出码、本地 AES-GCM 等
