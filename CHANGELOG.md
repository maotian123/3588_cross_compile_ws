# Changelog

## 2026-05-20

- Generated RK3588 cross compile workspace from the previous aarch64 cross compile workspace.
- Target changed to Ubuntu 20.04 / ROS1 Noetic / GCC 9.4 / Qt5 on RK3588.
- Build source changed to `src/loc_map`, currently linked to `/home/user/work_ws/loc_map` for testing.
- Build order changed to `LocUtils -> msf_loc -> slam_ui`.
