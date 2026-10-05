#!/bin/zsh
set -euo pipefail

readonly PROJECT_DIR="${0:A:h:h}"
readonly APP_BUNDLE="$PROJECT_DIR/build/iMirror.app"
readonly OUTPUT_DIR="$PROJECT_DIR/dist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/Resources/Info.plist")"
readonly VERSION
readonly ARCHIVE="$OUTPUT_DIR/iMirror-$VERSION-$(uname -m).zip"
readonly SOURCE_ARCHIVE="$OUTPUT_DIR/iMirror-$VERSION-source.tar.gz"

if ! git -C "$PROJECT_DIR" rev-parse --verify HEAD >/dev/null 2>&1; then
    print -u2 "请先将待发布源代码提交到 Git。"
    exit 1
fi
if [[ -n "$(git -C "$PROJECT_DIR" status --porcelain --untracked-files=normal)" ]]; then
    print -u2 "工作区有未提交文件。请先提交，确保源代码归档与构建一致。"
    exit 1
fi

if [[ -z "${IMIRROR_SIGN_IDENTITY:-}" ]]; then
    print -u2 "请设置 IMIRROR_SIGN_IDENTITY，例如：Developer ID Application: Your Name (TEAMID)"
    exit 1
fi
if [[ -z "${IMIRROR_NOTARY_PROFILE:-}" ]]; then
    print -u2 "请设置 IMIRROR_NOTARY_PROFILE（由 notarytool store-credentials 创建）。"
    exit 1
fi

IMIRROR_MINIMUM_MACOS="${IMIRROR_MINIMUM_MACOS:-14.0}" "$PROJECT_DIR/build.sh"
mkdir -p "$OUTPUT_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ARCHIVE"

xcrun notarytool submit "$ARCHIVE" \
    --keychain-profile "$IMIRROR_NOTARY_PROFILE" \
    --wait
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"

rm -f -- "$ARCHIVE"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ARCHIVE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
spctl --assess --type execute --verbose=2 "$APP_BUNDLE"

git -C "$PROJECT_DIR" archive \
    --format=tar.gz \
    --prefix=iMirror-$VERSION/ \
    --output="$SOURCE_ARCHIVE" \
    HEAD

print "可分发压缩包：$ARCHIVE"
print "对应源代码：$SOURCE_ARCHIVE"
