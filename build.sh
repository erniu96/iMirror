#!/bin/zsh
set -euo pipefail

readonly PROJECT_DIR="${0:A:h}"
readonly BUILD_DIR="$PROJECT_DIR/build"
readonly ACTION="${1:-build}"

case "$ACTION" in
    clean)
        rm -rf -- "$BUILD_DIR"
        print "已清理 $BUILD_DIR"
        exit 0
        ;;
    build|test|run) ;;
    *)
        print -u2 "用法：$0 [build|test|run|clean]"
        exit 2
        ;;
esac

if [[ "$(uname -s)" != "Darwin" ]]; then
    print -u2 "iMirror 需要 macOS 和 Xcode Command Line Tools。"
    exit 1
fi
if ! xcode-select -p >/dev/null 2>&1; then
    print -u2 "缺少 Xcode Command Line Tools。请运行 xcode-select --install，安装完成后重试。"
    exit 1
fi

readonly APP_NAME="iMirror"
readonly APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
readonly CONTENTS="$APP_BUNDLE/Contents"
readonly MACOS_DIR="$CONTENTS/MacOS"
readonly RESOURCES_DIR="$CONTENTS/Resources"
readonly FRAMEWORKS_DIR="$CONTENTS/Frameworks"
# Default to the oldest supported system so a local build also runs on other Macs
# and reuses one OpenSSL build regardless of the host macOS version.
readonly MINIMUM_MACOS="${IMIRROR_MINIMUM_MACOS:-14.0}"
readonly TARGET_ARCH="$(uname -m)"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
readonly SDK_PATH

if [[ -n "${IMIRROR_OPENSSL_PREFIX:-}" ]]; then
    OPENSSL_PREFIX="$IMIRROR_OPENSSL_PREFIX"
else
    OPENSSL_PREFIX="$("$PROJECT_DIR/Scripts/prepare-openssl.sh" "$MINIMUM_MACOS" "$TARGET_ARCH")"
fi
readonly OPENSSL_PREFIX
readonly LIBCRYPTO="$OPENSSL_PREFIX/lib/libcrypto.3.dylib"
if [[ ! -f "$LIBCRYPTO" ]]; then
    print -u2 "找不到 $LIBCRYPTO"
    exit 1
fi

rm -rf -- "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $MINIMUM_MACOS" "$CONTENTS/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
for localization in "$PROJECT_DIR"/Resources/*.lproj(N); do
    cp -R "$localization" "$RESOURCES_DIR/"
done
plutil -lint "$RESOURCES_DIR"/*.lproj/*.strings >/dev/null
cp "$PROJECT_DIR/COPYING" "$RESOURCES_DIR/GPL-3.0.txt"
cp "$PROJECT_DIR/ThirdParty/NOTICE.md" "$RESOURCES_DIR/ThirdParty-NOTICE.md"
cp "$PROJECT_DIR"/ThirdParty/*.txt "$RESOURCES_DIR/"

typeset -a c_sources c_objects swift_sources
c_sources=("$PROJECT_DIR"/AirPlay/**/*.c(N))

typeset source relative object_name object_path
for source in "${c_sources[@]}"; do
    relative="${source#$PROJECT_DIR/AirPlay/}"
    object_name="${relative//\//_}"
    object_path="$BUILD_DIR/airplay_${object_name%.c}.o"
    xcrun clang \
        -arch "$TARGET_ARCH" \
        -mmacosx-version-min="$MINIMUM_MACOS" \
        -isysroot "$SDK_PATH" \
        -I"$PROJECT_DIR/AirPlay" \
        -I"$PROJECT_DIR/AirPlay/plist" \
        -I"$OPENSSL_PREFIX/include" \
        -DOPENSSL_API_COMPAT=0x10101000L \
        -O2 -fno-strict-aliasing -Wall -Wno-deprecated-declarations -Wno-format \
        -c "$source" -o "$object_path"
    c_objects+=("$object_path")
done
rm -f -- "$BUILD_DIR/libairplay.a"
xcrun ar rcs "$BUILD_DIR/libairplay.a" "${c_objects[@]}"

xcrun clang++ \
    -arch "$TARGET_ARCH" \
    -mmacosx-version-min="$MINIMUM_MACOS" \
    -isysroot "$SDK_PATH" \
    -I"$PROJECT_DIR/Bridge" \
    -I"$PROJECT_DIR/AirPlay" \
    -I"$PROJECT_DIR/AirPlay/plist" \
    -I"$OPENSSL_PREFIX/include" \
    -fobjc-arc -fobjc-weak -O2 \
    -c "$PROJECT_DIR/Bridge/AirPlayReceiverBridge.mm" \
    -o "$BUILD_DIR/AirPlayReceiverBridge.o"

