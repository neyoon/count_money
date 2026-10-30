# Tally for HarmonyOS

ArkTS 原生客户端，包含支出、收入、转账、基金盈亏、分期还款、资产、总览、截图识别及 Apple version 2 备份导入导出。默认进入底部中央的记账页。

## 打开与构建

当前使用 DevEco Studio 26.0.0.851、SDK 26.0.0 和 bundled Hvigor 6.26.8。

首次打开工程前，在本目录执行：

```sh
cp build-profile.example.json5 build-profile.json5
```

用 DevEco Studio 打开 `harmonyos/`。`build-profile.json5` 是本机配置，已被 Git 忽略；示例配置不含签名凭据。
真机运行需要在 DevEco 的 Signing Configs 中登录自己的开发者账号、配置自动签名，并将 default product 关联到自己的签名配置。

macOS 命令行构建（未配置签名时生成 unsigned HAP）：

```sh
/Applications/DevEco-Studio.app/Contents/tools/node/bin/node scripts/build.mjs
```

脚本会在本地构建配置不存在时从示例生成。可通过 `DEVECO_HOME` 指定其他 DevEco 安装位置。

## 核心逻辑测试

```sh
/Applications/DevEco-Studio.app/Contents/tools/node/bin/node --test tests/ledger.test.mjs
```

没有个人备份时，私有备份测试自动跳过，其他测试使用合成数据。

## 数据与配置

- 私人 JSON、数据库、备份、证书和构建输出禁止提交。
- JSON 资源配置通过根目录 `.gitignore` 的具体路径白名单保留。
- 资产默认只读；设置中的初始化数据开关允许配置初始账户。
- 余额、转账方向、基金市值与还款规则对照 Apple 端实现。
- 构建和逻辑测试不能替代真机 UI、OCR、折叠状态及性能验证。
