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

- **General**: app version (`0.1.0`), build number (`2`), deployment target, and app category.
- **Signing & Capabilities**: development team, automatic signing, hardened runtime, and future capabilities.
- **Build Settings**: bundle identifier (`com.tseai.tracehalo`) and advanced compiler settings.

The checked-in project currently selects Team `4DXU5FSLLY` for automatic signing. Contributors using another Apple Developer account should select their own team under **Signing & Capabilities**. Certificates, private keys, notarization credentials, and provisioning profiles are never stored in the repository; Xcode and Keychain manage them locally.

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

Tests must not remove files, modify startup items, or change system settings. Generate the in-memory UI review screenshots with:

```sh
make snapshot-qa
```

### Version numbers

Public versions use a fixed-width format:

```text
v000.000.001  first Beta
v000.000.002  next patch
v000.001.000  next feature milestone
v001.000.000  first major release
```

The current Apple bundle metadata stores `v000.001.000` as `0.1.0`, with build number `2` and release channel `Beta`. `scripts/public-version.sh` formats the public version used by release files and tags.

### Release packaging

The default release target is the production, fail-closed path:

```sh
make release
```

It requires the configured Developer ID identity and `tracehalo-notary` profile, builds both `arm64` and `x86_64`, requires Apple notarization to return `Accepted`, staples and verifies the ticket, and runs Gatekeeper checks. A successful run produces DMG, TAR.GZ, and ZIP files, one `.sha256` file for each artifact, and `release-manifest.txt`. It must not fall back to ad-hoc signing when any production prerequisite is missing.

Use the separate local-only path when Developer ID or Apple notarization is intentionally not required:

```sh
make release-local
```

Its artifacts are explicitly marked `adhoc`, are not notarized, and must not be uploaded as a public Release. See [DISTRIBUTION.md](DISTRIBUTION.md) for one-time `notarytool` profile setup, release variables, and verification commands.

### Project layout

```text
TraceHalo/
├── TraceHalo.xcodeproj/          Native macOS application project
├── Package.swift
├── Resources/                    App metadata, localization, and artwork
├── Sources/
│   ├── TraceHaloCore/          Models, collectors, formatting, and safety
│   ├── TraceHaloApp/           SwiftUI app and menu bar interface
│   └── TraceHaloSensorHelper/  Optional read-only sensor helper
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

- **General**：应用版本（`0.1.0`）、构建号（`2`）、最低系统版本和应用分类。
- **Signing & Capabilities**：开发团队、自动签名、Hardened Runtime，以及以后新增的能力。
- **Build Settings**：Bundle ID（`com.tseai.tracehalo`）和高级编译配置。

工程当前为自动签名选择了 Team `4DXU5FSLLY`。使用其他 Apple Developer 账号的贡献者，请在 **Signing & Capabilities** 中改为自己的 Team。仓库不会保存证书、私钥、公证凭据或描述文件，它们由本机 Xcode 与钥匙串管理。

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

测试不得删除文件、修改启动项或改变系统设置。生成纯内存界面验收截图：

```sh
make snapshot-qa
```

### 版本号

公开版本使用固定宽度格式：

```text
v000.000.001  首个 Beta
v000.000.002  下一个修复版本
v000.001.000  下一个功能里程碑
v001.000.000  首个正式大版本
```

当前 Apple 应用内部将 `v000.001.000` 保存为 `0.1.0`，构建号为 `2`，发行渠道为 `Beta`。`scripts/public-version.sh` 会生成安装包和 Git Tag 使用的公开版本号。

### 发行包构建

默认发行目标是失败关闭的生产流程：

```sh
make release
```

它要求 Developer ID 身份和 `tracehalo-notary` profile 均可用，同时构建 `arm64` 与 `x86_64`，要求 Apple 公证返回 `Accepted`，完成 ticket 装订与验证，并执行 Gatekeeper 检查。成功后会生成 DMG、TAR.GZ、ZIP、每个产物各自的 `.sha256`，以及 `release-manifest.txt`；任何生产前置条件缺失时都不得降级为 ad-hoc。

无需 Developer ID 或 Apple 公证的本地测试必须使用独立入口：

```sh
make release-local
```

其产物会明确标记 `adhoc`，不经过公证，不得上传为公开 Release。`notarytool` profile 的一次性配置、发行变量和验证命令见 [DISTRIBUTION.md](DISTRIBUTION.md)。

### 项目结构

```text
TraceHalo/
├── TraceHalo.xcodeproj/          原生 macOS App 工程
├── Package.swift
├── Resources/                    应用信息、本地化资源和图标
├── Sources/
│   ├── TraceHaloCore/          模型、数据采集、格式化和安全边界
│   ├── TraceHaloApp/           SwiftUI 主程序和菜单栏界面
│   └── TraceHaloSensorHelper/  可选的只读传感器服务
├── Tests/                        Core 与纯内存界面测试
├── docs/images/                  README 界面截图
└── scripts/                      App 和发行包构建脚本
```

所有 Package 产品、模块、可执行文件和 Xcode Target 均统一使用 TraceHalo 命名。只有迁移早期开发版本设置所必需的只读旧标识会继续保留。

安装包构建、签名、公证和校验说明请查看 [DISTRIBUTION.md](DISTRIBUTION.md)。
