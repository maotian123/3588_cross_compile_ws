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

## Important Commands

```bash
cd /home/user/3588_cross_compile_ws
./script/check_prereqs.sh
make link-local-loc-map
RK3588_PASSWORD=123 make extract-sysroot
make setup-sysroot
source cross_compile_env.sh
make build-locutils
make build-msf_loc
make build-slam_ui
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
- `sysroot_base/`
- `cross_compile_env.sh`
- `arch/*.tar.gz`
