#!/bin/zsh
set -euo pipefail

readonly PROJECT_DIR="${0:A:h:h}"
readonly VERSION="3.6.3"
readonly SHA256="243a86649cf6f23eeb6a2ff2456e09e5d77dd9018a54d3d96b0c6bdd6ba6c7f1"
readonly MINIMUM_MACOS="${1:?缺少最低 macOS 版本}"
readonly TARGET_ARCH="${2:?缺少目标架构}"
readonly DEPENDENCIES_DIR="$PROJECT_DIR/.dependencies"
readonly PREFIX="$DEPENDENCIES_DIR/openssl-$VERSION-macos-$MINIMUM_MACOS-$TARGET_ARCH"
readonly ARCHIVE="$DEPENDENCIES_DIR/openssl-$VERSION.tar.gz"
readonly SOURCE_DIR="$DEPENDENCIES_DIR/openssl-$VERSION-macos-$MINIMUM_MACOS-$TARGET_ARCH-source"
readonly LIBCRYPTO="$PREFIX/lib/libcrypto.3.dylib"

if [[ -f "$LIBCRYPTO" ]]; then
    print "$PREFIX"
    exit 0
fi

case "$TARGET_ARCH" in
    arm64) readonly CONFIGURE_TARGET="darwin64-arm64-cc" ;;
    x86_64) readonly CONFIGURE_TARGET="darwin64-x86_64-cc" ;;
    *) print -u2 "不支持的架构：$TARGET_ARCH"; exit 1 ;;
esac

# OpenSSL invokes the compiler directly rather than through xcrun. Darwin clang
# uses SDKROOT as -isysroot for compilation and -syslibroot for linking.
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
CC="$(xcrun --sdk macosx --find clang)"
BUILD_JOBS="$(sysctl -n hw.logicalcpu)"
readonly SDKROOT CC BUILD_JOBS
if [[ "$SDKROOT" != /* || "$SDKROOT" == "/" || ! -d "$SDKROOT" ]]; then
    print -u2 "无效的 macOS SDK 路径：$SDKROOT"
    exit 1
fi
if [[ ! -x "$CC" ]]; then
    print -u2 "找不到可执行的 macOS clang：$CC"
    exit 1
fi

mkdir -p "$DEPENDENCIES_DIR"
if [[ ! -f "$ARCHIVE" ]]; then
    print -u2 "首次构建：下载 OpenSSL $VERSION 源码（约 53 MB）…"
    curl --fail --location --retry 3 --continue-at - \
        --output "$ARCHIVE.part" \
        "https://github.com/openssl/openssl/releases/download/openssl-$VERSION/openssl-$VERSION.tar.gz"
    mv "$ARCHIVE.part" "$ARCHIVE"
fi

ACTUAL_SHA256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
readonly ACTUAL_SHA256
if [[ "$ACTUAL_SHA256" != "$SHA256" ]]; then
    print -u2 "OpenSSL 源码校验失败：$ARCHIVE"
    rm -f -- "$ARCHIVE"
    exit 1
fi

rm -rf -- "$SOURCE_DIR"
mkdir -p "$SOURCE_DIR"
tar -xzf "$ARCHIVE" --strip-components=1 -C "$SOURCE_DIR"

print -u2 "为 macOS $MINIMUM_MACOS 编译 OpenSSL $VERSION…"
(
    cd "$SOURCE_DIR"
    export CC SDKROOT
    export MACOSX_DEPLOYMENT_TARGET="$MINIMUM_MACOS"
    ./Configure "$CONFIGURE_TARGET" \
        shared no-tests no-apps no-docs \
        --prefix="$PREFIX" \
        --openssldir="$PREFIX/ssl"
    make -j"$BUILD_JOBS" build_libs
    make install_dev install_runtime
) >&2

rm -rf -- "$SOURCE_DIR"
print "$PREFIX"
