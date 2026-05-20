#!/bin/bash
# Link src/loc_map to a local loc_map checkout for testing.

set -euo pipefail

LOCAL_LOC_MAP="${1:-/home/user/work_ws/loc_map}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$SCRIPT_DIR")"
LINK_PATH="$WORKSPACE_DIR/src/loc_map"

if [ ! -d "$LOCAL_LOC_MAP" ]; then
    echo "ERROR: local loc_map directory not found: $LOCAL_LOC_MAP"
    exit 1
fi

for required in LocUtils msf_loc slam_ui/slam_ui; do
    if [ ! -d "$LOCAL_LOC_MAP/$required" ]; then
        echo "ERROR: expected directory missing: $LOCAL_LOC_MAP/$required"
        exit 1
    fi
done

mkdir -p "$WORKSPACE_DIR/src"

if [ -L "$LINK_PATH" ]; then
    rm "$LINK_PATH"
elif [ -e "$LINK_PATH" ]; then
    echo "ERROR: $LINK_PATH exists and is not a symlink. Remove it manually before linking."
    exit 1
fi

ln -s "$LOCAL_LOC_MAP" "$LINK_PATH"
echo "Linked $LINK_PATH -> $LOCAL_LOC_MAP"
