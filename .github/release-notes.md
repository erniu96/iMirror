## 下载 / Download

下载 `iMirror-<版本>-macOS-universal.dmg`，同时支持 Apple Silicon 和 Intel Mac，要求 macOS 14 或更高版本。

Download `iMirror-<version>-macOS-universal.dmg`. It runs on Apple Silicon and Intel Macs with macOS 14 or later.

## 安装 / Install

1. 双击 dmg 打开，把窗口里的 iMirror 图标拖到右边的“应用程序”文件夹，然后推出磁盘映像。
2. 从“应用程序”文件夹打开 iMirror，按下方说明完成首次放行。
3. 首次启动时允许 iMirror 访问本地网络，否则 iPhone 找不到它。
4. iMirror 会弹出使用引导；之后它常驻在屏幕右上角的菜单栏，没有 Dock 图标。

1. Open the DMG and drag iMirror onto the Applications folder, then eject the disk image.
2. Open iMirror from Applications and allow it as described below.
3. When asked, allow iMirror to access the local network; otherwise your iPhone can't find it.
4. A getting-started guide appears; afterwards iMirror lives in the menu bar and has no Dock icon.

## 首次打开：跳过 Gatekeeper 校验 / First launch: getting past Gatekeeper

这个版本由 GitHub Actions 从公开源码自动构建，使用 ad-hoc 签名，没有经过 Apple 公证，所以 macOS 第一次会拦截。任选一种方式放行：

This build is made by GitHub Actions from the public source, ad-hoc signed and not notarized by Apple, so macOS blocks it the first time. Use any one of these:

- **macOS 15 及以上 / macOS 15 and later**：双击 iMirror，在提示中点“完成”；然后打开“系统设置 → 隐私与安全性”，在底部点“仍要打开”，输入密码确认。
  Open iMirror and click Done in the warning, then go to System Settings → Privacy & Security, click Open Anyway near the bottom, and confirm with your password.
- **macOS 14**：按住 Control 点按（或右键）iMirror，选“打开”，再点“打开”。
  Control-click (or right-click) iMirror, choose Open, then click Open.
- **终端 / Terminal（所有版本 / any version）**：

  ```bash
  xattr -dr com.apple.quarantine /Applications/iMirror.app
  ```

  提示“已损坏，无法打开”时也用这条命令。它只移除下载时附加的隔离标记，不修改应用本身。
  Use this too if macOS says the app "is damaged". It only removes the download quarantine flag and does not modify the app.

## 校验 / Verify

`shasum -a 256 iMirror-*.dmg` 的结果应与 `.sha256` 文件一致。/ The output should match the `.sha256` file.

## 源代码 / Source code

iMirror 按 GNU GPLv3 分发，本页面的 “Source code” 压缩包即为对应源代码。
iMirror is distributed under the GNU GPLv3; the "Source code" archives on this page are the matching source.
