#!/bin/bash
# RK3588 CMake cross compile entrypoint.
#
# Usage:
#   ./script/compile.sh
#   ./script/compile.sh --package LocUtils
#   ./script/compile.sh --package msf_loc --target web_ui_websocket_node
#   ./script/compile.sh --package slam_ui
#   ./script/compile.sh --cmake-args -DNAME=value

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$SCRIPT_DIR")"
SRC_DIR="$WORKSPACE_DIR/src/loc_map"
BUILD_DIR="$WORKSPACE_DIR/build"
INSTALL_DIR="$WORKSPACE_DIR/install"
TOOLCHAIN_FILE="$WORKSPACE_DIR/cmake/toolchain.cmake"
BUILD_JOBS="${RK3588_BUILD_JOBS:-2}"
USE_PREBUILT_LOCUTILS="${RK3588_USE_PREBUILT_LOCUTILS:-0}"
PREBUILT_LOCUTILS_SCRIPT="$WORKSPACE_DIR/script/locutils_prebuilt.sh"

if [ -z "${RK3588_CROSS_COMPILE_SYSROOT:-}" ]; then
    print_error "RK3588_CROSS_COMPILE_SYSROOT is not set"
    print_error "Run: source $WORKSPACE_DIR/cross_compile_env.sh"
    exit 1
fi

if [ ! -d "$RK3588_CROSS_COMPILE_SYSROOT" ] || [ -z "$(ls -A "$RK3588_CROSS_COMPILE_SYSROOT" 2>/dev/null)" ]; then
    print_error "Sysroot missing or empty: $RK3588_CROSS_COMPILE_SYSROOT"
    exit 1
fi

if [ ! -d "$SRC_DIR" ]; then
    print_error "loc_map source not found: $SRC_DIR"
    print_error "For local testing run: make link-local-loc-map"
    exit 1
fi

SYSROOT_ROS_DIR="$RK3588_CROSS_COMPILE_SYSROOT/opt/ros/noetic"
if [ ! -d "$SYSROOT_ROS_DIR" ]; then
    print_error "ROS1 Noetic not found in sysroot: $SYSROOT_ROS_DIR"
    exit 1
fi

if ! command -v aarch64-linux-gnu-g++ >/dev/null 2>&1 \
   && ! command -v aarch64-buildroot-linux-gnu-g++ >/dev/null 2>&1 \
   && [ ! -x "$WORKSPACE_DIR/toolchain/bin/aarch64-linux-gnu-g++" ] \
   && [ ! -x "$WORKSPACE_DIR/toolchain/bin/aarch64-buildroot-linux-gnu-g++" ]; then
    print_error "No aarch64 g++ found. Install one or put it in $WORKSPACE_DIR/toolchain/bin"
    exit 1
fi

# Do not source target ROS setup.bash on the x86 host/container.  The cross
# build uses explicit CMAKE_PREFIX_PATH/CATKIN_PREFIX_PATH below; sourcing the
# target setup script can terminate the shell in minimal CI images.

FIX_PCL_SCRIPT="$WORKSPACE_DIR/script/fix_pcl_ros_paths.sh"
if [ -x "$FIX_PCL_SCRIPT" ]; then
    print_info "Fixing sysroot CMake/pkg-config paths..."
    "$FIX_PCL_SCRIPT" "$RK3588_CROSS_COMPILE_SYSROOT"
fi

TARGET_PACKAGE=""
BUILD_TARGET=""
USER_CMAKE_ARGS=()
USER_BUILD_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --package)
            TARGET_PACKAGE="${2:-}"
            shift 2
            ;;
        --target)
            BUILD_TARGET="${2:-}"
            shift 2
            ;;
        --cmake-args)
            shift
            while [[ $# -gt 0 ]]; do
                if [[ "$1" =~ ^-- ]] && [[ ! "$1" =~ ^-D ]]; then
                    break
                fi
                USER_CMAKE_ARGS+=("$1")
                shift
            done
            ;;
        --)
            shift
            USER_BUILD_ARGS+=("$@")
            break
            ;;
        *)
            USER_BUILD_ARGS+=("$1")
            shift
            ;;
    esac
