# Codex Usage Widget

一个运行在 macOS 上的 Codex 用量浮窗，可以显示在 Codex 旁边，持续查看账户用量。

English：[README.md](README.md)

![Codex Usage Widget 预览](assets/preview.png)

## 功能

- 显示 5 小时额度使用比例、重置时间和长周期额度。
- 显示数据更新时间，精确到秒。
- 正常更新间隔为 30 秒；更新失败后每 1 秒重试一次。
- 支持手动刷新、退出和历史图表。
- 历史图表支持 24 小时、7 天、30 天和全部数据筛选，也可以选择主周期、长周期或全部指标。
- 显示可用的“使用限额重置”次数，点击后查看每条重置额度的标题和到期时间。
- 支持选择自定义背景图片和调整图片透明度，原有深色主题会继续保留。
- 支持拖动面板贴近屏幕边缘后自动缩放为极简卡片，极简模式显示 5 小时和长周期额度；鼠标悬停时恢复完整面板。
- 设置面板可以关闭自动缩放，并设置等待 1–10 秒后缩放，默认开启、默认等待 2 秒。
- 菜单栏支持显示实时用量，格式为 `CODEX(5h:42%|1W:18%)`，默认开启。
- 使用 `assets/icon.png` 生成应用图标。
- 每次成功获取的数据都会追加保存到本地历史文件，更新 App 不会删除历史数据。

应用只读调用本机 `codex app-server`，不会读取、复制或保存登录凭据。

## 安装和启动

项目提供两种产物：

- `AppBundle/Codex Usage Widget.app`：应用本体。
- `AppBundle/Codex Usage Widget.dmg`：安装镜像。

可以双击 DMG，将 App 拖入应用程序目录，也可以直接打开 App：

```zsh
open "AppBundle/Codex Usage Widget.app"
```

## 构建

项目不依赖 Xcode 工程或第三方 Swift 包，使用项目根目录下的脚本构建：

```zsh
./build.zsh
```

构建脚本会完成以下工作：

1. 使用 `xcrun swiftc` 编译 Swift/AppKit 应用。
2. 从 `assets/icon.png` 生成多分辨率 `AppIcon.icns`。
3. 生成并签名 `.app` 应用包。
4. 生成 `AppBundle/Codex Usage Widget.dmg` 安装镜像。

最低支持 macOS 13.0。

## 数据和配置

历史数据保存位置：

```text
~/Library/Application Support/Codex Usage Widget/usage-history.jsonl
```

背景图片路径、图片透明度、自动缩放、缩放等待时间和菜单栏显示开关保存在当前用户的 `UserDefaults` 中。

默认 Codex 可执行文件路径为：

```text
/Applications/ChatGPT.app/Contents/Resources/codex
```

如果 Codex 安装在其他位置，运行应用时可以通过 `CODEX_BIN` 指定：

```zsh
CODEX_BIN="/path/to/codex" "AppBundle/Codex Usage Widget.app/Contents/MacOS/CodexUsageWidget"
```

## 无界面检查

可以使用一次性模式获取经过清理的用量快照并退出：

```zsh
"AppBundle/Codex Usage Widget.app/Contents/MacOS/CodexUsageWidget" --once
```

该模式不会启动浮窗和菜单栏状态项。

## 项目结构

- `Sources/CodexUsageWidget.swift`：应用主体、AppKit UI、Codex app-server 客户端、历史记录、图表、设置和菜单栏状态项。
- `AppBundle/Contents/Info.plist`：应用 Bundle 元数据。
- `assets/icon.png`：应用图标源文件。
- `build.zsh`：构建 `.app` 和 `.dmg` 的标准脚本。
