# Count Money

个人记账软件设计与开发仓库。

当前文档：

- [产品与技术设计](docs/app-design.md)

运行方式：

- Mac 快速运行：`swift run CountMoney`
- iPhone 真机运行：用 Xcode 打开 `CountMoney.xcodeproj`，选择 `CountMoney` scheme，运行目标选你的 iPhone。
- 第一次真机运行前，在 Xcode 的 `Signing & Capabilities` 里选择你的 Team；Bundle ID 当前是 `com.guanxingjian.CountMoney`。

设计原则：

- 先保证数据不丢，再做同步和图表。
- 本地优先，离线可用。
- 支持 iPhone 记账，Mac 查看、录入和整理。
- 所有数据都应能导出、备份和恢复。
