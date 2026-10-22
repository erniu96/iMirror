# 更新日志 / Changelog

每个版本发布时，Release 页面会自动附上这里对应版本的内容。发布新版本前，请在最上方添加一节，标题格式为 `## [版本号] - 日期`。

Each release page includes the matching section below. Before tagging a release, add a section at the top titled `## [version] - date`.

## [1.3.0] - 2026-10-22

### 新增 / Added

- 新增繁体中文和日语界面，共四种语言（英文、简体中文、繁体中文、日语），跟随系统语言。
  The interface is now also in Traditional Chinese and Japanese, four languages in all, following the system language.
- 镜像窗口支持键盘：Command-W 停止投屏，Control-Command-F 进入或退出全屏幕，Esc 退出全屏幕。
  Mirroring windows work from the keyboard: Command-W stops mirroring, Control-Command-F enters or exits full screen, Esc leaves full screen.
- 发布包使用固定的自签名证书签名，更新后 macOS 不会再次询问本地网络权限。
  Builds are signed with a fixed self-signed certificate, so macOS keeps the Local Network permission after an update.

### 改进 / Improved

按 Apple 人机交互指南（HIG）逐项检查并调整：
Reviewed against Apple's Human Interface Guidelines:

- 菜单栏图标点开后是标准菜单，不再是弹出面板；每台投屏设备是一个子菜单（显示窗口、全屏幕、停止投屏）。
  The menu bar icon opens a standard menu instead of a popover; each mirroring device has a submenu (Show Window, Full Screen, Stop Mirroring).
- 菜单新增“关于 iMirror”（系统标准关于窗口），设置窗口去掉“关于”面板；“退出”改为“退出 iMirror”，“使用帮助”改为“入门指南”。
  The menu has About iMirror (the standard About window), replacing the About pane in Settings; Quit is now Quit iMirror and Help is now Getting Started Guide.
- 设置窗口记住上次打开的面板，高度随内容变化；接收器名称未修改时“应用”按钮不可用，回车即可应用。
  Settings reopens on the last pane and sizes to its content; Apply is unavailable until the receiver name changes, and Return applies it.
- 确认对话框说明后果并提供“取消”；出错提示的标题直接说明发生了什么，不再只写 “iMirror”。
  Confirmation dialogs explain the consequence and offer Cancel; error alerts are titled with what went wrong instead of just “iMirror”.
- 验证码窗口标题改为“验证码”；欢迎、验证码和设置窗口按内容自动调整大小，较长的翻译不会被截断。
  The code window is titled Pairing Code; the welcome, code and settings windows size to their content, so longer translations aren't clipped.
- 辅助功能：镜像窗口和按钮有 VoiceOver 标签，开启 VoiceOver 时控制按钮常驻显示；验证码逐位朗读。
  Accessibility: mirroring windows and their buttons have VoiceOver labels, the controls stay visible while VoiceOver runs, and the code is read digit by digit.

### 修复 / Fixed

- 解码出错的提示不再把中文全角冒号硬编码进所有语言。
  Video error alerts no longer hard-code a Chinese full-width colon in every language.

## [1.2.1] - 2026-10-06

### 修复 / Fixed

- 全屏、最大化或使用窗口平铺时，画面不再被拉伸，而是保持比例居中显示，空白处填充黑色。
  The picture keeps its aspect ratio, centered with black bars, instead of stretching in full screen, when maximized or when the window is tiled.

## [1.2.0] - 2026-10-05

### 新增 / Added

- 界面支持简体中文和英文，跟随系统语言；也可以在“系统设置 → 通用 → 语言与地区 → App”中单独为 iMirror 选择语言。其他语言无法匹配时显示英文。
  The interface is available in English and Simplified Chinese and follows the system language; you can also pick a language for iMirror alone in System Settings → General → Language & Region → Applications. Other languages fall back to English.
- 欢迎贡献翻译：复制 `Resources/en.lproj` 并翻译即可添加新语言，`Scripts/check-localizations.py` 会检查是否遗漏，详见 [翻译指南](https://github.com/erniu96/iMirror/blob/main/Documentation/LOCALIZATION.md)。
  Translations welcome: copy `Resources/en.lproj` and translate it to add a language; `Scripts/check-localizations.py` checks for gaps. See the [localization guide](https://github.com/erniu96/iMirror/blob/main/Documentation/LOCALIZATION.md).

### 改进 / Improved

- Release 说明会列出与上一版本相比的改动；dmg 窗口的说明改为中英双语。
  Release notes now list the changes since the previous version; the DMG window instructions are bilingual.

## [1.1.0] - 2026-10-05

### 新增 / Added

- 播放投屏设备的声音（AAC-ELD、AAC-LC、ALAC、PCM），音量跟随设备，可在菜单和设置中关闭。
  Plays sound from mirrored devices (AAC-ELD, AAC-LC, ALAC, PCM), following the device volume; can be turned off in the menu and Settings.
- 首次启动显示使用引导；应用已在运行时再次打开也会显示，菜单中新增“使用帮助”。
  A getting-started guide on first launch and whenever the running app is opened again; new Help item in the menu.
- 发布版改为拖拽安装的 dmg。
  Releases ship as a drag-to-Applications DMG.

### 改进 / Improved

- 菜单栏图标换成应用图标的单色版本，自动适配浅色和深色菜单栏。
  The menu bar icon is now a monochrome version of the app icon and adapts to light and dark menu bars.
- 菜单在等待连接时显示分步投屏说明。
  The menu shows step-by-step instructions while waiting for a device.
- 设置中的版本号改为读取应用信息，不再写死。
  Settings reads the version number from the app instead of a hard-coded value.

## [1.0.0] - 2026-10-05

首个公开版本。/ First public release.

- 菜单栏 AirPlay 屏幕镜像接收器：H.264 硬件解码、Metal 显示，支持多台设备同时投屏、随机验证码配对、窗口置顶和全屏、登录时启动。
  Menu bar AirPlay screen mirroring receiver: hardware H.264 decoding, Metal rendering, multiple devices at once, random-code pairing, always-on-top and full-screen windows, open at login.
- 新的应用图标。/ New app icon.
- 从源码构建不再需要 Homebrew，`install.sh` 一键编译并安装到“应用程序”。
  Building from source no longer needs Homebrew; `install.sh` builds and installs into Applications.
- GitHub Release 提供同时支持 Apple Silicon 和 Intel 的通用版本。
  GitHub Releases provide a universal build for Apple Silicon and Intel.

[1.2.1]: https://github.com/erniu96/iMirror/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/erniu96/iMirror/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/erniu96/iMirror/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/erniu96/iMirror/releases/tag/v1.0.0
