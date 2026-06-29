#!/bin/bash
# Manage the prebuilt LocUtils install cached inside the RK3588 Docker image.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$SCRIPT_DIR")"
DEFAULT_SRC_DIR="$WORKSPACE_DIR/src/loc_map"
DEFAULT_INSTALL_DIR="$WORKSPACE_DIR/install"
PREBUILT_DIR="${RK3588_PREBUILT_LOCUTILS_DIR:-$WORKSPACE_DIR/prebuilt_locutils}"
MANIFEST_FILE="$PREBUILT_DIR/manifest.env"

print_info() { echo "[prebuilt-locutils] $*"; }
print_warn() { echo "[prebuilt-locutils] WARN: $*" >&2; }

usage() {
    cat <<EOF
Usage:
  $0 hash [loc_map_dir]
  $0 restore [loc_map_dir] [install_dir]
  $0 save <locutils_tree_hash> [source_ref] [install_dir]
  $0 status
EOF
}

content_hash_locutils() {
    local loc_map_dir="$1"
    local locutils_dir="$loc_map_dir/LocUtils"

    if [ ! -d "$locutils_dir" ]; then
        print_warn "LocUtils source not found: $locutils_dir"
        return 1
    fi

    (
        cd "$locutils_dir"
        find . \
            \( -path './.git' -o -path './.cache' -o -path './build' -o -path './build-*' \
               -o -path './install' -o -path './libs' -o -path './__pycache__' \) -prune \
            -o -type f -print0 \
            | LC_ALL=C sort -z \
            | xargs -0 sha256sum \
            | sha256sum \
            | awk '{print "sha256:" $1}'
    )
}

hash_locutils() {
    local loc_map_dir="${1:-$DEFAULT_SRC_DIR}"

    if git -C "$loc_map_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git -C "$loc_map_dir" config --global --add safe.directory "$loc_map_dir" >/dev/null 2>&1 || true
        if git -C "$loc_map_dir" rev-parse --verify HEAD:LocUtils >/dev/null 2>&1; then
            if git -C "$loc_map_dir" diff --quiet -- LocUtils \
               && [ -z "$(git -C "$loc_map_dir" ls-files -o --exclude-standard LocUtils)" ]; then
                git -C "$loc_map_dir" rev-parse HEAD:LocUtils
                return 0
            fi
        fi
    fi

    content_hash_locutils "$loc_map_dir"
}

quote_manifest_value() {
    local value="$1"
    value="${value//\'/\'\"\'\"\'}"
    printf "'%s'" "$value"
}

validate_install_dir() {
    local install_dir="$1"
    local missing=0
    local required_paths=(
        "$install_dir/share/LocUtils/locutils-config.cmake"
        "$install_dir/lib/libLocUtils.so"
        "$install_dir/include/LocUtils/srv/ros1/updateWaypoints.h"
    )

    for path in "${required_paths[@]}"; do
        if [ ! -e "$path" ]; then
            print_warn "missing required LocUtils install file: $path"
            missing=1
        fi
    done

    return "$missing"
}

save_prebuilt() {
    local locutils_tree_hash="$1"
    local source_ref="${2:-unknown}"
    local install_dir="${3:-$DEFAULT_INSTALL_DIR}"

    validate_install_dir "$install_dir"

    rm -rf "$PREBUILT_DIR/install"
    mkdir -p "$PREBUILT_DIR"
    rsync -a --delete "$install_dir/" "$PREBUILT_DIR/install/"

    {
        printf 'LOCUTILS_TREE_HASH=%s\n' "$(quote_manifest_value "$locutils_tree_hash")"
        printf 'LOCUTILS_SOURCE_REF=%s\n' "$(quote_manifest_value "$source_ref")"
        printf 'LOCUTILS_PREBUILT_AT=%s\n' "$(quote_manifest_value "$(date -u +'%Y-%m-%dT%H:%M:%SZ')")"
    } > "$MANIFEST_FILE"

    print_info "saved LocUtils prebuilt install: hash=$locutils_tree_hash source_ref=$source_ref"
}

restore_prebuilt() {
    local loc_map_dir="${1:-$DEFAULT_SRC_DIR}"
    local install_dir="${2:-$DEFAULT_INSTALL_DIR}"

    if [ ! -f "$MANIFEST_FILE" ]; then
        print_warn "manifest not found: $MANIFEST_FILE"
        return 2
    fi

    # shellcheck disable=SC1090
    source "$MANIFEST_FILE"

    local expected_hash="${LOCUTILS_TREE_HASH:-}"
    if [ -z "$expected_hash" ]; then
        print_warn "manifest missing LOCUTILS_TREE_HASH"
        return 2
    fi

    local current_hash
    current_hash="$(hash_locutils "$loc_map_dir")"
    if [ "$current_hash" != "$expected_hash" ]; then
        print_warn "hash mismatch: current=$current_hash prebuilt=$expected_hash"
        return 2
    fi

    validate_install_dir "$PREBUILT_DIR/install"

    mkdir -p "$install_dir"
    rsync -a --delete "$PREBUILT_DIR/install/" "$install_dir/"
    print_info "restored matching prebuilt LocUtils install: hash=$current_hash"
}

status_prebuilt() {
    if [ -f "$MANIFEST_FILE" ]; then
        cat "$MANIFEST_FILE"
    else
        print_warn "manifest not found: $MANIFEST_FILE"
        return 2
    fi
}

cmd="${1:-}"
case "$cmd" in
    hash)
        shift
        hash_locutils "${1:-$DEFAULT_SRC_DIR}"
        ;;
    restore)
        shift
        restore_prebuilt "${1:-$DEFAULT_SRC_DIR}" "${2:-$DEFAULT_INSTALL_DIR}"
        ;;
    save)
        shift
        if [ $# -lt 1 ]; then
            usage >&2
            exit 2
        fi
        save_prebuilt "$1" "${2:-unknown}" "${3:-$DEFAULT_INSTALL_DIR}"
        ;;
    status)
        status_prebuilt
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
