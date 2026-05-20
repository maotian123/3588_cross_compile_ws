#!/bin/bash
# Fix hard-coded /usr paths in CMake/pkg-config files inside the RK3588 sysroot.

set -e

SYSROOT="${1:-${RK3588_CROSS_COMPILE_SYSROOT:-}}"

if [ -z "$SYSROOT" ]; then
    echo "ERROR: SYSROOT or RK3588_CROSS_COMPILE_SYSROOT not set"
    exit 1
fi

SHARE_DIR="$SYSROOT/opt/ros/noetic/share"
CMAKE_DIR="$SYSROOT/usr/lib/aarch64-linux-gnu/cmake"
USR_CMAKE_DIR="$SYSROOT/usr/lib/cmake"
LOCAL_CMAKE_DIR="$SYSROOT/usr/local/lib/cmake"
PKGCONFIG_DIRS=(
    "$SYSROOT/usr/share/pkgconfig"
    "$SYSROOT/usr/lib/pkgconfig"
    "$SYSROOT/usr/lib/aarch64-linux-gnu/pkgconfig"
    "$SYSROOT/usr/local/lib/pkgconfig"
)
DONE_MARKER="$SYSROOT/.cmake_pkgconfig_paths_fixed_v4"

EIGEN_CMAKE_DIR="$SYSROOT/usr/share/eigen3/cmake"
EIGEN_MACROS="$SYSROOT/usr/include/eigen3/Eigen/src/Core/util/Macros.h"

if [ -f "$DONE_MARKER" ] && [ -f "$EIGEN_CMAKE_DIR/Eigen3Config.cmake" ]; then
    echo "已经修复过，跳过..."
    exit 0
fi

if [ ! -d "$SHARE_DIR" ]; then
    echo "ERROR: $SHARE_DIR not found"
    exit 1
fi

echo "修复 ROS cmake 硬编码路径..."
echo "Sysroot: $SYSROOT"

TARGET_DIRS=("$SHARE_DIR" "$CMAKE_DIR")
if [ -d "$USR_CMAKE_DIR" ]; then
    TARGET_DIRS+=("$USR_CMAKE_DIR")
fi
if [ -d "$LOCAL_CMAKE_DIR" ]; then
    TARGET_DIRS+=("$LOCAL_CMAKE_DIR")
fi

TARGETS=$(grep -rlE '/usr/|/usr/local/|/opt/ros/noetic' "${TARGET_DIRS[@]}" 2>/dev/null | grep "\.cmake$" || true)
PC_TARGETS=$(grep -rlE -- '-I/usr/|-L/usr/|-I/usr/local/|-L/usr/local/|-I/opt/ros/noetic|-L/opt/ros/noetic' "${PKGCONFIG_DIRS[@]}" 2>/dev/null | grep "\.pc$" || true)

if [ -z "$TARGETS" ] && [ -z "$PC_TARGETS" ] && { [ ! -f "$EIGEN_MACROS" ] || [ -f "$EIGEN_CMAKE_DIR/Eigen3Config.cmake" ]; }; then
    echo "无需修复"
    touch "$DONE_MARKER"
    exit 0
fi

for f in $TARGETS; do
    echo "修复：$f"
    [ ! -f "${f}.bak" ] && cp "$f" "${f}.bak"
    python3 - "$f" "$SYSROOT" << 'PYTHON_SCRIPT'
import sys, re, os
path, sysroot = sys.argv[1], sys.argv[2]
with open(path, 'r') as f:
    c = f.read()
# Rewrite target-board absolute paths to paths inside the sysroot.  This covers
# ROS package configs that export /opt/ros/noetic and vendor configs under
# /usr/local/lib/cmake, not just /usr paths.
def prefix_sysroot(m):
    sep, prefix = m.group(1), m.group(2)
    start = m.start(2)
    if c[max(0, start - len(sysroot)):start] == sysroot:
        return sep + prefix
    return sep + sysroot + prefix

# Undo the v3 rewrite that incorrectly prefixed Qt variable-relative paths such
# as "${_qt5Core_install_prefix}/lib/..." inside sysrooted Qt CMake configs.
c = re.sub(r'(\$\{_qt5[A-Za-z0-9_]*_install_prefix\})' + re.escape(sysroot), r'\1', c)

# Rewrite only real absolute paths.  Do not match path fragments appended after
# CMake variables, e.g. "${_qt5Core_install_prefix}/lib/aarch64-linux-gnu".
c = re.sub(r'(^|[\s";(=])(/opt/ros/noetic|/usr/local|/usr/lib|/usr/include|/usr/share|/usr/bin|/usr|/lib)(?=/)', prefix_sysroot, c)
# 展开路径中的 .. (如 sysroot/usr/share/foo/cmake/../../../include -> sysroot/usr/include)
def normalize(m):
    return os.path.normpath(m.group(0))
c = re.sub(re.escape(sysroot) + r'/[^\s";]+', normalize, c)
with open(path, 'w') as f:
    f.write(c)
PYTHON_SCRIPT
done

for f in $PC_TARGETS; do
    echo "修复 pkg-config：$f"
    [ ! -f "${f}.bak" ] && cp "$f" "${f}.bak"
    python3 - "$f" "$SYSROOT" << 'PYTHON_SCRIPT'
