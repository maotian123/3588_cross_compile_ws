# RK3588 Cross Compile Workspace

这个工作区用于在 x86_64 宿主机上交叉编译 RK3588 板端运行的 `loc_map`：

- `LocUtils`
- `msf_loc`
- `slam_ui`

当前测试源码：

```text
/home/user/3588_cross_compile_ws/src/loc_map -> /home/user/work_ws/loc_map
```

后续拿到正式 git 地址后，把这个 symlink 换成 `git clone <loc_map_git_url> src/loc_map`。

## 文档入口

| 文档 | 用途 |
|------|------|
| [docs/RK3588_ROS1_宿主机交叉编译指南.md](docs/RK3588_ROS1_宿主机交叉编译指南.md) | 日常构建、单包编译、本地检查、部署方式 |
| [docs/RK3588_CI_Docker_交叉编译指南.md](docs/RK3588_CI_Docker_交叉编译指南.md) | CI/CD Docker 镜像、容器编译、缓存和制品建议 |
| [docs/从零构建RK3588交叉编译环境完整指南.md](docs/从零构建RK3588交叉编译环境完整指南.md) | 从目标板确认、抽 sysroot、配置工具链到编译的完整流程 |
| [docs/RK3588_板端运行验证记录.md](docs/RK3588_板端运行验证记录.md) | 已在 `10.10.10.50` 上做过的 loader/ldd/bag 测试记录 |
| [docs/RK3588_target_info.md](docs/RK3588_target_info.md) | 目标板系统、ABI、ROS、第三方库版本 |
| [docs/AI_交叉编译适配指南.md](docs/AI_交叉编译适配指南.md) | 给后续 AI/自动化维护用的适配规则和排错检查点 |

## 目标板结论

已通过 SSH 确认：

```text
host: 10.10.10.50
user: sfzt
board: Rockchip RK3588 CORE LP4 V10 Board
OS: Ubuntu 20.04.6 LTS
arch: aarch64 / arm64
kernel: 5.10.160
glibc: 2.31
gcc/g++: 9.4.0
cmake: 3.16.3
python: 3.8.10
ROS: /opt/ros/noetic
Docker: not installed
```

因此本工作区默认使用 Ubuntu Focal 的 `aarch64-linux-gnu` GCC 9.x 交叉编译器，加 RK3588 板端抽取的 sysroot。不要把 NVIDIA Orin/L4T Bootlin GCC 9.3 当作 3588 默认工具链；Bootlin 是 Orin/L4T 流程里的选择，不是 Rockchip 板子的目标匹配默认值。

## Docker 定位

这个仓库的职责是生产 RK3588 Docker 大镜像，真正的 GitHub Actions/Release 流水线在 `/home/user/loc_map_cicd`：

- 阿里云 ECS 上构建镜像，把 RK3588 sysroot、交叉编译器和构建脚本打进 image。
- 镜像推到阿里云 ACR。
- `/home/user/loc_map_cicd/.github/workflows/build.yml` 从 ACR 拉取镜像，挂载 `loc_map` 源码，编译并发布 Release。
- 本仓库的本地直接编译只作为调试和验证路径保留，不作为最终 CI 方向。

Docker 方案和本地直接编译方案的底层逻辑一样：都是在 x86 上调用 aarch64 交叉编译器，并使用 RK3588 板端 sysroot。区别是 CI 用 Docker 固定宿主机工具版本，并把大体积 sysroot 固化到镜像里，避免 `/home/user/loc_map_cicd` 每次构建时重新抽取或下载 sysroot。

CI Docker 入口见 [docs/RK3588_CI_Docker_交叉编译指南.md](docs/RK3588_CI_Docker_交叉编译指南.md)。

## 快速开始

```bash
cd /home/user/3588_cross_compile_ws

# 当前测试阶段：链接本地 loc_map
make link-local-loc-map

# 如果 sysroot 还没有生成，先从板端提取并解压
RK3588_PASSWORD=<password> make extract-sysroot
make setup-sysroot

# 检查宿主机工具、sysroot、源码结构
./script/check_prereqs.sh

# 编译 LocUtils -> msf_loc -> slam_ui
source ./cross_compile_env.sh
RK3588_BUILD_JOBS=1 ./script/compile.sh
```

`RK3588_PASSWORD` 只在运行命令时临时传入，不写进仓库。

