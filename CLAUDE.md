# Project Notes

This is the RK3588 cross compile workspace for `loc_map`.

## Target

- Platform: Rockchip RK3588 aarch64
- Board: `Rockchip RK3588 CORE LP4 V10 Board`
- OS: Ubuntu 20.04.6
- ROS: ROS1 Noetic
- GCC on target: 9.4.0
- glibc on target: 2.31
- binutils on target: 2.34
- Python: 3.8
- Qt: 5.12.8
- PCL: 1.10
- OpenCV: 4.2

## CI/CD Direction

The responsibility of this workspace is to produce the fat RK3588 Docker image for CI:

- Build and push the image on Alibaba Cloud ECS.
- Store the image in Alibaba Cloud ACR.
- `/home/user/loc_map_cicd/.github/workflows/build.yml` pulls the image, mounts the `loc_map` checkout, and writes build artifacts to mounted output directories.
- Direct host cross compile is kept only for local debug and parity checks.

This is still x86_64 cross compilation under the hood. Docker does not change the compiler model; it freezes the host packages, RK3588 sysroot, toolchain, and scripts so CI does not depend on a mutable ECS or developer machine.

## Important Commands

```bash
cd /home/user/3588_cross_compile_ws
./script/check_prereqs.sh
make link-local-loc-map
RK3588_PASSWORD=<password> make extract-sysroot
make setup-sysroot
source cross_compile_env.sh
make build-locutils
make build-msf_loc
make build-slam_ui
```

Docker image build on ECS:

```bash
cd /home/user/3588_cross_compile_ws
DOCKER_IMAGE=registry.cn-hangzhou.aliyuncs.com/<namespace>/rk3588-cross:2026-05-20 make docker-image
docker login registry.cn-hangzhou.aliyuncs.com
docker push registry.cn-hangzhou.aliyuncs.com/<namespace>/rk3588-cross:2026-05-20
```

Docker build smoke test:

```bash
LOC_MAP_DIR=/home/user/work_ws/loc_map \
RK3588_DOCKER_IMAGE=registry.cn-hangzhou.aliyuncs.com/<namespace>/rk3588-cross:2026-05-20 \
RK3588_BUILD_JOBS=1 \
./script/docker_build.sh --package LocUtils
```

## Source Layout

During initial testing, `src/loc_map` is a symlink to `/home/user/work_ws/loc_map`.

Later, replace it with the real git clone:

```bash
rm src/loc_map
git clone <loc_map_git_url> src/loc_map
```

## Build Conventions

- Do not copy the full `loc_map` tree into this workspace for local tests; use the symlink.
- Keep `LocUtils` installed into `/home/user/3588_cross_compile_ws/install`.
- Configure downstream packages with `LocUtils_DIR=/home/user/3588_cross_compile_ws/install/share/LocUtils`.
- Keep `msf_loc` service conventions from `loc_map`: do not make `msf_loc` generate WebUI/map update `.srv` headers.
- `slam_ui` requires host Qt build tools (`moc`, `uic`, `rcc`) in addition to target Qt libraries in the sysroot.
- Prefer a Ubuntu Focal generic `aarch64-linux-gnu` GCC 9.x toolchain for RK3588. Do not make NVIDIA Bootlin GCC 9.3 the default for this board.

## Generated Artifacts

These are generated and should not be committed:

- `build/`
- `install/`
- `rk3588_build/`
- `rk3588_install/`
- `sysroot_base/`
- `cross_compile_env.sh`
- `arch/*.tar.gz`
- `src/`
- `.ssh/`

Do commit `.claude/`, `docker/Dockerfile.rk3588_cross_compile`, `.dockerignore`, `script/docker_build.sh`, and `script/rk3588_image_build.sh`.