swift_sources=(
    "$PROJECT_DIR"/Domain/*.swift(N)
    "$PROJECT_DIR"/Storage/*.swift(N)
    "$PROJECT_DIR"/Services/*.swift(N)
    "$PROJECT_DIR"/Video/*.swift(N)
    "$PROJECT_DIR"/Audio/*.swift(N)
    "$PROJECT_DIR"/Window/*.swift(N)
    "$PROJECT_DIR"/App/*.swift(N)
)

xcrun swiftc \
    -swift-version 5 \
    -target "$TARGET_ARCH-apple-macosx$MINIMUM_MACOS" \
    -sdk "$SDK_PATH" \
    -module-name iMirror \
    -import-objc-header "$PROJECT_DIR/iMirror-Bridging-Header.h" \
    -I"$PROJECT_DIR/Bridge" \
    -I"$PROJECT_DIR/AirPlay" \
    -I"$OPENSSL_PREFIX/include" \
    -Xcc -I"$PROJECT_DIR/AirPlay/plist" \
    -parse-as-library \
    -O -whole-module-optimization \
    -emit-object \
    -o "$BUILD_DIR/iMirrorSwift.o" \
    "${swift_sources[@]}"

xcrun swiftc \
    -target "$TARGET_ARCH-apple-macosx$MINIMUM_MACOS" \
    -sdk "$SDK_PATH" \
    -o "$MACOS_DIR/$APP_NAME" \
    "$BUILD_DIR/iMirrorSwift.o" \
    "$BUILD_DIR/AirPlayReceiverBridge.o" \
    "$BUILD_DIR/libairplay.a" \
    "$LIBCRYPTO" \
    -Xlinker -rpath -Xlinker "@executable_path/../Frameworks" \
    -framework AppKit \
    -framework SwiftUI \
    -framework Combine \
    -framework Metal \
    -framework MetalKit \
    -framework VideoToolbox \
    -framework CoreVideo \
    -framework CoreMedia \
    -framework AVFoundation \
    -framework AudioToolbox \
    -framework ServiceManagement \
    -lobjc -lc++

readonly LIBCRYPTO_NAME="${LIBCRYPTO:t}"
# The executable records libcrypto's install name, which can differ from the
# path passed to the linker (for example a symlinked prefix).
LIBCRYPTO_INSTALL_NAME="$(otool -D "$LIBCRYPTO" | tail -n 1)"
readonly LIBCRYPTO_INSTALL_NAME
cp "$LIBCRYPTO" "$FRAMEWORKS_DIR/$LIBCRYPTO_NAME"
chmod 644 "$FRAMEWORKS_DIR/$LIBCRYPTO_NAME"
install_name_tool -id "@rpath/$LIBCRYPTO_NAME" "$FRAMEWORKS_DIR/$LIBCRYPTO_NAME"
install_name_tool \
    -change "$LIBCRYPTO_INSTALL_NAME" \
    "@executable_path/../Frameworks/$LIBCRYPTO_NAME" \
    "$MACOS_DIR/$APP_NAME"

readonly SIGN_IDENTITY="${IMIRROR_SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --sign - "$FRAMEWORKS_DIR/$LIBCRYPTO_NAME"
    codesign --force --sign - "$APP_BUNDLE"
else
    codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$FRAMEWORKS_DIR/$LIBCRYPTO_NAME"
    codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
fi
codesign --verify --deep --strict "$APP_BUNDLE"
if otool -L "$MACOS_DIR/$APP_NAME" | tail -n +2 | grep -F -- "$OPENSSL_PREFIX" >/dev/null; then
    print -u2 "应用仍引用构建机上的 OpenSSL：$OPENSSL_PREFIX"
    exit 1
fi

print "构建完成：$APP_BUNDLE"

if [[ "$ACTION" == "test" ]]; then
    IMIRROR_OPENSSL_PREFIX="$OPENSSL_PREFIX" "$PROJECT_DIR/Scripts/test-protocol.sh" || exit $?
    xcrun swiftc \
        -swift-version 5 \
        -target "$TARGET_ARCH-apple-macosx$MINIMUM_MACOS" \
        -sdk "$SDK_PATH" \
        "$PROJECT_DIR/Domain/ReceiverConfiguration.swift" \
        "$PROJECT_DIR/Storage/SettingsStore.swift" \
        "$PROJECT_DIR/Video/AnnexBParser.swift" \
        "$PROJECT_DIR/Video/VideoSessionRouter.swift" \
        "$PROJECT_DIR/Window/MirrorWindowSizing.swift" \
        "$PROJECT_DIR/Tests/UnitTests.swift" \
        -framework CoreGraphics \
        -o "$BUILD_DIR/iMirrorTests"
    "$BUILD_DIR/iMirrorTests" || exit $?

    readonly VIDEO_FIXTURE="${IMIRROR_VIDEO_FIXTURE:-$PROJECT_DIR/Tests/Fixtures/blue-640x480.h264}"
    if [[ ! -f "$VIDEO_FIXTURE" ]]; then
        print -u2 "找不到 H.264 测试文件：$VIDEO_FIXTURE"
        exit 1
    fi
    xcrun swiftc \
        -swift-version 5 \
        -target "$TARGET_ARCH-apple-macosx$MINIMUM_MACOS" \
        -sdk "$SDK_PATH" \
        "$PROJECT_DIR/Video/AnnexBParser.swift" \
        "$PROJECT_DIR/Video/H264Decoder.swift" \
        "$PROJECT_DIR/Video/VideoSessionRouter.swift" \
        "$PROJECT_DIR/Video/VideoPipeline.swift" \
        "$PROJECT_DIR/Tests/VideoPipelineSmokeTests.swift" \
        -framework VideoToolbox \
        -framework CoreVideo \
        -framework CoreMedia \
        -o "$BUILD_DIR/iMirrorVideoTests"
    "$BUILD_DIR/iMirrorVideoTests" "$VIDEO_FIXTURE" || exit $?

    xcrun swiftc \
        -swift-version 5 \
        -target "$TARGET_ARCH-apple-macosx$MINIMUM_MACOS" \
        -sdk "$SDK_PATH" \
        "$PROJECT_DIR/Audio/AirPlayAudioFormat.swift" \
        "$PROJECT_DIR/Audio/AudioPacketDecoder.swift" \
        "$PROJECT_DIR/Tests/AudioDecoderTests.swift" \
        -framework AVFoundation \
        -framework AudioToolbox \
        -o "$BUILD_DIR/iMirrorAudioTests"
    "$BUILD_DIR/iMirrorAudioTests" || exit $?
fi

if [[ "$ACTION" == "run" ]]; then
    open "$APP_BUNDLE"
fi
