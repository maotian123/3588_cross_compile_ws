#!/bin/bash
# Unpack RK3588 sysroot and generate cross_compile_env.sh.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

print_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$SCRIPT_DIR")"
ARCH_DIR="$WORKSPACE_DIR/arch"
SYSROOT_BASE_DIR="$WORKSPACE_DIR/sysroot_base"
SYSROOT_TARBALL="$ARCH_DIR/rk3588_sysroot.tar.gz"
ENV_FILE="$WORKSPACE_DIR/cross_compile_env.sh"

if [ ! -f "$SYSROOT_TARBALL" ]; then
    print_error "sysroot tarball not found: $SYSROOT_TARBALL"
    print_error "Run: RK3588_PASSWORD=123 make extract-sysroot"
    exit 1
fi

print_info "Unpacking sysroot to: $SYSROOT_BASE_DIR"
rm -rf "$SYSROOT_BASE_DIR"
mkdir -p "$SYSROOT_BASE_DIR"
tar -xzf "$SYSROOT_TARBALL" -C "$SYSROOT_BASE_DIR" --warning=no-file-changed

print_info "Fixing sysroot symlinks..."
bash "$SCRIPT_DIR/fix_sysroot_symlinks.sh" "$SYSROOT_BASE_DIR"

cat > "$ENV_FILE" << EOF_ENV
#!/bin/bash
# RK3588 cross compile environment. Source this file before building.

export RK3588_CROSS_COMPILE_SYSROOT="$SYSROOT_BASE_DIR"
export RK3588_WORKSPACE_DIR="$WORKSPACE_DIR"
export PATH="$WORKSPACE_DIR/toolchain/bin:\$PATH"
export RK3588_TOOLCHAIN_HOST_LIB="$WORKSPACE_DIR/toolchain_root/usr/lib/x86_64-linux-gnu"
export CMAKE_PREFIX_PATH="$WORKSPACE_DIR/install:$SYSROOT_BASE_DIR/opt/ros/noetic:$SYSROOT_BASE_DIR/usr:$SYSROOT_BASE_DIR/usr/local:\${CMAKE_PREFIX_PATH:-}"
export CATKIN_PREFIX_PATH="$SYSROOT_BASE_DIR/opt/ros/noetic"
export LD_LIBRARY_PATH="$WORKSPACE_DIR/toolchain_root/usr/lib/x86_64-linux-gnu:$WORKSPACE_DIR/install/lib:$SYSROOT_BASE_DIR/usr/local/lib:$SYSROOT_BASE_DIR/opt/ros/noetic/lib:\${LD_LIBRARY_PATH:-}"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT_BASE_DIR"
export PKG_CONFIG_LIBDIR="$SYSROOT_BASE_DIR/usr/lib/aarch64-linux-gnu/pkgconfig:$SYSROOT_BASE_DIR/usr/lib/pkgconfig:$SYSROOT_BASE_DIR/usr/share/pkgconfig:$SYSROOT_BASE_DIR/usr/local/lib/pkgconfig:$SYSROOT_BASE_DIR/opt/ros/noetic/lib/pkgconfig"

echo "[ENV] RK3588 sysroot: \$RK3588_CROSS_COMPILE_SYSROOT"
echo "[ENV] RK3588 cross compile environment ready"
EOF_ENV

chmod +x "$ENV_FILE"

print_info "Environment file written: $ENV_FILE"
print_info "Next: source $ENV_FILE"
