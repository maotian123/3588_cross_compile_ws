#!/bin/bash
# Run loc_map inside the RK3588 fat cross-compile image.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$SCRIPT_DIR")"
IMAGE="${RK3588_DOCKER_IMAGE:-rk3588-cross:20.04}"
BUILD_JOBS="${RK3588_BUILD_JOBS:-1}"
CONTAINER_WS="${RK3588_CONTAINER_WS:-/opt/rk3588/cross_compile_ws}"
LOC_MAP_DIR="${LOC_MAP_DIR:-$WORKSPACE_DIR/src/loc_map}"
LOCAL_BUILD_DIR="${RK3588_DOCKER_BUILD_DIR:-$WORKSPACE_DIR/rk3588_build}"
LOCAL_INSTALL_DIR="${RK3588_DOCKER_INSTALL_DIR:-$WORKSPACE_DIR/rk3588_install}"

if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker is not installed or not in PATH" >&2
    exit 1
fi

LOC_MAP_REAL="$(readlink -f "$LOC_MAP_DIR" 2>/dev/null || true)"
if [ -z "$LOC_MAP_REAL" ] || [ ! -d "$LOC_MAP_REAL" ]; then
    echo "ERROR: loc_map source not found: $LOC_MAP_DIR" >&2
    echo "Set LOC_MAP_DIR=/path/to/loc_map or run make link-local-loc-map" >&2
    exit 1
fi

mkdir -p "$LOCAL_BUILD_DIR" "$LOCAL_INSTALL_DIR"

docker run --rm --init \
    -u "$(id -u):$(id -g)" \
    -v "$LOC_MAP_REAL:$CONTAINER_WS/src/loc_map" \
    -v "$LOCAL_BUILD_DIR:$CONTAINER_WS/build" \
    -v "$LOCAL_INSTALL_DIR:$CONTAINER_WS/install" \
    -w "$CONTAINER_WS" \
    -e RK3588_BUILD_JOBS="$BUILD_JOBS" \
    -e RK3588_USE_PREBUILT_LOCUTILS="${RK3588_USE_PREBUILT_LOCUTILS:-0}" \
    "$IMAGE" \
    rk3588-cross-build "$@"
