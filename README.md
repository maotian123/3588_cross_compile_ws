# RK3588 Cross Compile Workspace

这个目录用于在 x86 主机上交叉编译 RK3588 板端使用的 `loc_map`，目标包为：

- `LocUtils`
- `msf_loc`
- `slam_ui`

当前测试源码：

```text
/home/user/3588_cross_compile_ws/src/loc_map -> /home/user/work_ws/loc_map
```

后续拿到正式 git 地址后，可以把这个 symlink 换成 git clone。

## 目标板信息

已通过 SSH 确认的板端信息：

```text
host: 10.10.10.50
user: sfzt
board: Rockchip RK3588 CORE LP4 V10 Board
OS: Ubuntu 20.04.6 LTS
arch: aarch64
kernel: 5.10.160
glibc: 2.31
gcc/g++: 9.4.0
cmake: 3.16.3
python: 3.8.10
ROS: /opt/ros/noetic
Docker: not installed
```

因此这里使用 Ubuntu Focal generic `aarch64-linux-gnu` GCC 9.4 交叉编译链和从 RK3588 板子抽取的 sysroot。不要使用 NVIDIA Orin/L4T Bootlin GCC 9.3 作为默认工具链。

## 目录结构

```text
3588_cross_compile_ws/
├── arch/                         # sysroot 归档和抽取记录
├── cmake/toolchain.cmake         # RK3588 aarch64 toolchain 配置
├── cross_compile_env.sh          # 交叉编译环境变量
├── script/
│   ├── check_prereqs.sh
│   ├── compile.sh                # LocUtils -> msf_loc -> slam_ui
│   ├── extract_sysroot.sh
│   ├── fix_pcl_ros_paths.sh
│   ├── fix_sysroot_symlinks.sh
│   ├── link_local_loc_map.sh
│   └── setup_cross_compile_env.sh
├── src/loc_map                   # 当前指向 /home/user/work_ws/loc_map
├── sysroot_base/                 # RK3588 sysroot
├── toolchain/                    # aarch64 工具链入口
├── build/                        # CMake build 输出
└── install/                      # 交叉编译 install prefix
```

## 初始化

如果 `src/loc_map` 还没有链接到本地测试源码：

```bash
cd /home/user/3588_cross_compile_ws
make link-local-loc-map
```

如果要重新从板子抽 sysroot：

```bash
cd /home/user/3588_cross_compile_ws
RK3588_PASSWORD=<password> make extract-sysroot
make setup-sysroot
```

`RK3588_PASSWORD` 不写进仓库或 README，运行时临时传入即可。

## 编译

推荐先手动 source 环境，再用单线程构建，避免链接阶段内存压力：

```bash
cd /home/user/3588_cross_compile_ws
source ./cross_compile_env.sh
RK3588_BUILD_JOBS=1 ./script/compile.sh
```

等价的 Makefile 入口：

```bash
cd /home/user/3588_cross_compile_ws
RK3588_BUILD_JOBS=1 make build
```

单独编译某个包：

```bash
source /home/user/3588_cross_compile_ws/cross_compile_env.sh
/home/user/3588_cross_compile_ws/script/compile.sh --package LocUtils
/home/user/3588_cross_compile_ws/script/compile.sh --package msf_loc
/home/user/3588_cross_compile_ws/script/compile.sh --package slam_ui
```

构建顺序固定为：

```text
LocUtils -> msf_loc -> slam_ui
```

## 本地验证

完整编译成功后，先检查关键产物是否为 ARM aarch64：

```bash
file \
  /home/user/3588_cross_compile_ws/install/lib/libLocUtils.so \
  /home/user/3588_cross_compile_ws/install/lib/libGeographicLib.so.26.0.0 \
  /home/user/3588_cross_compile_ws/install/lib/libceres.so.2.1.0 \
  /home/user/3588_cross_compile_ws/install/lib/libfmt.so.9.1.1 \
  /home/user/3588_cross_compile_ws/build/slam_ui/slam_ui \
  /home/user/work_ws/loc_map/msf_loc/loc_install/bin/lio_mapping_offline_node \
  /home/user/work_ws/loc_map/msf_loc/loc_install/bin/web_ui_websocket_node
```

扫描是否混入 x86 库：

```bash
find /home/user/3588_cross_compile_ws/install/lib \
  -maxdepth 1 -type f -name '*.so*' -exec file {} + | rg 'x86-64|Intel' || true

find /home/user/work_ws/loc_map/msf_loc/loc_install/bin \
     /home/user/work_ws/loc_map/msf_loc/loc_install/libs \
  -type f -exec file {} + | rg 'x86-64|Intel' || true
```

正常情况这两个扫描没有输出。

## 板端基础测试

板端测试不要污染系统目录，统一放到 `/tmp/rk3588_*`，测完删除。

基础测试覆盖：