import sys, re, os
path, sysroot = sys.argv[1], sys.argv[2]
with open(path, 'r') as f:
    c = f.read()
# pkg-config may be consumed by CMake without PKG_CONFIG_SYSROOT_DIR rewriting.
# Keep package-relative variables intact, but rewrite hard-coded absolute flags.
def prefix_flag(m):
    flag, path = m.group(1), m.group(2)
    return flag + path if path.startswith(sysroot) else flag + sysroot + path

c = re.sub(r'(-[IL])(/opt/ros/noetic|/usr/local|/usr/lib|/usr/include|/usr/share|/usr/bin|/usr|/lib)(?=/)', prefix_flag, c)
def normalize(m):
    return os.path.normpath(m.group(0))
c = re.sub(re.escape(sysroot) + r'/[^\s]+', normalize, c)
with open(path, 'w') as f:
    f.write(c)
PYTHON_SCRIPT
done

if [ -f "$EIGEN_MACROS" ] && [ ! -f "$EIGEN_CMAKE_DIR/Eigen3Config.cmake" ]; then
    echo "生成 Eigen3 CMake config：$EIGEN_CMAKE_DIR"
    mkdir -p "$EIGEN_CMAKE_DIR"
    python3 - "$EIGEN_MACROS" "$EIGEN_CMAKE_DIR" << 'PYTHON_SCRIPT'
import re
import sys
from pathlib import Path

macros_path = Path(sys.argv[1])
cmake_dir = Path(sys.argv[2])
text = macros_path.read_text()

def version_part(name):
    match = re.search(rf"#define\s+{name}\s+([0-9]+)", text)
    if not match:
        raise SystemExit(f"Cannot read {name} from {macros_path}")
    return match.group(1)

major = version_part("EIGEN_WORLD_VERSION")
minor = version_part("EIGEN_MAJOR_VERSION")
patch = version_part("EIGEN_MINOR_VERSION")
version = f"{major}.{minor}.{patch}"

(cmake_dir / "Eigen3Config.cmake").write_text(f"""\
get_filename_component(PACKAGE_PREFIX_DIR "${{CMAKE_CURRENT_LIST_DIR}}/../../../" ABSOLUTE)

if(NOT TARGET Eigen3::Eigen)
  include("${{CMAKE_CURRENT_LIST_DIR}}/Eigen3Targets.cmake")
endif()

set(EIGEN3_FOUND 1)
set(EIGEN3_INCLUDE_DIR "${{PACKAGE_PREFIX_DIR}}/include/eigen3")
set(EIGEN3_INCLUDE_DIRS "${{PACKAGE_PREFIX_DIR}}/include/eigen3")
set(EIGEN3_ROOT_DIR "${{PACKAGE_PREFIX_DIR}}")
set(EIGEN3_VERSION_STRING "{version}")
set(EIGEN3_VERSION_MAJOR "{major}")
set(EIGEN3_VERSION_MINOR "{minor}")
set(EIGEN3_VERSION_PATCH "{patch}")
set(Eigen3_VERSION "{version}")
""")

(cmake_dir / "Eigen3Targets.cmake").write_text("""\
get_filename_component(_IMPORT_PREFIX "${CMAKE_CURRENT_LIST_FILE}" PATH)
get_filename_component(_IMPORT_PREFIX "${_IMPORT_PREFIX}" PATH)
get_filename_component(_IMPORT_PREFIX "${_IMPORT_PREFIX}" PATH)
get_filename_component(_IMPORT_PREFIX "${_IMPORT_PREFIX}" PATH)

add_library(Eigen3::Eigen INTERFACE IMPORTED)
set_target_properties(Eigen3::Eigen PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES "${_IMPORT_PREFIX}/include/eigen3"
)

unset(_IMPORT_PREFIX)
""")

(cmake_dir / "Eigen3ConfigVersion.cmake").write_text(f"""\
set(PACKAGE_VERSION "{version}")

if(PACKAGE_VERSION VERSION_LESS PACKAGE_FIND_VERSION)
  set(PACKAGE_VERSION_COMPATIBLE FALSE)
elseif(PACKAGE_FIND_VERSION_MAJOR STREQUAL "{major}")
  set(PACKAGE_VERSION_COMPATIBLE TRUE)
  if(PACKAGE_FIND_VERSION STREQUAL PACKAGE_VERSION)
    set(PACKAGE_VERSION_EXACT TRUE)
  endif()
else()
  set(PACKAGE_VERSION_COMPATIBLE FALSE)
endif()
""")
PYTHON_SCRIPT
fi

touch "$DONE_MARKER"

# 修复 boost thread_data.hpp 中 PTHREAD_STACK_MIN 预处理问题
BOOST_THREAD_HPP="$SYSROOT/usr/include/boost/thread/pthread/thread_data.hpp"
if [ -f "$BOOST_THREAD_HPP" ]; then
    sed -i 's/#if PTHREAD_STACK_MIN > 0/#ifdef PTHREAD_STACK_MIN/' "$BOOST_THREAD_HPP"
fi

echo "修复完成！"
