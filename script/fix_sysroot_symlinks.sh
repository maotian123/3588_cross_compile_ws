#!/bin/bash
# 修复 sysroot 中的绝对符号链接，转换为相对路径

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SYSROOT_PATH="${1:-}"

if [ -z "$SYSROOT_PATH" ]; then
    print_error "用法: $0 <sysroot_path>"
    exit 1
fi

if [ ! -d "$SYSROOT_PATH" ]; then
    print_error "目录不存在: $SYSROOT_PATH"
    exit 1
fi

# 转为绝对路径
SYSROOT_PATH="$(cd "$SYSROOT_PATH" && pwd)"

print_info "修复 sysroot 符号链接: $SYSROOT_PATH"

if command -v symlinks &> /dev/null; then
    print_info "使用 symlinks 工具修复..."
    symlinks -cr "$SYSROOT_PATH"
else
    print_info "symlinks 工具不可用，使用内置实现..."
    FIXED=0
    SKIPPED=0
    while IFS= read -r link; do
        target=$(readlink "$link")
        if [[ "$target" == /* ]]; then
            link_dir=$(dirname "$link")
            if [[ "$target" == "$SYSROOT_PATH"/* ]]; then
                target_abs="$target"
            else
                target_abs="${SYSROOT_PATH}${target}"
            fi
            new_target=$(python3 -c "import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))" "$target_abs" "$link_dir")
            ln -snf "$new_target" "$link"
            ((FIXED++)) || true
        else
            ((SKIPPED++)) || true
        fi
    done < <(find "$SYSROOT_PATH" -type l)
    print_info "修复完成: 已修复 $FIXED, 已跳过 $SKIPPED"
fi

# 验证
print_info "验证符号链接..."
TOTAL=$(find "$SYSROOT_PATH" -type l | wc -l)
ABSOLUTE=0
DANGLING=0
DANGLING_LIST=""

while IFS= read -r link; do
    target=$(readlink "$link")
    if [[ "$target" == /* ]]; then
        ((ABSOLUTE++)) || true
    fi
    if [ ! -e "$link" ]; then
        ((DANGLING++)) || true
        if [ $DANGLING -le 20 ]; then
            DANGLING_LIST="${DANGLING_LIST}\n  $link -> $target"
        fi
    fi
done < <(find "$SYSROOT_PATH" -type l)

print_info "=========================================="
print_info "符号链接修复统计"
print_info "=========================================="
print_info "  总符号链接数: $TOTAL"
print_info "  残留绝对链接: $ABSOLUTE"
print_info "  悬空链接: $DANGLING"

if [ $ABSOLUTE -gt 0 ]; then
    print_warn "仍有 $ABSOLUTE 个绝对符号链接"
fi

if [ $DANGLING -gt 0 ]; then
    print_warn "发现 $DANGLING 个悬空符号链接 (前 20 个):"
    echo -e "$DANGLING_LIST"
fi

print_info "完成"

# Cross-toolchain compatibility fix:
# Ubuntu 20.04 sysroots keep arch-specific headers under usr/include/aarch64-linux-gnu/.
# Some aarch64 cross toolchains look for sys/, bits/, and gnu/ under usr/include, so create
# compatible links without changing source headers.
ARCH_INC="$SYSROOT_PATH/usr/include/aarch64-linux-gnu"
if [ -d "$ARCH_INC" ]; then
    print_info "修复 aarch64 工具链 arch-specific 头文件路径..."
    find "$ARCH_INC" -mindepth 1 -name "*.h" | while read f; do
        relpath="${f#$ARCH_INC/}"
        target="$SYSROOT_PATH/usr/include/$relpath"
        mkdir -p "$(dirname "$target")"
        if [ ! -e "$target" ]; then
            rel_target=$(python3 -c "import os, sys; print(os.path.relpath(sys.argv[1], os.path.dirname(sys.argv[2])))" "$f" "$target")
            ln -sf "$rel_target" "$target"
        fi
    done
fi

# Debian/Ubuntu cross GCC may read linker scripts from its own
# usr/aarch64-linux-gnu/lib directory. Those scripts reference
# /usr/aarch64-linux-gnu/lib under the active --sysroot, so provide the
# compatible layout for target sysroots that only have usr/lib/aarch64-linux-gnu.
CROSS_COMPAT_DIR="$SYSROOT_PATH/usr/aarch64-linux-gnu"
if [ -d "$SYSROOT_PATH/usr/lib/aarch64-linux-gnu" ]; then
    print_info "修复 aarch64 GCC 兼容库路径..."
    mkdir -p "$CROSS_COMPAT_DIR"
    if [ ! -e "$CROSS_COMPAT_DIR/lib" ]; then
        ln -s ../lib/aarch64-linux-gnu "$CROSS_COMPAT_DIR/lib"
    fi
fi
