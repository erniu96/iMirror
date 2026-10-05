#!/bin/zsh
# Packages an app bundle into a drag-to-Applications disk image.
# Requires dmgbuild: python3 -m pip install dmgbuild
set -euo pipefail

readonly PROJECT_DIR="${0:A:h:h}"
readonly APP_BUNDLE="${1:?用法：make-dmg.sh <iMirror.app> <输出.dmg>}"
readonly OUTPUT="${2:?用法：make-dmg.sh <iMirror.app> <输出.dmg>}"

if [[ ! -d "$APP_BUNDLE" ]]; then
    print -u2 "找不到应用：$APP_BUNDLE"
    exit 1
fi
if ! python3 -c 'import dmgbuild' >/dev/null 2>&1; then
    print -u2 "缺少 dmgbuild。请运行：python3 -m pip install dmgbuild"
    exit 1
fi

rm -f -- "$OUTPUT"
python3 -m dmgbuild \
    -s "$PROJECT_DIR/Resources/DMG/settings.py" \
    -D app="${APP_BUNDLE:A}" \
    -D background="$PROJECT_DIR/Resources/DMG/background.png" \
    "iMirror" "$OUTPUT"
hdiutil verify "$OUTPUT" >/dev/null
print "$OUTPUT"