- `file` 检查 ARM aarch64
- `ldd` 检查没有 `not found`
- `/lib/ld-linux-aarch64.so.1 --verify` 检查可执行文件能被 loader 装载

已验证的关键可执行文件：

```text
slam_ui
lio_matching_node
lio_mapping_node
lio_mapping_offline_node
lio_matching_ui_node
pgo_node
web_ui_websocket_node
```

## 板端 Bag 测试记录

板子上已有 bag：

```text
/home/sfzt/rosbag/2025-08-14-07-10-44_0.bag
duration: 18.8s
size: 332.7 MB
topics:
  /imu_data
  /rslidar_points
  /ultrasonic_info
  /vehicle_state
```

使用临时配置运行：

```text
bag_fold: /home/sfzt/rosbag
lidar_topic: /rslidar_points
imu_topic: /imu_data
vel_topic: /vehicle_state
output: /tmp/rk3588_bag_runtime_*/workspace
```

测试命令形式：

```bash
source /opt/ros/noetic/setup.bash
export LD_LIBRARY_PATH="$TEST_ROOT/install/lib:$TEST_ROOT/loc_install/libs:/usr/local/lib:/opt/ros/noetic/lib:/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu:${LD_LIBRARY_PATH:-}"

timeout 120s \
  "$TEST_ROOT/loc_install/bin/lio_mapping_offline_node" \
  "$TEST_ROOT/config/mapping/board_existing_bag.yaml"
```

板端实测结果：

```text
file: ARM aarch64
ldd: no missing deps
log: running in /home/sfzt/rosbag/2025-08-14-07-10-44_0.bag
log: io_utils.cpp:187] finish
generated:
  workspace/map_data/key_frames/1.pcd
  workspace/path/laser.txt
  workspace/path/gnss.txt
  workspace/map_data/trajectory/kf_odom.txt
  workspace/map_data/trajectory/keyframe.txt
```

说明：`lio_mapping_offline_node` 已经读完 bag 并生成关键帧/轨迹产物。进程本身没有自然退出，测试时用 `timeout` 收掉；这不影响“产物可在 RK3588 上启动并消费 bag”的验证结论。

## 清理测试产物

本地临时包：

```bash
rm -rf /tmp/rk3588_bag_runtime_payload.tar.gz /tmp/rk3588_bag_runtime_staging
rm -rf /tmp/rk3588_cross_test_payload.tar.gz
```

板端临时目录：

```bash
ssh sfzt@10.10.10.50 'rm -rf /tmp/rk3588_cross_test_* /tmp/rk3588_bag_runtime_* /tmp/rk3588_bag_test_*'
```

已经清理过的测试目录：

```text
/tmp/rk3588_cross_test_1779255852
/tmp/rk3588_bag_test_1779256666
/tmp/rk3588_bag_runtime_1779257354
```

## 已做的关键修正

- `LocUtils` 交叉编译时使用 sysroot/install 内 ARM 库，避免误链接主机 `/usr/local/lib`。
- `LocUtils/thirdparty` 安装 `libceres`、`libfmt` 时从 sysroot ARM 库链安装，避免 x86 库混入 `install/lib`。
- `msf_loc` 安装 `slam.yaml` 时支持从 `loc_install/config/slam.yaml` fallback。
- `slam_ui` 交叉编译时使用主机 `moc/uic/rcc`，避免 CMake 执行 sysroot 内 ARM Qt 工具。
- `fix_pcl_ros_paths.sh` 已处理 PCL/ROS/Qt CMake 路径，避免 sysroot 路径重复拼接。

## 常见问题

### 1. CMake 误用主机库

先检查：

```bash
find /home/user/3588_cross_compile_ws/install/lib \
  -maxdepth 1 -type f -name '*.so*' -exec file {} + | rg 'x86-64|Intel' || true
```

如果有输出，说明有 host 库混进来了，需要检查 CMake install 规则和 `LocUtils_LIBRARIES`。

### 2. Qt autogen 执行 ARM 工具失败

典型错误：

```text
/lib/ld-linux-aarch64.so.1: No such file or directory
```

原因是 x86 host 上执行了 sysroot 内 ARM 的 `moc/uic/rcc`。当前 `slam_ui` 已改为交叉编译时使用 host `/usr/bin/moc`、`/usr/bin/uic`、`/usr/bin/rcc`。

### 3. 板端测试目录残留

只清理 `/tmp/rk3588_*`，不要删除板端真实数据目录：

```bash
ssh sfzt@10.10.10.50 'rm -rf /tmp/rk3588_cross_test_* /tmp/rk3588_bag_runtime_* /tmp/rk3588_bag_test_*'
```

### 4. 后续替换为正式 git 源码

```bash
cd /home/user/3588_cross_compile_ws
rm src/loc_map
git clone <loc_map_git_url> src/loc_map
source ./cross_compile_env.sh
RK3588_BUILD_JOBS=1 ./script/compile.sh
```
