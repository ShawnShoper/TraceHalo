# Contributing to TraceHalo / 参与 TraceHalo

[English](#english) · [简体中文](#简体中文)

## English

Issues and focused pull requests are welcome.

When reporting a problem, include:

- Mac model and macOS version
- Affected page or menu bar module
- Whether the value is missing, incorrect, or causes a crash
- Reproduction steps and a screenshot when useful

Remove serial numbers, network addresses, personal file paths, and other private information before posting logs or reports.

Before sending a pull request:

1. Keep the change focused and avoid unrelated formatting rewrites.
2. Add or update tests for changed behavior.
3. Run `TRACEHALO_SAFE_TEST_MODE=1 swift test --disable-sandbox`.
4. Confirm that tests do not remove files, change startup items, or modify system settings.
5. Update both English and Simplified Chinese user-facing text when applicable.

See [DEVELOPMENT.md](DEVELOPMENT.md) for build instructions.

## 简体中文

欢迎提交 Issue 和范围明确的 Pull Request。

反馈问题时请提供：

- Mac 型号和 macOS 版本
- 出现问题的页面或菜单栏模块
- 数据是缺失、错误，还是导致程序崩溃
- 复现步骤，必要时附上截图

发布日志或报告前，请移除序列号、网络地址、个人文件路径和其他隐私信息。

提交 Pull Request 前：

1. 保持改动范围明确，不要夹带无关的格式化修改。
2. 为行为变化新增或更新测试。
3. 运行 `TRACEHALO_SAFE_TEST_MODE=1 swift test --disable-sandbox`。
4. 确认测试不会删除文件、修改启动项或改变系统设置。
5. 涉及用户文案时，同时更新英文和简体中文。

构建说明请查看 [DEVELOPMENT.md](DEVELOPMENT.md)。
