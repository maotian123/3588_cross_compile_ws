#!/bin/bash
# Extract RK3588 sysroot over SSH using paramiko.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$SCRIPT_DIR")"

HOST=""
USER=""
PASSWORD=""
OUTPUT_PATH="$WORKSPACE_DIR/arch/rk3588_sysroot.tar.gz"

usage() {
    echo "Usage: $0 --host <IP> --user <USER> --password <PASS> [--output <path>]"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host) HOST="$2"; shift 2 ;;
        --user) USER="$2"; shift 2 ;;
        --password) PASSWORD="$2"; shift 2 ;;
        --output) OUTPUT_PATH="$2"; shift 2 ;;
        *) usage ;;
    esac
done

if [ -z "$HOST" ] || [ -z "$USER" ] || [ -z "$PASSWORD" ]; then
    usage
fi

python3 -u "$SCRIPT_DIR/rk3588_extract_sysroot.py" \
    --host "$HOST" \
    --user "$USER" \
    --password "$PASSWORD" \
    --output "$OUTPUT_PATH"
