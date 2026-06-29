#!/bin/bash
# Build an RK3588 Docker image with a matching LocUtils install baked in.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$SCRIPT_DIR")"

OUTPUT_IMAGE="${DOCKER_IMAGE:-registry.cn-hangzhou.aliyuncs.com/bit_robot_image/robot_images:rk3588-cross-20260528-gtsam2}"
BASE_IMAGE="${RK3588_BASE_DOCKER_IMAGE:-${OUTPUT_IMAGE}-toolchain-base}"
LOC_MAP_DIR="${LOC_MAP_DIR:-/home/user/loc_map_cicd}"
BUILD_JOBS="${RK3588_BUILD_JOBS:-2}"
PUSH_IMAGE="${RK3588_PUSH_IMAGE:-0}"
PREBUILT_DIR="${RK3588_PREBUILT_LOCUTILS_DIR:-/opt/rk3588/cross_compile_ws/prebuilt_locutils}"
CONTAINER_NAME="${RK3588_PREBUILD_CONTAINER:-rk3588-locutils-prebuild-$$}"

if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker is not installed or not in PATH" >&2
    exit 1
fi

LOC_MAP_REAL="$(readlink -f "$LOC_MAP_DIR" 2>/dev/null || true)"
if [ -z "$LOC_MAP_REAL" ] || [ ! -d "$LOC_MAP_REAL/LocUtils" ]; then
    echo "ERROR: loc_map source with LocUtils not found: $LOC_MAP_DIR" >&2
    exit 1
fi

if [ ! -f "$WORKSPACE_DIR/arch/rk3588_sysroot.tar.gz" ]; then
    echo "ERROR: missing $WORKSPACE_DIR/arch/rk3588_sysroot.tar.gz" >&2
    exit 1
fi

LOCUTILS_TREE_HASH="$("$SCRIPT_DIR/locutils_prebuilt.sh" hash "$LOC_MAP_REAL")"
SOURCE_REF="$(git -C "$LOC_MAP_REAL" rev-parse --short HEAD 2>/dev/null || echo unknown)"

echo "[prebuild-image] output image: $OUTPUT_IMAGE"
echo "[prebuild-image] base image: $BASE_IMAGE"
echo "[prebuild-image] loc_map source: $LOC_MAP_REAL"
echo "[prebuild-image] LocUtils hash: $LOCUTILS_TREE_HASH"
echo "[prebuild-image] source ref: $SOURCE_REF"

docker build -f "$WORKSPACE_DIR/docker/Dockerfile.rk3588_cross_compile" -t "$BASE_IMAGE" "$WORKSPACE_DIR"

docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
docker run --name "$CONTAINER_NAME" --init \
    -v "$LOC_MAP_REAL:/tmp/loc_map_src:ro" \
    -e RK3588_BUILD_JOBS="$BUILD_JOBS" \
    -e RK3588_PREBUILT_LOCUTILS_DIR="$PREBUILT_DIR" \
    -e PREBUILT_LOCUTILS_TREE="$LOCUTILS_TREE_HASH" \
    -e PREBUILT_LOCUTILS_SOURCE_REF="$SOURCE_REF" \
    "$BASE_IMAGE" \
    bash -lc 'LOC_MAP_SRC=/tmp/loc_map_src rk3588-cross-build --package LocUtils && /opt/rk3588/cross_compile_ws/script/locutils_prebuilt.sh save "$PREBUILT_LOCUTILS_TREE" "$PREBUILT_LOCUTILS_SOURCE_REF"'

docker commit \
    --change "ENV RK3588_PREBUILT_LOCUTILS_DIR=$PREBUILT_DIR" \
    --change "ENV RK3588_PREBUILT_LOCUTILS_TREE=$LOCUTILS_TREE_HASH" \
    "$CONTAINER_NAME" \
    "$OUTPUT_IMAGE"
docker rm "$CONTAINER_NAME" >/dev/null

docker image inspect "$OUTPUT_IMAGE" --format '[prebuild-image] built {{.RepoTags}} id={{.Id}} size={{.Size}}'

if [ "$PUSH_IMAGE" = "1" ] || [ "$PUSH_IMAGE" = "true" ]; then
    docker push "$OUTPUT_IMAGE"
fi
