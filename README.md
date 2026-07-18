<p align="center">
  <img src="assets/branding/app-icon-light-1024.png" width="128" alt="Steam Account Companion icon">
</p>

# Steam Account Companion

[![CI](https://github.com/yukaroman/Steam-Account-Companion/actions/workflows/ci.yml/badge.svg)](https://github.com/yukaroman/Steam-Account-Companion/actions/workflows/ci.yml)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.44.6-54C5F8.svg)](.fvmrc)

一个面向**个人使用、本地优先**的 Flutter Steam 账号辅助工具，当前处于
**Alpha / 实验阶段**（`0.1.0`）。

核心场景：多账号 Steam Guard 验证码、本地加密存储、导入/备份，以及实验性的
登录会话与 mobile 确认。**不是** Steam 客户端，也不包含加速、下载、挂卡等能力。

> [!WARNING]
> 本项目会处理 `shared_secret`、`identity_secret`、登录会话（Cookie / JWT）、
> 恢复码和可选的 Steam 密码。项目**尚未经过独立安全审计**；导入真实账号前请阅读
> [SECURITY.md](SECURITY.md)，自行评估风险，并保留可用的恢复方式（如恢复码、
> Steam 官方令牌）。

## 非官方声明

Steam Account Companion 是非官方第三方项目，与 Valve Corporation 或 Steam
不存在隶属、赞助、授权或认可关系。Steam 及 Steam 标志是 Valve Corporation
在美国和/或其他国家的商标或注册商标。

本项目调用的 Steam Guard、QueryTime、Auth V2 登录与 mobile confirmations 属于
非公开或可能变化的协议行为，**随时可能失效或被限流**。

## 当前能力

| 能力 | 状态 |
| --- | --- |
| Steam Guard 五位验证码 + Steam QueryTime 校时 | 可用 |
| maFile / SteamTools JSON / 粘贴导入 | 可用 |
| Keychain / Keystore 主密钥 + 账号文件持久化 | 可用 |
| AES-256-GCM 本地加密（AAD 绑定账号 ID） | 默认开启，可在设置中明确关闭 |
| 加密 `.sacbak` 备份导出与合并恢复 | 可用 |
| 账号详情、密钥显式确认后查看、账号删除 | 可用 |
| Face ID / 指纹 / 系统身份验证门禁 | 可选，默认关闭 |
| 深色 / 浅色 / 跟随系统 / OLED 黑色 | 可用并持久化 |
| 现代 Session（access / refresh JWT、Cookie 派生） | 实验性 |
| 应用内密码登录换 Session（本机自动填 Guard） | 实验性 |
| Session 状态（无 / 有效 / 可刷新 / 已过期）、清除与重登 | 实验性 |
| 登录 / 交易 / 市场 mobileconf 确认 | 实验性，需要有效 Session |
| 后台多任务快照隐私遮罩 | 尚未实现 |

### 平台说明

- **iOS / macOS / Android**：令牌、导入、备份、加密存储为主路径；确认与登录依赖原生网络，面向这些平台。
- **Web**：受 Steam Community CORS 限制，**无法**使用 mobileconf 与应用内登录；可用于 UI 浏览与部分本地能力验证。

### 典型使用路径（Guard 精简导出）

许多 SteamTools 导出只有 Guard 密钥、没有 Session。可按下面流程获得确认能力：

1. 从「令牌」页导入 maFile 或 JSON（无需先有 Session）
2. 打开「确认」→ 账号旁点「登录」，或从账号详情进入
3. 输入 Steam **账号名**（不要用昵称）与密码；本机自动提交手机令牌码
4. 成功后可拉取并处理确认；会话过期时可清除后重新登录

邮箱验证码路径需额外手输；协议细节见 [docs/CHANGELOG.md](docs/CHANGELOG.md)。

## 数据与网络

- 账号载荷默认写在系统 Application Support 目录，并以 **AES-256-GCM** 封装；
  主密钥通过 `flutter_secure_storage` 使用平台安全存储。
- 用户可在设置中**明确关闭**本地加密；关闭后账号载荷可能以可读 JSON 落盘
  （含 secrets）。Face ID 与加密开关相互独立。
- 可选「记住密码」时，密码与 secrets 一并进入本地仓；默认不记住。
- **没有**自建账号系统、分析或遥测；不会把数据上传到本项目服务器。
- 会直连 Valve/Steam 的能力包括：QueryTime、Auth V2 登录、token 刷新、mobileconf。

完整说明见 [PRIVACY.md](PRIVACY.md) 和 [SECURITY.md](SECURITY.md)。

## 环境要求

- Flutter `3.44.6`（见 [.fvmrc](.fvmrc)；`pubspec.yaml` 声明最低 `>=3.27.0`）
- Dart `3.12.x`（与上述 Flutter 配套）
- iOS / macOS：Xcode 15 或更高
- Android：Android SDK
- Android 构建：JDK 17

Apple 插件使用 Flutter **Swift Package Manager** 集成，一般**不需要** `pod install`。

## 本地运行

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

仓库已包含 `ios/`、`android/`、`macos/`、`web/` 工程。iOS 真机签名请用本机配置，
不要把 Team ID 写进会提交的工程文件：

```bash
cp ios/Flutter/Local.xcconfig.example ios/Flutter/Local.xcconfig
# 编辑 Local.xcconfig 中的 DEVELOPMENT_TEAM（该文件已被 gitignore）
```

生产入口**不会**写入演示账号；首次启动请从令牌页导入。
**不要**把真实 maFile、`.sacbak`、Cookie、Token、验证码或密码提交到 GitHub
Issue、PR、日志或测试夹具。

CI 在 push / PR 上跑 `flutter analyze` 与 `flutter test`（见 `.github/workflows/ci.yml`）。

## 本地安装包

iOS 真机测试：

```bash
flutter run --release -d <device-id>
```

Android 本地测试包：

```bash
flutter build apk --release
```

没有 `android/key.properties` 时，Release APK 会使用本机 Debug key 签名，适合个人侧载，
**不能作为应用商店正式签名**。准备发布到商店时，复制
[`android/key.properties.example`](android/key.properties.example) 并配置自己的私有
keystore；真实文件和 keystore 已被 Git 忽略。

完整发布流程见 [docs/RELEASING.md](docs/RELEASING.md)。

## 开发状态与限制

- 版本 `0.1.0`：API、本地数据格式和界面都可能变化。
- **Guard 出码、导入、加密存储、备份**相对成熟；**登录 Session 与 mobileconf**
  仍属实验层，依赖非公开协议，不能保证长期兼容。
- 应用内登录与确认已有单测，但真机 / 真实账号端到端验收因平台与账号风险未全部完成。
- 这是个人工具，不是多用户密码库，也**不提供**账号或密钥的恢复保证。

| 文档 | 内容 |
| --- | --- |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 分层与边界 |
| [docs/CHANGELOG.md](docs/CHANGELOG.md) | 近期功能说明（Session / 登录等） |
| [docs/THREAT_MODEL.md](docs/THREAT_MODEL.md) | 精简威胁模型与已知限制 |
| [docs/RELEASING.md](docs/RELEASING.md) | iOS / Android 打包与发布检查 |
| [CODE_REVIEW.md](CODE_REVIEW.md) | 历史审查与修复记录 |
| [PROJECT_SPEC.md](PROJECT_SPEC.md) | 产品范围与安全边界 |
| [CONTRIBUTING.md](CONTRIBUTING.md) | 贡献约定 |

## 贡献与安全问题

功能建议与普通缺陷可用 GitHub Issue；提交前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。

**安全问题**请使用 GitHub 私密漏洞报告，不要在公开 Issue 中附带真实账号材料。
详情见 [SECURITY.md](SECURITY.md)。

## 许可证与来源

本项目以 [GNU General Public License v3.0](LICENSE) 发布。
App 内「设置 → 开源许可」也会显示本项目及依赖项许可证。

Steam 协议实现与测试向量曾参考或交叉验证 SteamTools、WinAuth 与 SteamAuth。
第三方来源、许可证与商标说明见 [NOTICE.md](NOTICE.md)。
