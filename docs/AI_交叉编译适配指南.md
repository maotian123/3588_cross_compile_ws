# AI 交叉编译适配指南

本文档给后续 AI/自动化维护使用，目标是避免把 Orin、Docker 或宿主机库路径误带进 RK3588 交叉编译流程。

## 项目结构速览

```text
3588_cross_compile_ws/
├── cmake/toolchain.cmake
├── script/
│   ├── check_prereqs.sh
│   ├── compile.sh
│   ├── extract_sysroot.sh
│   ├── fix_pcl_ros_paths.sh
│   ├── fix_sysroot_symlinks.sh
│   ├── link_local_loc_map.sh
│   ├── rk3588_extract_sysroot.py
│   └── setup_cross_compile_env.sh
├── docs/
├── src/loc_map                 # 当前是 /home/user/work_ws/loc_map symlink
├── build/                      # 生成，不提交
├── install/                    # 生成，不提交
├── sysroot_base/               # 生成，不提交
├── toolchain*/                 # 生成或本地下载，不提交
├── arch/                       # sysroot 归档，不提交
└── cross_compile_env.sh        # 生成，不提交
```

## 不变约束

- 目标板是 RK3588，不是 NVIDIA Orin。
- 目标系统是 Ubuntu 20.04 / ROS1 Noetic / GCC 9.4 / glibc 2.31。
- 默认工具链是 Ubuntu Focal `aarch64-linux-gnu` GCC 9.x。
- 不默认使用 NVIDIA Bootlin GCC 9.3。
- 本地调试不强制 Docker；CI/CD 使用带 RK3588 sysroot 的 Docker 大镜像。
- 构建顺序是 `LocUtils -> msf_loc -> slam_ui`。
- 当前测试源码是 `/home/user/work_ws/loc_map`，以后按用户提供的 git 地址替换。
- 不要提交 `build/`、`install/`、`sysroot_base/`、`toolchain*`、`arch/`、`src/`。

## 标准工作流

```bash
cd /home/user/3588_cross_compile_ws
make link-local-loc-map
RK3588_PASSWORD=<password> make extract-sysroot
make setup-sysroot
./script/check_prereqs.sh
source ./cross_compile_env.sh
RK3588_BUILD_JOBS=1 ./script/compile.sh
```

如果 sysroot 已存在，跳过 `extract-sysroot` 和 `setup-sysroot`。

## 适配正式 git 源码

用户给出 git 地址后：

```bash
cd /home/user/3588_cross_compile_ws
rm src/loc_map
git clone <loc_map_git_url> src/loc_map
```

检查源码结构：

```bash
test -f src/loc_map/LocUtils/CMakeLists.txt
test -f src/loc_map/msf_loc/CMakeLists.txt
test -f src/loc_map/slam_ui/slam_ui/CMakeLists.txt
```

如果目录布局变了，只改 `script/compile.sh` 里的 `PKG_PATHS`，不要把源码复制进工作区根目录。

## CMake 查找原则

`cmake/toolchain.cmake` 的核心边界：

```cmake
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_SYSROOT "$ENV{RK3588_CROSS_COMPILE_SYSROOT}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)
```

含义：

- 可执行工具在宿主机找，例如 `moc`、`uic`、`rcc`。
- 库必须从 `install/` 或 RK3588 sysroot 找。
- CMake package 可以从 sysroot、ROS Noetic、`install/` 找。
- 不要让 `/usr/local/lib` 这种宿主机路径参与目标链接。

## LocUtils 注意点

`LocUtils` 是下游依赖入口，必须先安装到：

```text
/home/user/3588_cross_compile_ws/install
```

下游包通过：

```bash
-DLocUtils_DIR=/home/user/3588_cross_compile_ws/install/share/LocUtils
```

找到它。

已做过的关键修正：

- 避免交叉编译时使用宿主机 `/usr/local/lib`。
- `LocUtils/thirdparty` 安装 `libceres`、`libfmt` 时从 ARM sysroot 库链取文件。
- `install/lib` 中不能混入 x86 `.so`。

## msf_loc 注意点

- `msf_loc` 不生成 WebUI/map update 相关 `.srv` 头，保持 `loc_map` 里的服务约定。
- `loc_install` 是运行包输出，板端测试主要使用 `loc_install/bin` 和 `loc_install/libs`。
- `slam.yaml` 安装支持从 `loc_install/config/slam.yaml` fallback。

## slam_ui 注意点

`slam_ui` 需要目标 Qt 库，但 Qt 代码生成工具必须是宿主机工具。

错误示例：

```text
/lib/ld-linux-aarch64.so.1: No such file or directory
```

这通常表示 CMake 在 x86 宿主机上执行了 ARM 版 `moc/uic/rcc`。处理方向是让构建使用 `/usr/bin/moc`、`/usr/bin/uic`、`/usr/bin/rcc`，而链接仍使用 sysroot 中的 ARM Qt5 库。

## 验证清单

每次改交叉编译逻辑后至少跑：

```bash
cd /home/user/3588_cross_compile_ws
./script/check_prereqs.sh
source ./cross_compile_env.sh
RK3588_BUILD_JOBS=1 ./script/compile.sh
```

构建后检查：

```bash
find /home/user/3588_cross_compile_ws/install/lib \
  -maxdepth 1 -type f -name '*.so*' -exec file {} + | rg 'x86-64|Intel' || true

find /home/user/3588_cross_compile_ws/src/loc_map/msf_loc/loc_install/bin \
     /home/user/3588_cross_compile_ws/src/loc_map/msf_loc/loc_install/libs \
  -type f -exec file {} + | rg 'x86-64|Intel' || true
```

正常情况无输出。

## Docker 的维护判断

Docker 版本和本地直接编译版本的底层逻辑一样：都在 x86 上使用 aarch64 交叉编译器和目标 sysroot。区别在环境边界。

本地调试可以不用 Docker，是因为：

- 目标板没有 Docker，验证链路不依赖容器。
- 项目是 ROS1 Noetic / Ubuntu 20.04，宿主机直接安装交叉工具链就够用。
- 少维护 Dockerfile、镜像、容器 apt 源和挂载路径。
- 路径问题更少，CMake 错误能直接定位到 `sysroot_base/`、`install/` 或宿主机。

CI/CD 使用 Docker 大镜像，是因为：

- 多台宿主机版本差异大，频繁出现宿主机依赖不一致。
- 需要固定 x86 ROS 工具链、代码生成器或 Python 包版本。
- CI 必须用完全可复现的镜像。
- 同时维护多个目标平台，宿主机全局依赖冲突。
- GitHub Actions 不应该每次重新抽取或下载 RK3588 sysroot。

当前 Docker 入口：

```text
docker/Dockerfile.rk3588_cross_compile
script/docker_build.sh
script/rk3588_image_build.sh
docs/RK3588_CI_Docker_交叉编译指南.md
```

## 常见误改

- 把 Orin 文档里的 Bootlin 下载命令复制到 RK3588 README。
- 在 `toolchain.cmake` 里写死 NVIDIA/L4T 路径。
- 把 `src/loc_map` 下源码或 `install/` 产物提交到交叉编译仓库。
- 用宿主机 `/usr/local/lib` 解决链接错误。
- 删除板端 `/home/sfzt/rosbag` 做清理。
