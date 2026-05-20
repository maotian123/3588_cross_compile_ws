#!/bin/bash
# Build loc_map inside the RK3588 fat cross-compile image.

set -euo pipefail

CROSS_WS="${RK3588_IMAGE_WORKSPACE:-/opt/rk3588/cross_compile_ws}"
LOC_MAP_SRC="${LOC_MAP_SRC:-$CROSS_WS/src/loc_map}"
BUILD_JOBS="${RK3588_BUILD_JOBS:-1}"

if [ ! -d "$LOC_MAP_SRC" ]; then
    echo "ERROR: LOC_MAP_SRC does not exist: $LOC_MAP_SRC" >&2
    echo "Mount loc_map to $CROSS_WS/src/loc_map or set LOC_MAP_SRC=/path/to/loc_map" >&2
    exit 1
fi

mkdir -p "$CROSS_WS/src"
if [ "$LOC_MAP_SRC" != "$CROSS_WS/src/loc_map" ]; then
    rm -rf "$CROSS_WS/src/loc_map"
    ln -s "$LOC_MAP_SRC" "$CROSS_WS/src/loc_map"
fi

if [ ! -f "$CROSS_WS/cross_compile_env.sh" ]; then
    echo "ERROR: missing $CROSS_WS/cross_compile_env.sh; image was not prepared correctly" >&2
    exit 1
fi

source "$CROSS_WS/cross_compile_env.sh"

"$CROSS_WS/script/check_prereqs.sh"
RK3588_BUILD_JOBS="$BUILD_JOBS" "$CROSS_WS/script/compile.sh" "$@"
