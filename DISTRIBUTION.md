# TraceHalo 发布、安装与校验

## 当前状态

`v0.2.0 Beta`（build 26）已完成本机安装验证，源码待合并。公开安装包需完成下列发行验证后发布，Apple 公证和上传仍待完成。[升级说明](docs/releases/v0.2.0.md)

TraceHalo 已取得 `Developer ID Application: Hao Xie (4DXU5FSLLY)` 证书，证书与私钥仅保存在维护者本机钥匙串，不进入仓库。本机 Apple 公证使用的 `notarytool` Keychain profile 已通过 Apple 服务验证；其他发布机器仍需自行配置。缺少 profile 时，正式发布命令会失败关闭（fail closed），不会降级生成可对外发布的 ad-hoc 包。

正式 Release 的固定要求是：

- 主程序与内嵌 helper 均使用 Developer ID、Hardened Runtime 和 Apple 时间戳签名；
- 主程序与 helper 均为 Universal 2，包含 `arm64` 和 `x86_64`；
- App 与 DMG 分别提交 Apple 公证且状态都必须为 `Accepted`；App 必须在进入任何发行容器前完成 ticket staple，DMG 随后独立完成 staple；
- 同一构建输出 DMG、TAR.GZ、ZIP、每个文件各自的 `.sha256`，以及 `release-manifest.txt`；
- 任一签名、架构、公证、staple、Gatekeeper 或校验步骤失败，整次正式发布失败。

通过正式发行验证后，`v0.2.0 Beta` 的产物将使用以下名称：

```text
TraceHalo-0.2.0-arm64-x86_64.dmg
TraceHalo-0.2.0-arm64-x86_64.tar.gz
TraceHalo-0.2.0-arm64-x86_64.zip
```

`.dmg` 是面向普通用户的首选安装包，盘内仅包含 `TraceHalo.app` 和 `Applications` 快捷入口。正式发行的 DMG、`.tar.gz` 和 `.zip` 均包含同一个已签名、已公证并独立装订 ticket 的 App。DMG 自身也具有独立公证票据。TAR.GZ 和 ZIP 另含安装说明。

## 用户下载与安装

TraceHalo 需要 macOS 14 或更高版本。

1. 选择已公开发布的版本，下载对应 DMG 和同名 `.sha256`。[GitHub Releases](https://github.com/ShawnShoper/TraceHalo/releases)
2. 在下载目录验证 SHA-256：

   ```sh
   shasum -a 256 -c TraceHalo-*.dmg.sha256
   ```

3. 如果已安装旧版，先用「彻底退出 TraceHalo」关闭旧版。打开 DMG，把 `TraceHalo.app` 拖入「应用程序」。
4. 从“应用程序”正常启动 TraceHalo。

如需使用 TAR.GZ 或 ZIP，也必须同时下载并验证对应的 `.sha256`：

```sh
for checksum in TraceHalo-*.sha256; do
    shasum -a 256 -c "$checksum"
done
```

正式 Release 仅在 Developer ID 签名、Apple 公证和 Gatekeeper 验证全部通过后发布。如果 macOS 显示「Apple 无法验证」，先确认文件来自官方 Releases、SHA-256 一致，并向项目提交问题。

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

正式流程采用两阶段公证：

1. 将签名后的 App 放入临时 ZIP，提交公证并等待 `Accepted`；
2. 给 App 装订并验证 ticket，执行签名与 Gatekeeper 复核；
3. 仅使用该已装订 App 创建并签名 DMG；
4. 对 DMG 单独提交公证、等待 `Accepted`，再装订并验证 DMG ticket；
5. 从同一个已装订 App 创建最终 ZIP 和 TAR.GZ；
6. 挂载 DMG、解压 ZIP/TAR，逐一验证内部 App 的签名、ticket、架构和 Gatekeeper 结果。

正式构建成功后，输出目录包含 `app-notarization-result.json` 和 `dmg-notarization-result.json`。取得 Apple 日志时，也会保存 `app-notarization-log.json` 与 `dmg-notarization-log.json`。`release-manifest.txt` 会记录两个 submission ID。

本仓库的卸载助手仅信任 Team `4DXU5FSLLY` 的 Developer ID 签名。使用其他团队的分支需要同步更新客户端与助手的签名信任配置，重新验证助手批准、管理员认证和卸载流程，才具备完整的发行能力。

同一团队可以使用另一个已验证的公证 profile：

```sh
make release \
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

每次打包在 `.build/dist/` 下生成独立目录。请通过对应的 `release-manifest.txt` 区分签名方式和公证状态，`Signing mode: adhoc` 与 `Notarized: 0` 表示本地测试包。正式发行必须通过前述验证。

ad-hoc 和 Apple Development 签名可用于普通监控测试。特权卸载验收需要主程序和卸载助手均由预设团队使用 Developer ID 签名。需要权限的应用也可在 Finder 中按 macOS 提示手动移除。

## 发布后复核

上传前至少复核：

```sh
codesign --verify --deep --strict --verbose=4 /Applications/TraceHalo.app
spctl --assess --type execute --verbose=4 /Applications/TraceHalo.app
xcrun stapler validate /Applications/TraceHalo.app
```

同时在 Apple silicon 与 Intel Mac 上各执行一次安装、首次启动、菜单栏显示、helper 加载和完整退出验证。SHA-256、Git Tag、Release 标题和应用内版本必须对应同一次构建，不能混用旧桌面 App 或旧 `.build` 产物。