done

declare -A PKG_PATHS
PKG_PATHS[LocUtils]="$SRC_DIR/LocUtils"
PKG_PATHS[msf_loc]="$SRC_DIR/msf_loc"
PKG_PATHS[slam_ui]="$SRC_DIR/slam_ui/slam_ui"

resolve_targets() {
    if [ -n "$TARGET_PACKAGE" ]; then
        if [ -z "${PKG_PATHS[$TARGET_PACKAGE]:-}" ]; then
            print_error "Unknown package: $TARGET_PACKAGE"
            print_error "Valid packages: LocUtils, msf_loc, slam_ui"
            exit 1
        fi
        echo "$TARGET_PACKAGE"
    else
        echo "LocUtils"
        echo "msf_loc"
        echo "slam_ui"
    fi
}

mkdir -p "$BUILD_DIR" "$INSTALL_DIR"

CMAKE_PREFIX_PATHS=(
    "$INSTALL_DIR"
    "$RK3588_CROSS_COMPILE_SYSROOT/opt/ros/noetic"
    "$RK3588_CROSS_COMPILE_SYSROOT/usr"
    "$RK3588_CROSS_COMPILE_SYSROOT/usr/local"
)
export CATKIN_PREFIX_PATH="$RK3588_CROSS_COMPILE_SYSROOT/opt/ros/noetic"
export CMAKE_PREFIX_PATH
CMAKE_PREFIX_PATH=$(IFS=:; echo "${CMAKE_PREFIX_PATHS[*]}")
export LD_LIBRARY_PATH="$INSTALL_DIR/lib:$RK3588_CROSS_COMPILE_SYSROOT/usr/local/lib:$RK3588_CROSS_COMPILE_SYSROOT/opt/ros/noetic/lib:${LD_LIBRARY_PATH:-}"
export PATH="$WORKSPACE_DIR/toolchain/bin:$PATH"

COMMON_CMAKE_ARGS=(
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE"
    -DCMAKE_BUILD_TYPE=Release
    -DBUILD_TESTING=OFF
)

copy_sysroot_runtime_lib() {
    local src="$1"
    local dst="$INSTALL_DIR/lib/$(basename "$src")"

    mkdir -p "$INSTALL_DIR/lib"
    if [ -L "$src" ]; then
        local target_abs
        target_abs="$(readlink -f "$src" 2>/dev/null || true)"
        if [ -n "$target_abs" ] && [ -f "$target_abs" ]; then
            local target_base
            target_base="$(basename "$target_abs")"
            if [ "$target_base" = "$(basename "$src")" ]; then
                rm -f "$dst"
                cp -aL "$src" "$dst"
            else
                if [ ! -e "$INSTALL_DIR/lib/$target_base" ]; then
                    cp -aL "$target_abs" "$INSTALL_DIR/lib/$target_base"
                fi
                ln -snf "$target_base" "$dst"
            fi
        else
            rm -f "$dst"
            cp -a "$src" "$dst"
        fi
    else
        rm -f "$dst"
        cp -a "$src" "$dst"
    fi
}

copy_external_gtsam_runtime_libs() {
    local copied=0
    local lib_dirs=(
        "$RK3588_CROSS_COMPILE_SYSROOT/usr/lib/aarch64-linux-gnu"
        "$RK3588_CROSS_COMPILE_SYSROOT/lib/aarch64-linux-gnu"
    )
    local patterns=(
        "libgtsam.so*"
        "libmetis-gtsam.so*"
    )

    for lib_dir in "${lib_dirs[@]}"; do
        [ -d "$lib_dir" ] || continue
        for pattern in "${patterns[@]}"; do
            shopt -s nullglob
            local files=("$lib_dir"/$pattern)
            shopt -u nullglob
            for file in "${files[@]}"; do
                copy_sysroot_runtime_lib "$file"
                copied=1
            done
        done
    done

    if [ "$copied" = "1" ]; then
        print_info "Copied external GTSAM runtime libs to $INSTALL_DIR/lib"
    else
        print_warn "External GTSAM runtime libs were not found in sysroot"
    fi
}

