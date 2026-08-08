# TraceHalo Development Guide / 开发指南

[English](#english) · [简体中文](#简体中文)

## English

This document contains developer information intentionally kept out of the user-facing README.

### Requirements

- macOS 14 or later
- Xcode or a Swift toolchain compatible with Swift tools 6.2

### Build and run

```sh
git clone https://github.com/ShawnShoper/TraceHalo.git
cd TraceHalo
swift build --disable-sandbox
swift run --disable-sandbox SystemScope --safe-test-mode
```

Safe test mode rejects controlled system changes. Build a double-clickable local app with:

```sh
./scripts/build-app.sh
open .build/TraceHalo.app
```

### Test

```sh
SYSTEMSCOPE_SAFE_TEST_MODE=1 swift test --disable-sandbox
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

Apple bundle metadata stores `v000.000.001` as `0.0.1`, with a separate build number. `scripts/public-version.sh` formats the public version used by release files and tags.

### Project layout

```text
TraceHalo/
├── Package.swift
├── Resources/                    App metadata, localization, and artwork
├── Sources/
│   ├── SystemScopeCore/          Models, collectors, formatting, and safety
│   ├── SystemScopeApp/           SwiftUI app and menu bar interface
│   └── SystemScopeSensorHelper/  Optional read-only sensor helper
├── Tests/                        Core and in-memory UI tests
├── docs/images/                  README screenshots
└── scripts/                      App and release packaging
```

`SystemScope` is the historical internal Swift module and executable name. The product, application bundle, and public repository use the name TraceHalo.

For packaging, signing, notarization, and verification, see [DISTRIBUTION.md](DISTRIBUTION.md).

## 简体中文

本文保存从普通用户 README 中移出的开发信息。

### 环境要求

- macOS 14 或更高版本
- Xcode，或兼容 Swift tools 6.2 的 Swift 工具链

### 构建和运行

```sh
git clone https://github.com/ShawnShoper/TraceHalo.git
cd TraceHalo
swift build --disable-sandbox
swift run --disable-sandbox SystemScope --safe-test-mode
```

安全测试模式会拒绝受控系统修改。生成可以双击打开的本地 App：

```sh
./scripts/build-app.sh
open .build/TraceHalo.app
```

### 测试

```sh
SYSTEMSCOPE_SAFE_TEST_MODE=1 swift test --disable-sandbox
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

Apple 应用内部将 `v000.000.001` 保存为 `0.0.1`，构建号单独记录。`scripts/public-version.sh` 会生成安装包和 Git Tag 使用的公开版本号。

### 项目结构

```text
TraceHalo/
├── Package.swift
├── Resources/                    应用信息、本地化资源和图标
├── Sources/
│   ├── SystemScopeCore/          模型、数据采集、格式化和安全边界
│   ├── SystemScopeApp/           SwiftUI 主程序和菜单栏界面
│   └── SystemScopeSensorHelper/  可选的只读传感器服务
├── Tests/                        Core 与纯内存界面测试
├── docs/images/                  README 界面截图
└── scripts/                      App 和发行包构建脚本
```

`SystemScope` 是项目早期保留的内部 Swift 模块与可执行文件名；产品、应用包和公开仓库统一使用 TraceHalo。

安装包构建、签名、公证和校验说明请查看 [DISTRIBUTION.md](DISTRIBUTION.md)。
