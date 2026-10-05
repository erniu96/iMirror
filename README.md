<p align="center"><img src="Resources/AppIcon.svg" width="160" alt="iMirror 图标"></p>

# iMirror

简体中文 | [English](README.en.md)

iMirror 是使用 SwiftUI 与 macOS 原生媒体栈构建的菜单栏 AirPlay 屏幕镜像接收器。应用启动后仅驻留在右上角菜单栏；连接 iPhone、iPad 或 Mac 后，以无标题栏悬浮窗口显示画面。

**[下载最新版本](https://github.com/erniu96/iMirror/releases/latest)** · 需要 macOS 14 或更高版本 · 同时支持 Apple Silicon 和 Intel Mac

## 已实现

- SwiftUI `MenuBarExtra`，不显示 Dock 图标。
- Bonjour `_airplay._tcp` / `_raop._tcp` 服务注册，同时使用 P2P 与 AWDL flags。
- 每次新设备发起配对时生成新的随机四位验证码，不保存固定验证码。
- 接收器名称自动附加稳定的四位本机标记，便于在多台 Mac 之间区分。
- 已验证客户端持久化，后续连接可免验证码；支持一键遗忘。
- VideoToolbox 硬件 H.264 解码，IOSurface/NV12 直接交给 Metal 显示。
- 支持多台设备同时投屏：每个连接使用独立的硬件解码器、Metal 视图和窗口，彼此断开互不影响。
- 无标题栏、可缩放、默认置顶的投屏窗口；鼠标移入才显示停止投屏、置顶和全屏按钮。
- 横竖屏切换时保持视频比例，首帧按 1:1 像素或屏幕可见区域自动适配。
- 播放投屏设备的声音（AAC-ELD、AAC-LC、ALAC、PCM），跟随设备音量，可在菜单中关闭。
- 首次启动显示使用引导；应用已在运行时再次打开也会弹出引导，菜单中可随时点“使用帮助”。
- 菜单栏图标是应用图标的单色版本，自动适配浅色和深色菜单栏。
- 界面支持简体中文和英文，跟随系统语言，也可在“系统设置 → 通用 → 语言与地区 → App”中单独设置；欢迎[贡献更多语言](Documentation/LOCALIZATION.md)。
- 使用 `SMAppService` 支持登录时自动启动。
- 睡眠时停止网络服务，唤醒后自动恢复。
- 推送版本标签后自动构建 universal 应用并发布到 GitHub Release；另有 Developer ID 签名、公证和 zip 分发脚本。

## 下载安装（无需编译）

从 [Releases](https://github.com/erniu96/iMirror/releases/latest) 下载最新的 `iMirror-<版本>-macOS-universal.dmg`，同时支持 Apple Silicon 和 Intel Mac。双击打开后，把窗口里的 iMirror 图标拖到右边的“应用程序”文件夹即可。

发布版使用 ad-hoc 签名，没有经过 Apple 公证，首次打开会被 Gatekeeper 拦截，任选一种方式放行：

- **macOS 15 及以上**：先双击打开一次，在提示中点“完成”；然后到“系统设置 → 隐私与安全性”底部点“仍要打开”，输入密码确认。
- **macOS 14**：按住 Control 点按（或右键）iMirror，选“打开”，再点“打开”。
- **终端（所有版本）**：`xattr -dr com.apple.quarantine /Applications/iMirror.app`。提示“已损坏，无法打开”时也用这条命令。

放行后即可正常双击打开。首次启动请允许 iMirror 访问本地网络，并按弹出的引导操作。

## 从源码安装

要求 macOS 14 或更高版本和 Xcode Command Line Tools，不需要 Homebrew。没有安装 Command Line Tools 时先运行 `xcode-select --install`。

```bash
bash install.sh
```

脚本会编译应用，退出正在运行的旧版本，用 `ditto` 复制到 `/Applications/iMirror.app` 并启动。当前用户没有 `/Applications` 写权限时会通过 `sudo` 请求管理员密码。加 `--no-open` 只安装不启动；用 `IMIRROR_INSTALL_DIR` 可以安装到其他目录。

首次构建会从 OpenSSL 官方 GitHub Release 下载 3.6.3 源码（约 53 MB），校验 SHA-256 后编译，需要几分钟；产物缓存在 `.dependencies`，之后直接复用。GitHub 下载慢时，可用 `IMIRROR_OPENSSL_URL` 指向同一文件的镜像，校验仍然生效。已有自己编译的 OpenSSL 3 时，可用 `IMIRROR_OPENSSL_PREFIX` 指定其安装前缀。

## 开发构建

```bash
./build.sh test
bash command.txt
```

`bash command.txt` 会构建并直接从 `build/` 启动菜单栏应用，可从任意工作目录调用，适合开发调试；日常使用请用 `install.sh` 安装，“登录时启动”需要应用位于固定路径。iMirror 仅支持 macOS；在 Linux 或 Windows 上运行时会明确提示并退出。

构建产物默认以 macOS 14 为最低版本，可在其他 macOS 14 及以上的同架构 Mac 上运行。需要更高的最低版本时设置 `IMIRROR_MINIMUM_MACOS`，例如 `IMIRROR_MINIMUM_MACOS=15.0 ./build.sh`；每个最低版本会单独编译一份 OpenSSL。

应用产物为 `build/iMirror.app`。本地构建使用 ad-hoc 签名，每次重新构建签名都会变化，系统可能再次询问本地网络或防火墙权限，属于正常现象。给朋友分发前必须按 [分发文档](Documentation/DISTRIBUTION.md) 完成 Developer ID 签名和公证。

本地制作 dmg：`python3 -m pip install dmgbuild` 后运行 `./Scripts/make-dmg.sh build/iMirror.app iMirror.dmg`。dmg 窗口背景是 `Resources/DMG/background.svg` 渲染出的 `background.png` 与 `background@2x.png`。

应用图标的源文件是 `Resources/AppIcon.svg`。修改后运行 `node Scripts/make-app-icon.mjs` 重新生成 `Resources/AppIcon.icns`（需要 Node 和 Playwright Chromium），并一起提交。

## 发布

先在 [CHANGELOG.md](CHANGELOG.md) 顶部写好新版本的改动，再推送与 `Info.plist` 中 `CFBundleShortVersionString` 一致的标签（例如 `v1.2.0`）。`.github/workflows/release.yml` 会在 Apple Silicon 和 Intel 上分别构建并运行全部测试，合并成 universal 应用，以 ad-hoc 签名，用 `Scripts/make-dmg.sh` 制作拖拽安装的 dmg，连同 SHA-256 校验文件发布到 GitHub Release。Release 说明由 CHANGELOG 中该版本的内容、与上一版本的对比链接和 `.github/release-notes.md` 的安装说明组成；CHANGELOG 缺少该版本时发布会失败。需要正式签名和公证的版本请按 [分发文档](Documentation/DISTRIBUTION.md) 在本机打包。

## 翻译

界面文字在 `Resources/<语言代码>.lproj/Localizable.strings`，代码中以英文原文作为 key。添加语言只需复制 `en.lproj`、翻译、在 `Info.plist` 的 `CFBundleLocalizations` 中登记，然后运行 `python3 Scripts/check-localizations.py` 检查遗漏。详见 [翻译指南](Documentation/LOCALIZATION.md)。

## 测试

`./build.sh test` 会完整构建应用，检查签名，运行协议测试、Swift 单元测试、两路独立的 H.264 解码测试，以及音频解码测试（用系统编码器生成 AAC-ELD、AAC-LC、ALAC 数据，再按 AirPlay 协商参数解码）。默认视频样本由程序生成，存放在 `Tests/Fixtures/`，无需准备本机录像；可用 `IMIRROR_VIDEO_FIXTURE` 指定其他 Annex-B H.264 文件，文件不存在时测试会失败。

GitHub Actions 配置为在 Apple Silicon 和 Intel 的 macOS 15 环境中运行完整测试。虚拟机通过 `IMIRROR_ALLOW_SOFTWARE_DECODER=1` 允许 VideoToolbox 使用软件解码；应用仍默认要求硬件解码。自动化测试不覆盖 iPhone 真机发现、配对、AWDL 连通性和 Metal 窗口显示，这些需要在 Mac 上实际投屏验收。

只验证可移植的 C 协议模块时，在 macOS 或 Linux 上运行：

```bash
./Scripts/test-protocol.sh
```

Linux 上需要 C 编译器和 OpenSSL 3 开发包；这条命令不会构建 macOS 应用。Linux 桌面用户如需 AirPlay 接收器，可使用本项目协议层的上游 [UxPlay](https://github.com/FDH2/UxPlay)。

## 使用

1. 启动 iMirror，菜单栏出现接收器图标（手机和显示器的小图标）。首次启动会弹出使用引导。
2. 在 iPhone/iPad 控制中心打开“屏幕镜像”，或在 Mac 控制中心打开“屏幕镜像”。
3. 选择带本机标记的名称（例如 `iMirror-A7K2`），按 Mac 上显示的随机验证码完成配对。
4. 在设置中可修改接收器基础名称、开启登录时启动、管理配对设备。

iPhone 找不到接收器时，依次检查：macOS 15 及以上首次启动时是否允许了“本地网络”权限（可在“系统设置 → 隐私与安全性 → 本地网络”中重新打开）；iPhone 与 Mac 是否在同一 Wi-Fi；macOS 防火墙是否阻止了 iMirror 的传入连接。

AWDL 没有面向第三方的公开“AirPlay 接收器”框架。iMirror 使用 Apple 公开的 DNS-SD P2P/AWDL 注册标志参与点对点发现，实际 AirPlay/RAOP 会话由开源协议层处理。部分 macOS 版本需要在“系统设置 → 通用 → 隔空投送与接力”中保持“隔空播放接收器”开启，才能让 AWDL 接口处于可用状态。

## 卸载

1. 在设置中关闭“登录时启动”，然后从菜单栏退出 iMirror。
2. 删除 `/Applications/iMirror.app`。
3. 如需同时清除接收器身份和已配对设备，删除 `~/Library/Application Support/iMirror`，并运行 `defaults delete com.erniu.imirror` 清除设置。

## 约定

- 默认接收器基础名：`iMirror`，实际广播名自动追加稳定的四位随机标记
- 验证码：每次新配对随机生成四位数字
- 默认置顶：开启
- 视频：H.264，最高广播能力 1920×1080@60
- 音频：播放发送端协商的 AAC-ELD、AAC-LC、ALAC 或 PCM 音频；为降低延迟，排队超过 0.35 秒的音频会被丢弃
- 不广播尚未实现的 HEVC 能力

更多设计说明见 [架构文档](Documentation/ARCHITECTURE.md)。

## 许可证

协议层基于 GPLv3 的 UxPlay 派生代码，因此 iMirror 整体按 GNU GPLv3 分发，完整条款见 [COPYING](COPYING)。第三方声明见 [ThirdParty/NOTICE.md](ThirdParty/NOTICE.md)。分发脚本同时生成应用压缩包和对应源代码归档。
