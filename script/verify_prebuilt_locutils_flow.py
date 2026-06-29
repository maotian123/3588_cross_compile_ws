#!/usr/bin/env python3
"""Verify the RK3588 image supports the prebuilt LocUtils fast path."""

from __future__ import annotations

import os
import subprocess
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(message)


def read(path: str) -> str:
    return (REPO_ROOT / path).read_text(encoding="utf-8")


def main() -> None:
    locutils_prebuilt = REPO_ROOT / "script/locutils_prebuilt.sh"
    image_builder = REPO_ROOT / "script/build_prebuilt_locutils_image.sh"
    compile_sh = read("script/compile.sh")
    dockerfile = read("docker/Dockerfile.rk3588_cross_compile")

    require(locutils_prebuilt.exists(), "script/locutils_prebuilt.sh must exist")
    require(image_builder.exists(), "script/build_prebuilt_locutils_image.sh must exist")

    locutils_text = locutils_prebuilt.read_text(encoding="utf-8")
    image_builder_text = image_builder.read_text(encoding="utf-8")

    require("hash)" in locutils_text, "locutils_prebuilt.sh must expose a hash command")
    require("restore)" in locutils_text, "locutils_prebuilt.sh must expose a restore command")
    require("save)" in locutils_text, "locutils_prebuilt.sh must expose a save command")
    require("git -C" in locutils_text, "LocUtils hash must prefer git tree hashing")
    require("locutils-config.cmake" in locutils_text, "restore must validate LocUtils CMake config")
    require("libLocUtils.so" in locutils_text, "restore must validate libLocUtils.so")
    require("updateWaypoints.h" in locutils_text, "restore must validate generated service headers")

    require(
        "RK3588_USE_PREBUILT_LOCUTILS" in compile_sh,
        "compile.sh must gate the fast path with RK3588_USE_PREBUILT_LOCUTILS",
    )
    require(
        "restore_prebuilt_locutils_if_enabled" in compile_sh,
        "compile.sh must attempt restore before building LocUtils",
    )
    require(
        "LocUtils)" in compile_sh
        and compile_sh.index("restore_prebuilt_locutils_if_enabled") < compile_sh.index("configure_and_build"),
        "compile.sh must define restore before the build loop",
    )

    require("docker commit" in image_builder_text, "image builder must commit the prebuilt install into the image")
    require("locutils_prebuilt.sh save" in image_builder_text, "image builder must save LocUtils manifest")
    require("PREBUILT_LOCUTILS_TREE" in image_builder_text, "image builder must pass the source hash into the image")

    require(
        "RK3588_PREBUILT_LOCUTILS_DIR" in dockerfile,
        "Dockerfile must define the prebuilt LocUtils location",
    )

    for rel in [
        "script/locutils_prebuilt.sh",
        "script/build_prebuilt_locutils_image.sh",
        "script/compile.sh",
    ]:
        subprocess.run(["bash", "-n", str(REPO_ROOT / rel)], check=True)

    print("[verify] prebuilt LocUtils fast path wiring ok")


if __name__ == "__main__":
    main()
