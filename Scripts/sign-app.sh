#!/bin/zsh
# Signs iMirror.app (the bundled libcrypto first, then the app).
#
# - IMIRROR_SIGN_IDENTITY set: that keychain identity with a timestamp and the
#   hardened runtime, for Developer ID distribution (see package-release.sh).
# - Otherwise, a fixed self-signed certificate from IMIRROR_SIGN_P12 and
#   IMIRROR_SIGN_P12_PASSWORD, by default ~/.config/imirror-signing/
#   {imirror-signing.p12,p12-password}. Its designated requirement
#   (identifier + certificate hash) stays the same across builds, so macOS
#   keeps the Local Network permission after an update. The certificate goes
#   into a throwaway keychain; the login keychain isn't touched.
# - Neither available: ad hoc. Every build is then a new identity to macOS.
#
# Usage: Scripts/sign-app.sh <iMirror.app>
set -euo pipefail

readonly APP_BUNDLE="${1:?用法：sign-app.sh <iMirror.app>}"
readonly LIBRARIES=("$APP_BUNDLE"/Contents/Frameworks/*.dylib(N))
readonly SIGNING_DIR="$HOME/.config/imirror-signing"

if [[ -n "${IMIRROR_SIGN_IDENTITY:-}" && "$IMIRROR_SIGN_IDENTITY" != "-" ]]; then
    for library in "${LIBRARIES[@]}"; do
        codesign --force --timestamp --options runtime --sign "$IMIRROR_SIGN_IDENTITY" "$library"
    done
    codesign --force --timestamp --options runtime --sign "$IMIRROR_SIGN_IDENTITY" "$APP_BUNDLE"
    codesign --verify --deep --strict "$APP_BUNDLE"
    exit 0
fi

p12="${IMIRROR_SIGN_P12:-}"
password="${IMIRROR_SIGN_P12_PASSWORD:-}"
if [[ -z "$p12" && -f "$SIGNING_DIR/imirror-signing.p12" && "${IMIRROR_SIGN_IDENTITY:-}" != "-" ]]; then
    p12="$SIGNING_DIR/imirror-signing.p12"
    [[ -n "$password" ]] || password="$(<"$SIGNING_DIR/p12-password")"
fi

if [[ -z "$p12" ]]; then
    print -u2 "warning: ad-hoc signature; macOS asks for Local Network access again after every update"
    for library in "${LIBRARIES[@]}"; do
        codesign --force --sign - "$library"
    done
    codesign --force --sign - "$APP_BUNDLE"
    codesign --verify --deep --strict "$APP_BUNDLE"
    exit 0
fi

if [[ -z "$password" ]]; then
    print -u2 "IMIRROR_SIGN_P12 需要同时设置 IMIRROR_SIGN_P12_PASSWORD"
    exit 1
fi

keychain_dir="$(mktemp -d)"
keychain="$keychain_dir/imirror-signing.keychain-db"
keychain_password="$(uuidgen)"
# set-key-partition-list only finds keys in a keychain on the user search list:
# add the throwaway keychain for the build, then restore the original list.
typeset -a search_list
search_list=("${(@f)$(security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"$//')}")
cleanup() {
    security list-keychains -d user -s "${search_list[@]}"
    security delete-keychain "$keychain" 2>/dev/null || true
    rm -rf -- "$keychain_dir"
}
trap cleanup EXIT

security create-keychain -p "$keychain_password" "$keychain"
security list-keychains -d user -s "$keychain" "${search_list[@]}"
security set-keychain-settings "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$p12" -k "$keychain" -P "$password" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain" >/dev/null
# Self-signed, so not "valid" for find-identity -v; codesign accepts it by hash.
identity="$(security find-identity -p codesigning "$keychain" | awk '/\)/ { print $2; exit }')"
if [[ -z "$identity" ]]; then
    print -u2 "$p12 里没有代码签名身份"
    exit 1
fi

# No hardened runtime: library validation would refuse the bundled libcrypto,
# because a self-signed certificate carries no Team ID.
for library in "${LIBRARIES[@]}"; do
    codesign --force --keychain "$keychain" --sign "$identity" "$library"
done
codesign --force --keychain "$keychain" --sign "$identity" "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
requirement="$(codesign --display --requirements - "$APP_BUNDLE" 2>&1 | sed -n 's/^designated => //p')"
if [[ "$requirement" != *'certificate root = H"'* ]]; then
    print -u2 "指定要求没有固定证书：$requirement"
    exit 1
fi
print "designated requirement: $requirement"
