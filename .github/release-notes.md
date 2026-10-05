## 下载

下载 `iMirror-<版本>-macOS-universal.dmg`。同时支持 Apple Silicon 和 Intel Mac，要求 macOS 14 或更高版本。

## 安装

1. 双击 dmg 打开，把窗口里的 iMirror 图标拖到右边的“应用程序”文件夹，然后推出磁盘映像。
2. 从“应用程序”文件夹打开 iMirror，按下方说明完成首次放行。
3. 首次启动时允许 iMirror 访问本地网络，否则 iPhone 找不到它。
4. iMirror 会弹出使用引导；之后它常驻在屏幕右上角的菜单栏，没有 Dock 图标。

## 首次打开：跳过 Gatekeeper 校验

这个版本由 GitHub Actions 从公开源码自动构建，使用 ad-hoc 签名，没有经过 Apple 公证，所以 macOS 第一次会拦截。任选一种方式放行，之后就能正常双击打开。

**方法一：系统设置（macOS 15 及以上）**

1. 双击 iMirror，弹出“未打开 iMirror”的提示时点“完成”。
2. 打开“系统设置 → 隐私与安全性”，滚动到底部“安全性”一栏，找到关于 iMirror 的提示，点“仍要打开”。
3. 输入登录密码，在随后的对话框里再点“仍要打开”。

**方法二：右键打开（macOS 14）**

在“应用程序”文件夹里按住 Control 点按（或右键）iMirror，选“打开”，在对话框里再点“打开”。

**方法三：终端命令（所有版本）**

```bash
xattr -dr com.apple.quarantine /Applications/iMirror.app
```

如果提示“iMirror 已损坏，无法打开”，也用这条命令解决。它只移除下载时附加的“来自互联网”隔离标记，不修改应用本身。

## 校验

可用 `shasum -a 256 iMirror-*.dmg` 核对与 `.sha256` 文件中的值一致。

## 源代码

iMirror 按 GNU GPLv3 分发。本页面底部的 “Source code” 压缩包即为与此版本对应的完整源代码。
