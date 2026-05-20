#!/bin/bash
# Check local prerequisites for RK3588 cross compilation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$SCRIPT_DIR")"
SYSROOT="${RK3588_CROSS_COMPILE_SYSROOT:-$WORKSPACE_DIR/sysroot_base}"
SOURCE_DIR="$WORKSPACE_DIR/src/loc_map"

STATUS=0

ok() { echo "[OK] $1"; }
warn() { echo "[WARN] $1"; }
fail() { echo "[FAIL] $1"; STATUS=1; }

if command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
    ok "Found aarch64-linux-gnu-gcc: $(command -v aarch64-linux-gnu-gcc)"
elif command -v aarch64-buildroot-linux-gnu-gcc >/dev/null 2>&1; then
    ok "Found aarch64-buildroot-linux-gnu-gcc: $(command -v aarch64-buildroot-linux-gnu-gcc)"
elif [ -x "$WORKSPACE_DIR/toolchain/bin/aarch64-linux-gnu-gcc" ] || [ -x "$WORKSPACE_DIR/toolchain/bin/aarch64-buildroot-linux-gnu-gcc" ]; then
    ok "Found workspace aarch64 GCC under toolchain/bin"
else
    fail "No aarch64 GCC found. Install gcc-aarch64-linux-gnu/g++-aarch64-linux-gnu or place a toolchain in $WORKSPACE_DIR/toolchain/bin"
fi

for tool in cmake make python3 pkg-config rsync; do
    if command -v "$tool" >/dev/null 2>&1; then
        ok "Found $tool: $(command -v "$tool")"
    else
        fail "Missing host tool: $tool"
    fi
done

for qt_tool in moc uic rcc; do
    if command -v "$qt_tool" >/dev/null 2>&1; then
        ok "Found Qt host tool $qt_tool: $(command -v "$qt_tool")"
    else
        warn "Missing Qt host tool $qt_tool. LocUtils/msf_loc may build, but slam_ui will not."
    fi
done

if python3 - <<'PY' >/dev/null 2>&1
import paramiko
PY
then
    ok "Python paramiko is available"
else
    fail "Python paramiko is missing; sysroot extraction script needs it"
fi

if [ -d "$SOURCE_DIR" ]; then
    ok "Found source: $SOURCE_DIR"
    for required in LocUtils/CMakeLists.txt msf_loc/CMakeLists.txt slam_ui/slam_ui/CMakeLists.txt; do
        if [ -f "$SOURCE_DIR/$required" ]; then
            ok "Found $required"
        else
            fail "Missing $SOURCE_DIR/$required"
        fi
    done
else
    fail "Source not found: $SOURCE_DIR. Run: make link-local-loc-map"
fi

if [ -d "$SYSROOT" ] && [ -n "$(ls -A "$SYSROOT" 2>/dev/null)" ]; then
    ok "Found sysroot: $SYSROOT"
    for required in opt/ros/noetic usr/include usr/lib/aarch64-linux-gnu lib/aarch64-linux-gnu; do
        if [ -e "$SYSROOT/$required" ]; then
            ok "Found sysroot/$required"
        else
            fail "Missing sysroot/$required"
        fi
    done
else
    warn "Sysroot not unpacked at $SYSROOT. Run: RK3588_PASSWORD=123 make extract-sysroot && make setup-sysroot"
fi

exit "$STATUS"
