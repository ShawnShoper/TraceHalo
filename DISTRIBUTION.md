# TraceHalo 安装与校验说明

如果压缩包文件名包含 `-adhoc`，其中的 TraceHalo 使用 ad-hoc 签名，适用于
当前尚未取得 Apple Developer ID 证书的测试分发。它不是 Apple 公证发行包，
macOS 仍可能显示“Apple 无法验证是否包含可能危害 Mac 安全的恶意软件”等
Gatekeeper 提示。这属于当前签名级别的已知限制，不能通过重新压缩或 ad-hoc
签名消除。

只有文件名包含 `-developer-id-notarized`、签名验证通过并且 Apple 公证票据
有效的包，才属于 Apple 公证发行包。

请只接收来自你信任的发送者的安装包，并先核对同目录 `.sha256` 文件中的
SHA-256：

```sh
shasum -a 256 TraceHalo-*.zip
```

输出的校验值应与 `.sha256` 文件第一列完全一致。

## 安装

1. 解压 ZIP，将 `TraceHalo.app` 拖入“应用程序”目录。
2. 第一次启动时，在 Finder 中右键点按 `TraceHalo.app`，选择“打开”。
3. 确认应用来源可信后，在系统对话框中再次选择“打开”。
4. 如果没有出现可继续打开的按钮，进入“系统设置 → 隐私与安全性”，找到
   被阻止的 TraceHalo，选择“仍要打开”，再按系统要求完成确认。

不同 macOS 版本的文字可能略有不同。不要关闭系统安全机制，也不要执行来源
不明的终端命令来移除所有文件的隔离属性。

安装成功后，TraceHalo 的菜单栏监控会在主窗口关闭后继续运行。“彻底退出
TraceHalo”才会结束后台采样。

## 正式发行说明

取得 `Developer ID Application` 证书后，维护者应改用 Developer ID 签名、
Hardened Runtime、Apple 公证和票据装订。只有完成该流程并通过 Gatekeeper
验收的产物，才应对外描述为“已通过 Apple 验证”。
