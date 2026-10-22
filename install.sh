#!/usr/bin/env bash
# Build iMirror and install it into /Applications (or IMIRROR_INSTALL_DIR).
set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR
readonly BUNDLE_ID="com.hhwyz.imirror"
# 1.3.0 之前的包名，覆盖安装旧版时同样认作 iMirror。
readonly LEGACY_BUNDLE_ID="com.erniu.imirror"
readonly INSTALL_DIR="${IMIRROR_INSTALL_DIR:-/Applications}"
readonly SOURCE_APP="$PROJECT_DIR/build/iMirror.app"
readonly TARGET_APP="$INSTALL_DIR/iMirror.app"

open_after_install=true
for argument in "$@"; do
    case "$argument" in
        --no-open) open_after_install=false ;;
        -h|--help)
            printf '用法：%s [--no-open]\n' "$0"
            printf '编译 iMirror 并安装到 %s，完成后自动启动。\n' "$INSTALL_DIR"
            exit 0
            ;;
        *)
            printf '未知参数：%s\n' "$argument" >&2
            exit 2
            ;;
    esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
    printf 'iMirror 是 macOS 应用，请在 Mac 上运行 bash install.sh。\n' >&2
    exit 1
fi

zsh "$PROJECT_DIR/build.sh" build

bundle_id_of() {
    /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist" 2>/dev/null || true
}

installed_bundle_id=""
[[ -e "$TARGET_APP" ]] && installed_bundle_id="$(bundle_id_of "$TARGET_APP")"
if [[ -e "$TARGET_APP" && "$installed_bundle_id" != "$BUNDLE_ID" && "$installed_bundle_id" != "$LEGACY_BUNDLE_ID" ]]; then
    printf '%s 不是 iMirror，为避免误删已停止安装。\n' "$TARGET_APP" >&2
    exit 1
fi

# Replacing the bundle under a running process can crash it; ask it to quit first.
if pgrep -x iMirror >/dev/null 2>&1; then
    printf '正在退出运行中的 iMirror…\n'
    for running_id in "$BUNDLE_ID" "$LEGACY_BUNDLE_ID"; do
        osascript -e "tell application id \"$running_id\" to quit" >/dev/null 2>&1 || true
    done
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x iMirror >/dev/null 2>&1 || break
        sleep 0.5
    done
    pkill -x iMirror 2>/dev/null || true
fi

install_parent="$INSTALL_DIR"
while [[ ! -e "$install_parent" ]]; do
    install_parent="$(dirname -- "$install_parent")"
done
if [[ -w "$install_parent" ]] && { [[ ! -e "$TARGET_APP" ]] || [[ -w "$TARGET_APP" ]]; }; then
    needs_sudo=false
else
    needs_sudo=true
    printf '写入 %s 需要管理员权限，请输入本机登录密码。\n' "$INSTALL_DIR"
fi

as_installer() {
    if [[ "$needs_sudo" == true ]]; then
        sudo "$@"
    else
        "$@"
    fi
}

as_installer mkdir -p "$INSTALL_DIR"

# ditto merges into an existing bundle, so remove the old copy to avoid stale files.
as_installer rm -rf -- "$TARGET_APP"
as_installer ditto "$SOURCE_APP" "$TARGET_APP"
# Prompt Finder and the Dock to pick up a changed icon.
as_installer touch "$TARGET_APP"
codesign --verify --deep --strict "$TARGET_APP"

printf '已安装：%s\n' "$TARGET_APP"
printf '如果之前在 build 目录运行时开启过“登录时启动”，请在设置中关闭后重新开启，使其指向这里的副本。\n'

if [[ "$open_after_install" == true ]]; then
    open "$TARGET_APP"
fi
