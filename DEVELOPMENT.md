# TraceHalo Development Guide / 开发指南

[English](#english) · [简体中文](#简体中文)

## English

This document contains developer information intentionally kept out of the user-facing README.

### Requirements

- macOS 14 or later
- Xcode or a Swift toolchain compatible with Swift tools 6.2

### Build and run

For day-to-day macOS app development, open the native project:

```sh
open TraceHalo.xcodeproj
```

Select the **TraceHalo** scheme. In the TraceHalo target you can manage:

- **General**: app version (`0.2.0`), build number (`26`), deployment target, and app category.
- **Signing & Capabilities**: development team, automatic signing, hardened runtime, and future capabilities.
- **Build Settings**: bundle identifier (`com.tseai.tracehalo`) and advanced compiler settings.

The checked-in project currently selects Team `4DXU5FSLLY` for automatic signing. Contributors using another Apple Developer account should select their own team under **Signing & Capabilities**. Certificates, private keys, notarization credentials, and provisioning profiles are never stored in the repository; Xcode and Keychain manage them locally.

The privileged uninstall helper trusts Developer ID signatures from the checked-in team. A fork using a different team must update the client and helper signing requirements together and reverify the authorization and uninstall flows.

The maintainer machine has `Developer ID Application: Hao Xie (4DXU5FSLLY)` with its private key, and its local `tracehalo-notary` Keychain profile has been validated with Apple. The profile remains local to the release machine; having the certificate alone does not make a build notarized.

To create an Xcode archive, select **Any Mac** and choose **Product → Archive**. The Organizer can then export or upload the archive using the distribution certificate available to the selected Apple Developer team. An `Apple Development` signature is for local development and testing; public distribution still requires the appropriate distribution certificate and, outside the Mac App Store, Apple notarization.

When adding a Swift source file, add it to the matching Xcode target as well as the matching Swift Package source directory. The native project and `Package.swift` intentionally share the same source files.

The Swift Package workflow remains available for command-line builds and tests:

```sh
git clone https://github.com/ShawnShoper/TraceHalo.git
cd TraceHalo
swift build --disable-sandbox
swift run --disable-sandbox TraceHalo --safe-test-mode
```

Safe test mode rejects controlled system changes. Build a double-clickable local app with:

```sh
./scripts/build-app.sh
open .build/TraceHalo.app
```

### Test

```sh
TRACEHALO_SAFE_TEST_MODE=1 swift test --disable-sandbox
```

Test removal with disposable fixtures or test doubles. Keep installed apps, personal files, startup items, and system settings outside test scope. Generate the in-memory UI review screenshots with:

```sh
make snapshot-qa
```

### Version numbers

Public versions use a compact semantic tag:

```text
v0.0.1  first Beta
v0.0.2  next patch
v0.1.0  next feature milestone
v1.0.0  first major release
```

The source for `v0.2.0` uses Apple bundle version `0.2.0`, build `26`, and release channel `Beta`. `scripts/public-version.sh` formats versions for release files and tags. The public installer depends on passing the distribution checks below. [Upgrade notes in Simplified Chinese](docs/releases/v0.2.0.md)

### Release packaging

The default release target is the production, fail-closed path:

```sh
make release
```

It requires the configured Developer ID identity and `tracehalo-notary` profile, builds both `arm64` and `x86_64`, and uses two notarization stages. The app must be accepted, stapled, and Gatekeeper-verified before it enters any public archive; the resulting DMG is then signed, notarized, stapled, and verified separately. A successful run produces DMG, TAR.GZ, and ZIP files whose embedded app tickets validate independently, one `.sha256` file for each artifact, separate app/DMG notarization evidence, and `release-manifest.txt`. It must not fall back to ad-hoc signing when any production prerequisite is missing.

Use the separate local-only path when Developer ID or Apple notarization is intentionally not required:

```sh
make release-local
```

Use the output directory and its `release-manifest.txt` to identify the build. `Signing mode: adhoc` identifies a local test package. Ad-hoc and Apple Development builds can verify ordinary monitoring. Privileged uninstall requires the trusted team’s Developer ID signatures on both the app and helper. For protected apps, Finder remains available for manual removal. [Distribution guide](DISTRIBUTION.md)

### Project layout

```text
TraceHalo/
├── TraceHalo.xcodeproj/          Native macOS application project
├── Package.swift
├── Resources/                    App metadata, localization, and artwork
├── Sources/
│   ├── TraceHaloCore/          Models, collectors, formatting, and safety
│   ├── TraceHaloApp/           SwiftUI app and menu bar interface
│   ├── TraceHaloSensorHelper/  Optional read-only sensor helper
│   └── TraceHaloUninstallHelper/  Authorized removal of eligible apps
├── Tests/                        Core and in-memory UI tests
├── docs/images/                  README screenshots
└── scripts/                      App and release packaging
```

All package products, modules, executables, and Xcode targets use the TraceHalo name. Read-only legacy identifiers remain only where required to migrate settings from early development builds.

For packaging, signing, notarization, and verification, see [DISTRIBUTION.md](DISTRIBUTION.md).

## 简体中文

本文保存从普通用户 README 中移出的开发信息。

### 环境要求

- macOS 14 或更高版本
- Xcode，或兼容 Swift tools 6.2 的 Swift 工具链

### 构建和运行

日常开发 macOS App 时，直接打开原生工程：

```sh
open TraceHalo.xcodeproj
```

选择 **TraceHalo** Scheme。进入 TraceHalo Target 后可以直接管理：

- **General**：应用版本（`0.2.0`）、构建号（`26`）、最低系统版本和应用分类。
- **Signing & Capabilities**：开发团队、自动签名、Hardened Runtime，以及以后新增的能力。
- **Build Settings**：Bundle ID（`com.tseai.tracehalo`）和高级编译配置。

工程当前为自动签名选择了 Team `4DXU5FSLLY`。使用其他 Apple Developer 账号的贡献者，请在 **Signing & Capabilities** 中改为自己的 Team。仓库不会保存证书、私钥、公证凭据或描述文件，它们由本机 Xcode 与钥匙串管理。

卸载助手仅信任本仓库预设团队的 Developer ID 签名。使用其他签名团队的分支需要同步修改客户端和助手的签名信任配置，再复验授权和卸载流程。

维护者机器已经安装 `Developer ID Application: Hao Xie (4DXU5FSLLY)` 及其私钥，且本机 `tracehalo-notary` 钥匙串 profile 已通过 Apple 验证。该 profile 仅保存在发布机器；只有证书不代表构建已经通过 Apple 公证。

需要生成归档时，选择 **Any Mac**，然后执行 **Product → Archive**。之后可在 Organizer 中使用当前 Apple Developer Team 的发行证书导出或上传。`Apple Development` 签名仅适合本机开发和测试；公开分发仍需对应的发行证书，Mac App Store 以外的发行还需要完成 Apple 公证。

新增 Swift 源文件时，请同时将它加入对应的 Xcode Target，并放入对应的 Swift Package 源码目录。原生工程与 `Package.swift` 有意共用同一套源码。

Swift Package 的命令行构建和测试方式继续保留：

```sh
git clone https://github.com/ShawnShoper/TraceHalo.git
cd TraceHalo
swift build --disable-sandbox
swift run --disable-sandbox TraceHalo --safe-test-mode
```

安全测试模式会拒绝受控系统修改。生成可以双击打开的本地 App：

```sh
./scripts/build-app.sh
open .build/TraceHalo.app
```

### 测试

```sh
TRACEHALO_SAFE_TEST_MODE=1 swift test --disable-sandbox
```

卸载测试使用临时夹具或测试替身。测试范围限于测试数据，已安装应用、个人文件、启动项和系统设置需隔离。生成纯内存界面验收截图：

```sh
make snapshot-qa
```

### 版本号

公开版本使用简洁的语义化标签：

```text
v0.0.1  首个 Beta
v0.0.2  下一个修复版本
v0.1.0  下一个功能里程碑
v1.0.0  首个正式大版本
```

`v0.2.0` 源码的 Apple 应用版本为 `0.2.0`，构建号为 `26`，发行渠道为 `Beta`。`scripts/public-version.sh` 为安装包和 Git Tag 格式化公开版本号。公开安装包需通过下文的发行验证。[升级说明](docs/releases/v0.2.0.md)

### 发行包构建

默认发行目标是失败关闭的生产流程：

```sh
make release
```

它要求 Developer ID 身份和 `tracehalo-notary` profile 均可用，同时构建 `arm64` 与 `x86_64`，并执行两阶段公证。App 必须先公证 `Accepted`、装订 ticket 并通过 Gatekeeper，之后才能进入任何公开归档；生成的 DMG 再单独签名、公证、装订和验证。成功后会生成内部 App ticket 可独立验证的 DMG、TAR.GZ、ZIP、每个产物各自的 `.sha256`、App/DMG 两套公证证据，以及 `release-manifest.txt`；任何生产前置条件缺失时都不得降级为 ad-hoc。

无需 Developer ID 或 Apple 公证的本地测试必须使用独立入口：

```sh
make release-local
```

请通过产物所在目录和 `release-manifest.txt` 确认构建来源。`Signing mode: adhoc` 表示本地测试包。ad-hoc 和 Apple Development 签名可验证普通监控，特权卸载验收要求 App 与卸载助手都使用受信任团队的 Developer ID 签名。需要系统权限的应用也可在 Finder 中按提示手动移除。[分发指南](DISTRIBUTION.md)

### 项目结构

```text
TraceHalo/
├── TraceHalo.xcodeproj/          原生 macOS App 工程
├── Package.swift
├── Resources/                    应用信息、本地化资源和图标
├── Sources/
│   ├── TraceHaloCore/          模型、数据采集、格式化和安全边界
│   ├── TraceHaloApp/           SwiftUI 主程序和菜单栏界面
│   ├── TraceHaloSensorHelper/  可选的只读传感器服务
│   └── TraceHaloUninstallHelper/  为符合条件的应用提供授权卸载
├── Tests/                        Core 与纯内存界面测试
├── docs/images/                  README 界面截图
└── scripts/                      App 和发行包构建脚本
```

所有 Package 产品、模块、可执行文件和 Xcode Target 均统一使用 TraceHalo 命名。只有迁移早期开发版本设置所必需的只读旧标识会继续保留。

安装包构建、签名、公证和校验说明请查看 [DISTRIBUTION.md](DISTRIBUTION.md)。
