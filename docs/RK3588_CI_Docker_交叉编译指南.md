# RK3588 Docker 镜像和 loc_map_cicd 接入指南

`/home/user/3588_cross_compile_ws` 的目标是做 RK3588 交叉编译大镜像：把 RK3588 sysroot、交叉编译器、CMake 配置和构建脚本打进 Docker image。

真正的 CI/CD workflow 在 `/home/user/loc_map_cicd/.github/workflows/build.yml`。它不构建镜像，只从阿里云 ACR 拉取已经构建好的 RK3588 镜像，挂载当前 `loc_map` 仓库源码，然后输出 GitHub Release。

## 镜像内容

镜像包含：

- Ubuntu 20.04 x86_64
- `gcc-aarch64-linux-gnu` / `g++-aarch64-linux-gnu`
- CMake、Make、pkg-config、rsync、file、ripgrep
- Python3 + paramiko
- host Qt tools: `moc`、`uic`、`rcc`
- RK3588 sysroot，路径为 `/opt/rk3588/cross_compile_ws/sysroot_base`
- `cmake/toolchain.cmake`
- `script/compile.sh`
- `script/check_prereqs.sh`
- `script/fix_*`
- `rk3588-cross-build` 容器内构建入口

镜像不包含：

- `loc_map` 源码
- `build/`
- `install/`
- SSH key、密码
- GitHub token、Gemini key、阿里云 key

## ECS 上构建大镜像

推荐在阿里云 ECS 上构建镜像，因为 sysroot 大，GitHub-hosted runner 不适合每次临时准备。ECS 只负责构建和推送镜像，不需要接入 GitHub Actions runner。

ECS 安装 Docker：

```bash
sudo apt-get update
sudo apt-get install -y docker.io
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
```

重新登录 shell 后确认：

```bash
docker version
```

准备工作区：

```bash
cd /home/user/3588_cross_compile_ws
```

确认 sysroot tarball 存在：

```bash
ls -lh arch/rk3588_sysroot.tar.gz
```

如果没有，先从板子抽取，或者把已有 tarball 传到 ECS：

```bash
RK3588_PASSWORD=<password> make extract-sysroot
```

构建镜像：

```bash
cd /home/user/3588_cross_compile_ws
DOCKER_IMAGE=registry.cn-hangzhou.aliyuncs.com/bit_robot_image/robot_images:rk3588-cross-20260521 make docker-image
```

本地 smoke test：

```bash
LOC_MAP_DIR=/home/user/work_ws/loc_map \
RK3588_DOCKER_IMAGE=registry.cn-hangzhou.aliyuncs.com/bit_robot_image/robot_images:rk3588-cross-20260521 \
RK3588_BUILD_JOBS=1 \
./script/docker_build.sh --package LocUtils
```

完整构建：

```bash
LOC_MAP_DIR=/home/user/work_ws/loc_map \
RK3588_DOCKER_IMAGE=registry.cn-hangzhou.aliyuncs.com/bit_robot_image/robot_images:rk3588-cross-20260521 \
RK3588_BUILD_JOBS=1 \
./script/docker_build.sh
```

本地 wrapper 默认输出到：

```text
rk3588_build/
rk3588_install/
```

这两个目录专门给 Docker 路径使用，避免和本地直接编译的 `build/`、`install/` CMake cache 混在一起。

## 推送到阿里云 ACR

登录阿里云容器镜像服务：

```bash
docker login registry.cn-hangzhou.aliyuncs.com
```

推送：

```bash
docker push registry.cn-hangzhou.aliyuncs.com/bit_robot_image/robot_images:rk3588-cross-20260521
```

建议同时打一个带日期或 sysroot 版本的不可变 tag：

```bash
docker tag \
  rk3588-cross:test \
  registry.cn-hangzhou.aliyuncs.com/bit_robot_image/robot_images:rk3588-cross-20260521

docker push registry.cn-hangzhou.aliyuncs.com/bit_robot_image/robot_images:rk3588-cross-20260521
```

GitHub Actions 里用固定日期 tag 更可控，`latest` 只适合手动验证。

当前已推送并验证的镜像：

```text
registry.cn-hangzhou.aliyuncs.com/bit_robot_image/robot_images:rk3588-cross-20260521
digest: sha256:2fba0e062eb3680e576d25616d5ee8fcd2cffe6103fbea9428b93123cda7d27e
```

## loc_map_cicd 需要的 GitHub Secrets

在 `/home/user/loc_map_cicd` 对应的 GitHub 仓库里配置：

```text
ACR_REGISTRY=registry.cn-hangzhou.aliyuncs.com
ACR_USERNAME=aliyun2905962273
ACR_PASSWORD=<your_acr_password>
RK3588_CROSS_IMAGE=registry.cn-hangzhou.aliyuncs.com/bit_robot_image/robot_images:rk3588-cross-20260521
GEMINI_API_KEY=<your_gemini_key>
```

`GEMINI_API_KEY` 只影响发布说明 AI 总结，和交叉编译镜像没有耦合。

`GITHUB_TOKEN` 是 GitHub Actions 自动提供的，不需要手动配置。不要把阿里云 AK/SK、ACR 密码、Gemini key 写到 workflow 明文里。

当前 RK3588 workflow 不再使用旧的腾讯云 COS key 和飞书 webhook；产物先发布到 GitHub Release。如果后续要同步到阿里云 OSS，再单独增加 OSS bucket 和 AK/SK。

## loc_map_cicd Workflow 使用方式

`/home/user/loc_map_cicd/.github/workflows/build.yml` 现在是 RK3588 专用的最小 workflow：

- `prepare`：生成版本号、tag、changelog、commit 信息。
- `build-rk3588`：登录阿里云 ACR、拉取 `RK3588_CROSS_IMAGE`、运行 `rk3588-cross-build`、检查 ARM 产物、打包 release。
- `release`：用 `GEMINI_API_KEY` 生成发布说明，上传到 GitHub Release。

旧的 Orin `cross-compile` 镜像、GHCR 构建镜像流程、腾讯云 COS 上传流程不作为 RK3588 主路径使用。

## ECS 的两种用法

推荐方案：ECS 只负责构建和推送大镜像。

```text
ECS: docker build + docker push 到阿里云 ACR
loc_map_cicd GitHub Actions: docker pull + build loc_map + GitHub Release
```

可选方案：ECS 同时作为 GitHub self-hosted runner。

```text
ECS: self-hosted runner + 本地 Docker image
GitHub Actions: runs-on self-hosted
```

如果 ACR 私有镜像拉取慢或网络受限，可以考虑 self-hosted runner；否则先用 ACR 更简单。

## 镜像更新时机

需要重建并推送镜像的情况：

- RK3588 板端 apt 依赖变化
- ROS Noetic 包变化
- `/usr/local` 下第三方库变化
- sysroot 重新抽取
- `cmake/toolchain.cmake` 或 `script/fix_*` 变化
- 交叉编译器版本变化

普通 `loc_map` 业务代码变化不需要重建镜像，只需要 GitHub Actions 拉同一个镜像重新编译。
