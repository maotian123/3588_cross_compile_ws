#!/usr/bin/env python3
"""Extract a RK3588 Ubuntu 20.04 ROS Noetic sysroot over SSH.

This script avoids sshpass so the workspace can run on hosts where only
paramiko is installed.
"""

from __future__ import annotations

import argparse
import os
import pathlib
import shlex
import sys
import time

import paramiko


DEFAULT_DIRS = [
    "/tmp/rk3588_sysroot_version.txt",
    "/etc/alternatives",
    "/usr/include",
    "/usr/lib/aarch64-linux-gnu",
    "/usr/lib/pkgconfig",
    "/usr/lib/cmake",
    "/usr/lib/qt5/bin",
    "/usr/bin/aarch64-linux-gnu-qmake",
    "/lib/aarch64-linux-gnu",
    "/usr/share/pkgconfig",
    "/usr/share/cmake",
    "/usr/share/eigen3",
    "/usr/share/pcl-1.10",
    "/usr/share/vtk-7.1",
    "/usr/local/include",
    "/usr/local/lib",
    "/usr/local/share",
    "/opt/ros/noetic",
]

sys.stdout.reconfigure(line_buffering=True)


def run(client: paramiko.SSHClient, command: str, timeout: int = 120) -> str:
    stdin, stdout, stderr = client.exec_command(command, timeout=timeout)
    out = stdout.read().decode("utf-8", "replace")
    err = stderr.read().decode("utf-8", "replace")
    code = stdout.channel.recv_exit_status()
    if code != 0:
        raise RuntimeError(f"remote command failed ({code}): {command}\n{err}")
    return out


def sudo_run(client: paramiko.SSHClient, password: str, command: str, timeout: int = 1200) -> str:
    quoted_password = shlex.quote(password)
    sudo_command = f"printf '%s\\n' {quoted_password} | sudo -S bash -lc {shlex.quote(command)}"
    return run(client, sudo_command, timeout=timeout)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", required=True)
    parser.add_argument("--user", required=True)
    parser.add_argument("--password", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    output = pathlib.Path(args.output).expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    version_path = output.parent / "rk3588_sysroot_version.txt"
    remote_id = int(time.time())
    remote_tar = f"/tmp/rk3588_sysroot_{remote_id}.tar.gz"
    remote_list = f"/tmp/rk3588_sysroot_{remote_id}.list"

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    print(f"[INFO] Connecting to {args.user}@{args.host} ...", flush=True)
    client.connect(
        hostname=args.host,
        username=args.user,
        password=args.password,
        timeout=10,
        banner_timeout=10,
        auth_timeout=10,
        look_for_keys=False,
        allow_agent=False,
    )

    version_command = r"""
set -e
echo "extract_time: $(date -Iseconds)"
echo "hostname: $(hostname)"
echo "kernel: $(uname -r)"
echo "arch: $(uname -m)"
cat /proc/device-tree/model 2>/dev/null | tr '\000' '\n' | sed 's/^/model: /' || true
cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | sed 's/PRETTY_NAME=/os: /' || true
echo "gcc: $(gcc --version 2>/dev/null | head -1)"
echo "cmake: $(cmake --version 2>/dev/null | head -1)"
echo "python: $(python3 --version 2>/dev/null)"
echo "ros: $(bash -lc 'source /opt/ros/noetic/setup.bash 2>/dev/null; echo ${ROS_DISTRO:-unknown}')"
"""
    version = run(client, version_command)
    print(version.rstrip(), flush=True)

    sudo_run(
        client,
        args.password,
        f"cat > /tmp/rk3588_sysroot_version.txt <<'EOF'\n{version}\nEOF",
        timeout=60,
    )

    existing_dirs = []
    for directory in DEFAULT_DIRS:
        test_cmd = f"test -e {shlex.quote(directory)} && echo yes || true"
        if run(client, test_cmd).strip() == "yes":
            existing_dirs.append(directory)
        else:
            print(f"[INFO] Skip missing: {directory}", flush=True)

    if not existing_dirs:
        raise RuntimeError("no sysroot directories found")

    print("[INFO] Creating remote sysroot tarball. This can take a while.", flush=True)
    list_entries = "\n".join(
        f"printf '%s\\0' {shlex.quote(path)} >> {shlex.quote(remote_list)}"
        for path in existing_dirs
    )
    sudo_run(
        client,
        args.password,
        f"""
rm -f {shlex.quote(remote_tar)} {shlex.quote(remote_list)}
{list_entries}
find /usr/lib -maxdepth 1 \\( -type f -o -type l \\) -print0 >> {shlex.quote(remote_list)} 2>/dev/null || true
tar czf {shlex.quote(remote_tar)} --warning=no-file-changed --null --files-from {shlex.quote(remote_list)} 2>/tmp/rk3588_sysroot_tar.err || true
test -f {shlex.quote(remote_tar)}
""",
        timeout=2400,
    )

    print(f"[INFO] Downloading {remote_tar} -> {output}", flush=True)
    sftp = client.open_sftp()
    try:
        last_report = {"time": 0.0}

        def progress(transferred: int, total: int) -> None:
            now = time.time()
            if now - last_report["time"] < 5 and transferred != total:
                return
            last_report["time"] = now
            if total:
                print(
                    f"[INFO] Download progress: {transferred / (1024 * 1024):.1f} / {total / (1024 * 1024):.1f} MiB",
                    flush=True,
                )
            else:
                print(f"[INFO] Download progress: {transferred / (1024 * 1024):.1f} MiB", flush=True)

        sftp.get(remote_tar, str(output), callback=progress)
    finally:
        sftp.close()

    sudo_run(
        client,
        args.password,
        f"rm -f {shlex.quote(remote_tar)} {shlex.quote(remote_list)} /tmp/rk3588_sysroot_version.txt",
        timeout=60,
    )
    client.close()

    version_path.write_text(version, encoding="utf-8")
    size_mb = output.stat().st_size / (1024 * 1024)
    print(f"[INFO] Sysroot written: {output} ({size_mb:.1f} MiB)", flush=True)
    print(f"[INFO] Version info: {version_path}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
