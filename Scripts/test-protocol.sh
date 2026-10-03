#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/imirror-protocol.XXXXXX")"
trap 'rm -rf -- "$TEST_DIR"' EXIT

CC="${CC:-cc}"
# Conventional build variables intentionally allow a list of compiler flags.
read -r -a extra_cppflags <<< "${CPPFLAGS:-}"
read -r -a extra_cflags <<< "${CFLAGS:-}"
read -r -a extra_ldflags <<< "${LDFLAGS:-}"
openssl_flags=()
if [[ -n "${IMIRROR_OPENSSL_PREFIX:-}" ]]; then
    openssl_flags+=("-I$IMIRROR_OPENSSL_PREFIX/include" "-L$IMIRROR_OPENSSL_PREFIX/lib")
elif command -v pkg-config >/dev/null 2>&1 && pkg-config --exists openssl; then
    read -r -a openssl_flags <<< "$(pkg-config --cflags --libs openssl)"
fi

sources=(
    "$PROJECT_DIR/AirPlay/aes.c"
    "$PROJECT_DIR/AirPlay/crypto/aes.c"
    "$PROJECT_DIR/AirPlay/crypto_openssl.c"
    "$PROJECT_DIR/AirPlay/ed25519/sha512.c"
    "$PROJECT_DIR/AirPlay/utils.c"
    "$PROJECT_DIR/AirPlay/http_request.c"
    "$PROJECT_DIR/AirPlay/llhttp/api.c"
    "$PROJECT_DIR/AirPlay/llhttp/http.c"
    "$PROJECT_DIR/AirPlay/llhttp/llhttp.c"
    "$PROJECT_DIR"/AirPlay/playfair/*.c
    "$PROJECT_DIR"/AirPlay/plist/*.c
)

"$CC" -std=gnu11 -O2 -fno-strict-aliasing -Wall -Wno-unused-parameter \
    -Wno-deprecated-declarations -Wno-format -DOPENSSL_API_COMPAT=0x10101000L \
    -I"$PROJECT_DIR/AirPlay" -I"$PROJECT_DIR/AirPlay/plist" \
    "${extra_cppflags[@]}" "${extra_cflags[@]}" "${openssl_flags[@]}" \
    "$PROJECT_DIR/Tests/ProtocolTests.c" "${sources[@]}" \
    "${extra_ldflags[@]}" -lcrypto -lm -o "$TEST_DIR/protocol-tests"
"$TEST_DIR/protocol-tests"
