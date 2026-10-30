# Tally

个人记账应用，同一仓库维护 Apple 与 HarmonyOS 原生客户端。

| 目录 | 平台 | 打开方式 |
| --- | --- | --- |
| `apple/` | iOS / macOS | Xcode 打开 `apple/CountMoney.xcodeproj` |
| `harmonyos/` | HarmonyOS | 先复制本地构建配置，再用 DevEco Studio 打开该目录 |

Apple 原有代码和项目文件整体移入 `apple/`，内部相对路径保持不变。
鸿蒙开发、构建和签名说明见 [harmonyos/README.md](harmonyos/README.md)。
Apple 功能说明见 [apple/README.md](apple/README.md)。

两个客户端支持 version 2 JSON 账本备份迁移。个人账本、备份、签名凭据和构建产物不提交到仓库；版本库中的 JSON 仅为应用必需资源配置。
