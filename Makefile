# RK3588 (aarch64) ROS1 Noetic cross compile workspace

.PHONY: help check-prereqs link-local-loc-map extract-sysroot setup-sysroot build build-locutils build-msf_loc build-slam_ui docker-image docker-image-prebuilt-locutils docker-build clean

WORKSPACE_DIR := $(shell pwd)
ENV_FILE := $(WORKSPACE_DIR)/cross_compile_env.sh
DOCKER_IMAGE ?= rk3588-cross:20.04

RK3588_HOST ?= 10.10.10.50
RK3588_USER ?= sfzt
LOCAL_LOC_MAP ?= /home/user/work_ws/loc_map

help:
	@echo "RK3588 (aarch64) ROS1 Noetic cross compile workspace"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  check-prereqs       Check local tools, sysroot, and loc_map source"
	@echo "  link-local-loc-map  Link src/loc_map -> $(LOCAL_LOC_MAP) for testing"
	@echo "  extract-sysroot     Extract sysroot from RK3588 board"
	@echo "  setup-sysroot       Unpack arch/rk3588_sysroot.tar.gz and write env file"
	@echo "  build               Build LocUtils -> msf_loc -> slam_ui"
	@echo "  build-locutils      Build only LocUtils"
	@echo "  build-msf_loc       Build only msf_loc"
	@echo "  build-slam_ui       Build only slam_ui"
	@echo "  docker-image        Build the fat CI Docker image with RK3588 sysroot ($(DOCKER_IMAGE))"
	@echo "  docker-image-prebuilt-locutils"
	@echo "                      Build/push image with current LocUtils preinstalled"
	@echo "  docker-build        Build loc_map inside the fat CI Docker image"
	@echo "  clean               Remove build/install/rk3588/sysroot/env outputs"
	@echo ""
	@echo "Sysroot extraction example:"
	@echo "  RK3588_PASSWORD=<password> make extract-sysroot"

check-prereqs:
	@./script/check_prereqs.sh

link-local-loc-map:
	@./script/link_local_loc_map.sh "$(LOCAL_LOC_MAP)"

extract-sysroot:
	@if [ -z "$$RK3588_PASSWORD" ]; then \
		echo "ERROR: set RK3588_PASSWORD first, for example: RK3588_PASSWORD=<password> make extract-sysroot"; \
		exit 1; \
	fi
	@./script/extract_sysroot.sh --host "$(RK3588_HOST)" --user "$(RK3588_USER)" --password "$$RK3588_PASSWORD"

setup-sysroot:
	@./script/setup_cross_compile_env.sh

build:
	@if [ ! -f "$(ENV_FILE)" ]; then \
		echo "ERROR: run make setup-sysroot and source $(ENV_FILE) first"; \
		exit 1; \
	fi
	@bash -c ". $(ENV_FILE) && bash $(WORKSPACE_DIR)/script/compile.sh"

build-locutils:
	@if [ ! -f "$(ENV_FILE)" ]; then \
		echo "ERROR: run make setup-sysroot and source $(ENV_FILE) first"; \
		exit 1; \
	fi
	@bash -c ". $(ENV_FILE) && bash $(WORKSPACE_DIR)/script/compile.sh --package LocUtils"

build-msf_loc:
	@if [ ! -f "$(ENV_FILE)" ]; then \
		echo "ERROR: run make setup-sysroot and source $(ENV_FILE) first"; \
		exit 1; \
	fi
	@bash -c ". $(ENV_FILE) && bash $(WORKSPACE_DIR)/script/compile.sh --package msf_loc"

build-slam_ui:
	@if [ ! -f "$(ENV_FILE)" ]; then \
		echo "ERROR: run make setup-sysroot and source $(ENV_FILE) first"; \
		exit 1; \
	fi
	@bash -c ". $(ENV_FILE) && bash $(WORKSPACE_DIR)/script/compile.sh --package slam_ui"

docker-image:
	@if [ ! -f "arch/rk3588_sysroot.tar.gz" ]; then \
		echo "ERROR: missing arch/rk3588_sysroot.tar.gz; run RK3588_PASSWORD=<password> make extract-sysroot or copy it from ECS storage"; \
		exit 1; \
	fi
	docker build -f docker/Dockerfile.rk3588_cross_compile -t "$(DOCKER_IMAGE)" .

docker-image-prebuilt-locutils:
	@./script/build_prebuilt_locutils_image.sh

docker-build:
	@RK3588_DOCKER_IMAGE="$(DOCKER_IMAGE)" ./script/docker_build.sh

clean:
	rm -rf build/
	rm -rf install/
	rm -rf rk3588_build/
	rm -rf rk3588_install/
	rm -rf sysroot_base/
	rm -f cross_compile_env.sh
