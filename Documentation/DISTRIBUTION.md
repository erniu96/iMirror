# 签名、公证与分发

朋友可直接使用的 macOS 应用需要 Developer ID 签名和 Apple 公证。构建脚本不会把 ad-hoc 签名伪装成可分发版本。

1. 安装 Xcode Command Line Tools：`xcode-select --install`。OpenSSL 由构建脚本从已校验的官方源码编译，不需要 Homebrew。
2. 在 Apple Developer 账户创建 `Developer ID Application` 证书。
3. 保存公证凭据：

   ```bash
   xcrun notarytool store-credentials imirror-notary \
     --apple-id "你的 Apple ID" \
     --team-id "TEAMID" \
     --password "App 专用密码"
   ```

4. 执行 `./build.sh test`，将待发布源码提交到 Git，并确保工作区没有未提交文件。分发脚本使用同一个提交生成源代码归档。
5. 打包：

   ```bash
   IMIRROR_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
   IMIRROR_NOTARY_PROFILE="imirror-notary" \
   ./Scripts/package-release.sh
   ```

   分发脚本默认生成 macOS 14+ 产物，并首次从已校验的官方源码编译对应最低系统版本的 OpenSSL。可通过 `IMIRROR_MINIMUM_MACOS` 提高最低版本。

产物位于 `dist/iMirror-<版本>-<架构>.zip`，对应源代码位于 `dist/iMirror-<版本>-source.tar.gz`（版本取自 `Info.plist`）；分发 GPLv3 二进制时请一并提供两者。当前脚本按构建 Mac 的原生架构生成包；Apple Silicon 上是 arm64，Intel Mac 上是 x86_64。若要发布 universal 版本，需要分别准备两个架构的 OpenSSL 动态库和应用可执行文件，再使用 `lipo` 合并匹配的 Mach-O 文件并重新签名、公证。

解压后请把 iMirror 拖到 `/Applications`。登录项注册要求应用位于稳定路径，不应直接从 Downloads 或压缩包临时目录运行。
