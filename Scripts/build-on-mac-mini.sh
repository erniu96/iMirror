#!/bin/bash
# Builds a universal, fixed-certificate-signed DMG on the LAN Mac mini and copies it back.
# Run on 222:  bash Scripts/build-on-mac-mini.sh
#
# The tracked and new (not ignored) files of this working tree are copied to
# ~/imirror-build/src on the Mac mini, which builds and tests arm64, cross-builds
# x86_64, merges them with lipo, signs with ~/.config/imirror-signing (the fixed
# certificate, 0700/0600, same files as on 222; see Scripts/sign-app.sh) and
# packages the DMG. The DMG and its .sha256 land in /mnt/hdd/imirror/dist and,
# unless IMIRROR_BEPASTY=0, are shared on the LAN bepasty (kept 1 week).
set -euo pipefail
cd "$(dirname "$0")/.."
host=${IMIRROR_BUILD_HOST:-10.10.10.202}
out=${IMIRROR_DIST_DIR:-/mnt/hdd/imirror/dist}
remote=imirror-build
version=$(sed -n '/CFBundleShortVersionString/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' Resources/Info.plist)
dmg="iMirror-$version-macOS-universal.dmg"

# Start from a clean copy each time, keeping the OpenSSL and build caches.
ssh -o BatchMode=yes "$host" "mkdir -p ~/$remote/src && cd ~/$remote/src && find . -mindepth 1 -maxdepth 1 ! -name build ! -name .dependencies ! -name dist -exec rm -rf {} +"
git ls-files -z --cached --others --exclude-standard \
    | rsync -a --from0 --files-from=- ./ "$host:$remote/src/"

ssh -o BatchMode=yes "$host" "zsh -s" <<REMOTE
set -euo pipefail
cd ~/$remote
[[ -f ~/.config/imirror-signing/imirror-signing.p12 ]] || { print -u2 'Mac mini 上没有 ~/.config/imirror-signing 证书'; exit 1; }
if [[ ! -x venv/bin/dmgbuild ]]; then
    python3 -m venv venv
    venv/bin/pip install --quiet dmgbuild==1.6.7
fi
export IMIRROR_PYTHON="\$HOME/$remote/venv/bin/python3"
cd src
# The Command Line Tools on the Mac mini lack the SwiftUI macro plugins; use Xcode's toolchain.
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
rm -rf dist && mkdir -p dist/arm64 dist/x86_64 dist/universal
: > ../build.log
step() { "\$@" >> ../build.log 2>&1 || { tail -40 ../build.log >&2; exit 1; } }
step env IMIRROR_ARCH=arm64 ./build.sh test
step ditto build/iMirror.app dist/arm64/iMirror.app
step env IMIRROR_ARCH=x86_64 ./build.sh build
step ditto build/iMirror.app dist/x86_64/iMirror.app
grep -E '✓|passed|通过' ../build.log | tail -8 || true

ditto dist/arm64/iMirror.app dist/universal/iMirror.app
for binary in Contents/MacOS/iMirror Contents/Frameworks/libcrypto.3.dylib; do
    lipo -create "dist/arm64/iMirror.app/\$binary" "dist/x86_64/iMirror.app/\$binary" -output "dist/universal/iMirror.app/\$binary"
    [[ "\$(lipo -archs "dist/universal/iMirror.app/\$binary")" == "x86_64 arm64" ]] || { print -u2 "\$binary 不是通用二进制"; exit 1; }
done
# lipo invalidates the per-architecture signatures.
Scripts/sign-app.sh dist/universal/iMirror.app
Scripts/make-dmg.sh dist/universal/iMirror.app "dist/$dmg" >/dev/null
(cd dist && shasum -a 256 "$dmg" > "$dmg.sha256")
REMOTE

mkdir -p "$out"
scp -q "$host:$remote/src/dist/$dmg" "$host:$remote/src/dist/$dmg.sha256" "$out/"
(cd "$out" && [[ $(sha256sum "$dmg" | cut -d' ' -f1) == $(cut -d' ' -f1 "$dmg.sha256") ]]) \
    || { echo "checksum mismatch" >&2; exit 1; }
echo "$out/$dmg"
if [[ ${IMIRROR_BEPASTY:-1} != 0 ]]; then
    bepasty=${IMIRROR_BEPASTY_SCRIPT:-$HOME/.agents/skills/bepasty/scripts/bepasty.sh}
    upload=$(bash "$bepasty" --lifetime "${IMIRROR_BEPASTY_LIFETIME:-1w}" "$out/$dmg" 2>&1)
    grep -q 'successfully uploaded' <<<"$upload" || { echo "bepasty upload failed:" >&2; echo "$upload" >&2; exit 1; }
    grep -Eo 'https?://[^ ]+' <<<"$upload" | tail -1
fi
