# Third-party notices

iMirror 的 AirPlay/RAOP 协议层来自用户提供的 UxPlay 派生参考实现。保留的文件包含以下第三方组件；具体作者和版权年份见源文件中的原始声明。原参考实现没有记录全部组件的精确版本。

- [UxPlay](https://github.com/FDH2/UxPlay)、[RPiPlay](https://github.com/FDH2/RPiPlay) 及 PlayFair — GPL v3 或更新版本，见仓库根目录 `COPYING`。`AirPlay/crypto_openssl.*` 保留 Florian Draschbacher、Jaslo Ziska 的版权声明；PlayFair 接收端实现位于 `AirPlay/playfair/`。
- 原 RAOP 接收层 — LGPL v2.1 或更新版本；保留 Juho Vähä-Herttua、dsafa22 的源文件声明，完整条款见 `LGPL-2.1.txt`。
- [libplist](https://github.com/libimobiledevice/libplist) 及其 cnary 节点实现 — LGPL v2.1 或更新版本，位于 `AirPlay/plist/`，完整条款见 `LGPL-2.1.txt`。
- [llhttp 6.0.6](https://github.com/nodejs/llhttp/tree/v6.0.6) — MIT License，位于 `AirPlay/llhttp/`，完整条款见 `llhttp-LICENSE.txt`。
- [tiny-AES-c](https://github.com/kokke/tiny-AES-c) — Unlicense，位于 `AirPlay/aes.*`，完整条款见 `tiny-AES-LICENSE.txt`。
- axTLS 的 AES CBC 实现 — BSD 3-Clause，位于 `AirPlay/crypto/aes.c`，Copyright (c) 2007 Cameron Rich，完整条款见 `axTLS-LICENSE.txt`。
- [csrp](https://github.com/cocagne/csrp) — MIT License，位于 `AirPlay/srp.*`，完整条款见 `csrp-LICENSE.txt`。
- time64 — MIT License，Copyright (c) 2007-2010 Michael G Schwern，位于 `AirPlay/plist/time64.*`，完整条款见 `time64-LICENSE.txt`。
- LibTomCrypt 的 SHA-512 实现 — 原文件声明可自由用于所有用途且不提供保证；位于 `AirPlay/ed25519/sha512.*`，保留的声明见 `SHA512-NOTICE.txt`。该目录仅保留 SHA-512，不再包含旧 Ed25519 配对实现。
- [PiP by amitv87](https://github.com/amitv87/PiP) — MIT License，原参考实现包含相关实现思路；原有条款保留在 `PiP-LICENSE.txt`。
- [OpenSSL](https://github.com/openssl/openssl) — Apache License 2.0；构建时动态链接并将 `libcrypto.3.dylib` 复制到应用包。日常构建使用本机 Homebrew `openssl@3`，可移植构建使用 `Scripts/prepare-openssl.sh` 指定且校验的版本；完整条款见 `OpenSSL-LICENSE.txt`。

iMirror 整体按 GPLv3 分发。提供二进制时，请同时提供对应版本的源代码、构建脚本和这些声明；发布脚本会同时生成源码包。第三方组件各自的原始许可和版权声明继续保留。

2026-10-03 的清理移除了未使用的 Curve25519/Ed25519 实现、旧 axTLS 非 AES 模块、独立演示程序、PlayFair 发送端和 Raspberry Pi 调试转储；接收端 AES、SHA-512、配对、HTTP、plist 与网络协议实现保留。第三方代码已按 iMirror 的接收器需求修改，并非未经修改的上游版本。
