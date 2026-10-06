# 更新日志 / Changelog

每个版本发布时，Release 页面会自动附上这里对应版本的内容。发布新版本前，请在最上方添加一节，标题格式为 `## [版本号] - 日期`。

Each release page includes the matching section below. Before tagging a release, add a section at the top titled `## [version] - date`.

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
