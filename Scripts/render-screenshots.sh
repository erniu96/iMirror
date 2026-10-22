#!/bin/zsh
# 用应用里真实的 SwiftUI 视图（菜单、设置、使用引导、验证码窗口）配上示例数据渲染截图，
# 输出 <目录>/<语言>/<light|dark>/*.png。不启动 AirPlay 接收器，窗口全透明，不会出现在屏幕上。
# Renders the shipping views with sample data to <dir>/<language>/<light|dark>/*.png.
set -euo pipefail

readonly PROJECT_DIR="${0:A:h:h}"
readonly OUTPUT_DIR="${1:A}"
readonly BUILD_DIR="$PROJECT_DIR/build/screenshots"
readonly APP="$BUILD_DIR/iMirrorScreenshots.app"

if [[ -z "${1:-}" || "$(uname -s)" != "Darwin" ]]; then
    print -u2 "用法：在 macOS 上运行 $0 <输出目录>"
    exit 2
fi

rm -rf -- "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -R "$PROJECT_DIR"/Resources/*.lproj "$PROJECT_DIR/Resources/AppIcon.icns" "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key><string>en</string>
	<key>CFBundleExecutable</key><string>iMirrorScreenshots</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundleIdentifier</key><string>com.erniu.imirror.screenshots</string>
	<key>CFBundleName</key><string>iMirror</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>VERSION</string>
	<key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/Resources/Info.plist")"
sed -i '' "s/VERSION/$version/" "$APP/Contents/Info.plist"

xcrun swiftc \
    -swift-version 5 \
    -target "$(uname -m)-apple-macosx14.0" \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -module-name iMirrorScreenshots \
    -parse-as-library \
    -o "$APP/Contents/MacOS/iMirrorScreenshots" \
    "$PROJECT_DIR/Domain/ReceiverStatus.swift" \
    "$PROJECT_DIR/Domain/ReceiverConfiguration.swift" \
    "$PROJECT_DIR/App/MenuBarIcon.swift" \
    "$PROJECT_DIR/App/MenuBarView.swift" \
    "$PROJECT_DIR/App/SettingsView.swift" \
    "$PROJECT_DIR/App/WelcomeWindowController.swift" \
    "$PROJECT_DIR/App/PinPanelController.swift" \
    "$PROJECT_DIR"/Scripts/Screenshots/*.swift
codesign --force --sign - "$APP" >/dev/null

for language in en zh-Hans; do
    for appearance in light dark; do
        mkdir -p "$OUTPUT_DIR/$language/$appearance"
        # open 让程序在当前用户的图形会话中运行，通过 SSH 调用也能连上窗口服务器。
        open -W -n "$APP" --args "$OUTPUT_DIR/$language/$appearance" "$appearance" \
            -AppleLanguages "($language)" -AppleLocale "${language/-Hans/_CN}"
    done
done
ls -R "$OUTPUT_DIR"
