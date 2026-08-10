# TraceHalo 发布、安装与校验

## 当前状态

TraceHalo 已取得 `Developer ID Application: Hao Xie (4DXU5FSLLY)` 证书，证书与私钥仅保存在维护者本机钥匙串，不进入仓库。本机 Apple 公证使用的 `notarytool` Keychain profile 已通过 Apple 服务验证；其他发布机器仍需自行配置。缺少 profile 时，正式发布命令会失败关闭（fail closed），不会降级生成可对外发布的 ad-hoc 包。

正式 Release 的固定要求是：

- 主程序与内嵌 helper 均使用 Developer ID、Hardened Runtime 和 Apple 时间戳签名；
- 主程序与 helper 均为 Universal 2，包含 `arm64` 和 `x86_64`；
- Apple 公证状态必须为 `Accepted`，并完成 ticket staple 与 Gatekeeper 验收；
- 同一构建输出 DMG、TAR.GZ、ZIP、每个文件各自的 `.sha256`，以及 `release-manifest.txt`；
- 任一签名、架构、公证、staple、Gatekeeper 或校验步骤失败，整次正式发布失败。

当前 `0.1.0` Beta build 2 的正式产物名为：

```text
TraceHalo-v000.001.000-Beta-build2-macOS-universal2-arm64-x86_64-developer-id-notarized.dmg
TraceHalo-v000.001.000-Beta-build2-macOS-universal2-arm64-x86_64-developer-id-notarized.tar.gz
TraceHalo-v000.001.000-Beta-build2-macOS-universal2-arm64-x86_64-developer-id-notarized.zip
```

`.dmg` 是面向普通用户的首选安装包；`.tar.gz` 和 `.zip` 提供相同已签名、已公证并已装订 ticket 的 App，适合不同下载或自动化环境。

## 用户下载与安装

TraceHalo 需要 macOS 14 或更高版本。

1. 从 [GitHub Releases](https://github.com/ShawnShoper/TraceHalo/releases) 下载最新 DMG，以及与它同名的 `.sha256`。
2. 在下载目录验证 SHA-256：

   ```sh
   shasum -a 256 -c TraceHalo-*.dmg.sha256
   ```

3. 打开 DMG，把 `TraceHalo.app` 拖入“应用程序”。
4. 从“应用程序”正常启动 TraceHalo。

如需使用 TAR.GZ 或 ZIP，也必须同时下载并验证对应的 `.sha256`：

```sh
for checksum in TraceHalo-*.sha256; do
    shasum -a 256 -c "$checksum"
done
```

正式 Release 已通过 Developer ID 与 Apple 公证，不需要关闭 Gatekeeper，也不应要求执行 `xattr -cr`。如果正式包仍显示“Apple 无法验证”，不要绕过系统安全提示；先确认文件来自官方 Releases、SHA-256 一致，并向项目提交问题。

## 发布机器一次性配置

### 1. 检查 Developer ID 身份

```sh
security find-identity -v -p codesigning
```

输出必须包含可用的：

```text
Developer ID Application: Hao Xie (4DXU5FSLLY)
```

只有 `.cer` 而没有对应私钥不能签名。证书与私钥不得提交到 Git、放入发布包或发送给其他人。

### 2. 配置公证 profile

默认 profile 名称是 `tracehalo-notary`。使用 Apple ID 与 Team ID 配置时，不要把 app-specific password 写进命令或脚本；省略 `--password` 后，`notarytool` 会通过安全输入提示读取它：

```sh
xcrun notarytool store-credentials tracehalo-notary \
    --apple-id "<Apple Developer Apple ID>" \
    --team-id "4DXU5FSLLY"
```

也可使用 App Store Connect API key；私钥文件必须存放在仓库外。保存后验证 profile 能访问 Apple 公证服务：

```sh
xcrun notarytool history --keychain-profile tracehalo-notary
```

发布前先执行上述验证命令；只有它能返回历史记录或完成提交，才可运行正式 `make release`。

## 正式发布

在干净工作树和正确版本元数据上执行：

```sh
make test
make release
```

`make release` 固定传入以下正式发布契约：

- `TRACEHALO_RELEASE_MODE=developer-id`
- `TRACEHALO_RELEASE_ARCH=universal`
- `TRACEHALO_NOTARIZE=1`
- `TRACEHALO_STRICT_SIGNING=1`
- `TRACEHALO_SIGNING_IDENTITY="Developer ID Application: Hao Xie (4DXU5FSLLY)"`
- `TRACEHALO_TEAM_ID=4DXU5FSLLY`
- `TRACEHALO_NOTARY_PROFILE=tracehalo-notary`

需要在另一支合法团队或另一个 profile 上发布时，应显式覆盖 Make 变量：

```sh
make release \
    TRACEHALO_SIGNING_IDENTITY="Developer ID Application: <Name> (<Team ID>)" \
    TRACEHALO_TEAM_ID="<Team ID>" \
    TRACEHALO_NOTARY_PROFILE="<profile>"
```

正式命令不会在缺少证书、公证凭据或 Apple 拒绝构建时回退到 ad-hoc。只有脚本完整输出三种产物、三份校验文件、`release-manifest.txt`，并且所有验证均通过，才可上传到 GitHub Releases。

## 本地 ad-hoc 包

无需 Developer ID 的本机测试入口继续保留：

```sh
make release-local
```

该目标固定使用 ad-hoc 签名、跳过公证，默认构建 `arm64`。如需调整本地架构：

```sh
make release-local TRACEHALO_LOCAL_RELEASE_ARCH=universal
```

文件名会明确包含 `adhoc`。这类包只用于维护者本机或受控测试，不得上传为正式 Release，不得描述为“已通过 Apple 验证”。

## 发布后复核

上传前至少复核：

```sh
codesign --verify --deep --strict --verbose=4 /Applications/TraceHalo.app
spctl --assess --type execute --verbose=4 /Applications/TraceHalo.app
xcrun stapler validate /Applications/TraceHalo.app
```

同时在 Apple silicon 与 Intel Mac 上各执行一次安装、首次启动、菜单栏显示、helper 加载和完整退出验证。SHA-256、Git Tag、Release 标题和应用内版本必须对应同一次构建，不能混用旧桌面 App 或旧 `.build` 产物。