restore_prebuilt_locutils_if_enabled() {
    case "$USE_PREBUILT_LOCUTILS" in
        1|true|TRUE|yes|YES|on|ON)
            ;;
        *)
            return 1
            ;;
    esac

    if [ ! -x "$PREBUILT_LOCUTILS_SCRIPT" ]; then
        print_warn "Prebuilt LocUtils script is missing or not executable: $PREBUILT_LOCUTILS_SCRIPT"
        return 1
    fi

    if "$PREBUILT_LOCUTILS_SCRIPT" restore "$SRC_DIR" "$INSTALL_DIR"; then
        print_info "Using prebuilt LocUtils install from Docker image"
        return 0
    fi

    print_warn "Prebuilt LocUtils is unavailable or stale; building LocUtils from source"
    return 1
}

configure_and_build() {
    local pkg="$1"
    local source_dir="${PKG_PATHS[$pkg]}"
    local pkg_build_dir="$BUILD_DIR/$pkg"
    local args=("${COMMON_CMAKE_ARGS[@]}")

    if [ ! -f "$source_dir/CMakeLists.txt" ]; then
        print_error "CMakeLists.txt not found for $pkg: $source_dir"
        exit 1
    fi

    if [ "$pkg" = "LocUtils" ] && restore_prebuilt_locutils_if_enabled; then
        return 0
    fi

    if [ "$pkg" != "LocUtils" ] && [ ! -f "$INSTALL_DIR/share/LocUtils/locutils-config.cmake" ]; then
        restore_prebuilt_locutils_if_enabled || true
    fi

    case "$pkg" in
        LocUtils)
            args+=(
                -DCOMPILE_METHOD=CATKIN
                -DUSE_CROSS_COMPILE=OFF
                -DUSE_INTERNAL_LIBS=ON
                -DUSE_INTERNAL_GTSAM=OFF
            )
            ;;
        msf_loc)
            args+=(
                -DCOMPILE_METHOD=CATKIN
                -DLocUtils_DIR="$INSTALL_DIR/share/LocUtils"
            )
            ;;
        slam_ui)
            args+=(
                -DLocUtils_DIR="$INSTALL_DIR/share/LocUtils"
            )
            ;;
    esac

    args+=("${USER_CMAKE_ARGS[@]}")

    print_info "-------------------------------------------"
    print_info "Package: $pkg"
    print_info "Source: $source_dir"
    print_info "Build: $pkg_build_dir"
    print_info "CMAKE_PREFIX_PATH: $CMAKE_PREFIX_PATH"
    print_info "CMake args: ${args[*]}"

    cmake -S "$source_dir" -B "$pkg_build_dir" -G "Unix Makefiles" \
        -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
        "${args[@]}"

    local build_cmd=(cmake --build "$pkg_build_dir" -j"$BUILD_JOBS")
    if [ -n "$BUILD_TARGET" ]; then
        build_cmd+=(--target "$BUILD_TARGET")
    fi
    build_cmd+=("${USER_BUILD_ARGS[@]}")

    print_info "Build command: ${build_cmd[*]}"
    "${build_cmd[@]}"

    if [ -z "$BUILD_TARGET" ] || [ "$BUILD_TARGET" = "install" ] || [ "$pkg" = "LocUtils" ]; then
        print_info "Installing $pkg to $INSTALL_DIR"
        cmake --install "$pkg_build_dir"
        if [ "$pkg" = "LocUtils" ]; then
            copy_external_gtsam_runtime_libs
        fi
    elif [ "$pkg" = "msf_loc" ] || [ "$pkg" = "slam_ui" ]; then
        print_info "Skipping install for targeted downstream build: $pkg"
    fi
}

print_info "RK3588 sysroot: $RK3588_CROSS_COMPILE_SYSROOT"
print_info "loc_map source: $SRC_DIR"

while IFS= read -r pkg; do
    configure_and_build "$pkg"
done < <(resolve_targets)

print_info "Build sequence finished"