## 单包编译

```bash
cd /home/user/3588_cross_compile_ws
source ./cross_compile_env.sh

./script/compile.sh --package LocUtils
./script/compile.sh --package msf_loc
./script/compile.sh --package slam_ui
```

构建顺序固定为：

```text
LocUtils -> msf_loc -> slam_ui
```

## 已验证产物

2026-05-21 已使用 Docker CI 镜像路径验证：

```bash
DOCKER_BUILDKIT=1 DOCKER_IMAGE=rk3588-cross:test make docker-image

LOC_MAP_DIR=/home/user/work_ws/loc_map RK3588_DOCKER_IMAGE=rk3588-cross:test RK3588_BUILD_JOBS=1 ./script/docker_build.sh --package LocUtils
LOC_MAP_DIR=/home/user/work_ws/loc_map RK3588_DOCKER_IMAGE=rk3588-cross:test RK3588_BUILD_JOBS=1 ./script/docker_build.sh --package msf_loc
LOC_MAP_DIR=/home/user/work_ws/loc_map RK3588_DOCKER_IMAGE=rk3588-cross:test RK3588_BUILD_JOBS=1 ./script/docker_build.sh --package slam_ui
```

验证时关键产物均为 ARM aarch64：

```text
rk3588_install/lib/libLocUtils.so
rk3588_install/lib/libGeographicLib.so.26.0.0
rk3588_install/lib/libceres.so.2.1.0
rk3588_install/lib/libfmt.so.9.1.1
rk3588_build/slam_ui/slam_ui
/home/user/work_ws/loc_map/msf_loc/loc_install/bin/lio_mapping_offline_node
/home/user/work_ws/loc_map/msf_loc/loc_install/bin/web_ui_websocket_node
```

本地测试输出属于生成产物，验证后可删除；重新运行上面的 Docker build 命令即可复现。

板端也已在 `sfzt@10.10.10.50` 做过基础 loader/ldd 检查，并用板上已有 bag `/home/sfzt/rosbag/2025-08-14-07-10-44_0.bag` 跑通 `lio_mapping_offline_node`。详见 [docs/RK3588_板端运行验证记录.md](docs/RK3588_板端运行验证记录.md)。

## 目录结构

```text
3588_cross_compile_ws/
├── cmake/toolchain.cmake              # RK3588 aarch64 CMake toolchain
├── docker/Dockerfile.rk3588_cross_compile # 带 RK3588 sysroot 的 CI 大镜像
├── docs/                              # 交叉编译、适配、板端验证文档
├── script/
│   ├── check_prereqs.sh
│   ├── compile.sh                     # LocUtils -> msf_loc -> slam_ui
│   ├── docker_build.sh                # 本地调用 CI 大镜像编译 loc_map
│   ├── extract_sysroot.sh             # SSH 抽取 RK3588 sysroot
│   ├── fix_pcl_ros_paths.sh
│   ├── fix_sysroot_symlinks.sh
│   ├── link_local_loc_map.sh
│   ├── rk3588_extract_sysroot.py
│   └── setup_cross_compile_env.sh
├── Makefile
├── CHANGELOG.md
└── CLAUDE.md
```

以下是生成文件或本地文件，不上传：

```text
arch/
build/
install/
rk3588_build/
rk3588_install/
sysroot_base/
toolchain/
toolchain_root/
toolchain_pkgs/
cross_compile_env.sh
src/
.ssh/
```

## 上传规则

只上传交叉编译逻辑、脚本、CMake 配置和文档。不要上传：

- sysroot 压缩包或解压目录
- 交叉编译工具链和 `.deb` 下载包
- `build/`、`install/`、`devel/`、`log/`
- 临时测试 payload
- SSH key、密码、个人本地配置

当前 `.gitignore` 已按这个规则处理。

CI Docker 相关的 `docker/Dockerfile.rk3588_cross_compile`、`.dockerignore`、`script/docker_build.sh`、`script/rk3588_image_build.sh` 需要上传。`arch/rk3588_sysroot.tar.gz` 只在 ECS 构建镜像时放在本地，不提交到 git。

阿里云 ACR 推荐固定 tag：

```text
registry.cn-hangzhou.aliyuncs.com/bit_robot_image/robot_images:rk3588-cross-20260521
```
