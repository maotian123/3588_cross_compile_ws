# RK3588 Target Info

Confirmed on `2026-05-20` by SSH to `sfzt@10.10.10.50`.

```text
hostname: Ubuntu
kernel: Linux Ubuntu 5.10.160 #13 SMP Sat Oct 19 03:29:55 UTC 2024 aarch64
machine: aarch64
dpkg_arch: arm64
model: Rockchip RK3588 CORE LP4 V10 Board
serial: be4d91fbf90659ef
os: Ubuntu 20.04.6 LTS focal
nproc: 8
memory: 7.7 GiB
disk: /dev/root 46G total, 18G available
```

Toolchain and system ABI:

```text
gcc machine: aarch64-linux-gnu
gcc version: 9.4.0
g++ version: 9.4.0
binutils ld: 2.34
glibc: 2.31
libstdc++ max observed: GLIBCXX_3.4.28
```

Build/runtime packages:

```text
ROS_DISTRO=noetic
cmake=3.16.3
python=3.8.10
Qt=5.12.8
Boost=1.71
Eigen=3.3.7
PCL=1.10
OpenCV=4.2
GTSAM=4.0.3
yaml-cpp=0.6.2
TBB=2020.1
SuiteSparse=5.7.1
GeographicLib=1.50.1
```

Conclusion:

Use a generic Ubuntu Focal `aarch64-linux-gnu` GCC 9.x cross compiler with the RK3588 sysroot extracted from this board. The NVIDIA Bootlin GCC 9.3 toolchain from the Orin workflow is not the target-matched default for this Rockchip board.
