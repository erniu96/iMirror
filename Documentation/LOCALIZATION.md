# 翻译指南 / Localization Guide

iMirror 的界面文字放在 `Resources/<语言代码>.lproj/` 里。英文是开发语言：代码中直接写英文原文，英文原文同时作为查找翻译的 key；系统语言没有对应翻译时显示英文。

iMirror's interface text lives in `Resources/<language>.lproj/`. English is the development language: the code contains the English text, which is also the key used to look up translations. Languages without a translation fall back to English.

| 文件 / File | 内容 / Contents |
| --- | --- |
| `Localizable.strings` | 菜单、设置、引导、提示和错误信息 / menus, settings, guide, alerts and errors |
| `InfoPlist.strings` | 系统权限提示（本地网络）/ system permission prompts (local network) |

已支持 / Available: `en`（English）、`zh-Hans`（简体中文）。

## 添加一种语言 / Adding a language

1. 复制英文目录，目录名用 Apple 的语言代码，例如日语 `ja`、繁体中文 `zh-Hant`、德语 `de`：

   Copy the English folder, naming it with Apple's language code, e.g. `ja`, `zh-Hant`, `de`:

   ```bash
   cp -R Resources/en.lproj Resources/ja.lproj
   ```

2. 翻译每一行等号**右边**的文字，左边的 key 保持不变：

   Translate the text on the **right** of each `=`; leave the key on the left unchanged:

   ```text
   "Show All Windows" = "すべてのウインドウを表示";
   ```

   - `%@`（文字）、`%lld`、`%d`（数字）是占位符，必须原样保留，数量和类型不能变。语序不同时可以写成 `%1$@`、`%2$@` 调整顺序。
     `%@` (text), `%lld` and `%d` (numbers) are placeholders; keep the same number and kind. Use `%1$@`, `%2$@` to reorder them.
   - 文字里的双引号要写成 `\"`。/ Write double quotes inside text as `\"`.
   - “屏幕镜像”“控制中心”“隐私与安全性”等系统名称请使用 Apple 在该语言中的官方叫法。
     Use Apple's official names for system features such as Screen Mirroring, Control Center and Privacy & Security.

3. 在 `Resources/Info.plist` 的 `CFBundleLocalizations` 里加上语言代码：

   Add the language code to `CFBundleLocalizations` in `Resources/Info.plist`:

   ```xml
   <string>ja</string>
   ```

4. 运行检查脚本（只需要 Python 3，不需要 Mac）：

   Run the checker (Python 3 only; no Mac needed):

   ```bash
   python3 Scripts/check-localizations.py
   ```

   它会指出缺少或多余的翻译、占位符不一致、空翻译，以及 `Info.plist` 没有登记的语言。CI 也会运行这项检查。

   It reports missing or extra entries, mismatched placeholders, empty translations, and languages missing from `Info.plist`. CI runs the same check.

5. 在 Mac 上用 `./build.sh run` 查看效果。不想切换整个系统语言时，可以在“系统设置 → 通用 → 语言与地区 → App”里单独给 iMirror 选择语言，或者直接运行：

   Check it on a Mac with `./build.sh run`. To try a language without changing the whole system, pick it for iMirror in System Settings → General → Language & Region → Applications, or run:

   ```bash
   build/iMirror.app/Contents/MacOS/iMirror -AppleLanguages '(ja)'
   ```

6. 提交 Pull Request。/ Open a pull request.

## 给开发者 / For developers

- SwiftUI 的 `Text`、`Button`、`Toggle`、`Label`、`Section` 等直接写英文字面量，会自动查找翻译。不需要翻译的文字用 `Text(verbatim:)`。
  SwiftUI literals in `Text`, `Button`, `Toggle`, `Label`, `Section` etc. are looked up automatically. Use `Text(verbatim:)` for text that must not be translated.
- 其他字符串用 `String(localized: "…")`；Objective-C 用 `NSLocalizedString(@"…", nil)`。
  Use `String(localized: "…")` for other strings and `NSLocalizedString(@"…", nil)` in Objective-C.
- 插值会变成占位符：字符串是 `%@`，整数是 `%lld`。状态码等数字请先转换成 `Int(…)`。
  Interpolations become placeholders: `%@` for strings and `%lld` for integers. Convert status codes and other numbers with `Int(…)`.
- 新增或修改文字后，同步更新 `en.lproj` 和其他所有语言，再运行检查脚本。脚本也会拒绝界面代码里硬编码的中文。
  After adding or changing text, update `en.lproj` and every other language, then run the checker. It also rejects hard-coded Chinese in UI code.
