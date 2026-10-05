#!/usr/bin/env python3
import argparse
import os
import signal
import subprocess
import sys
import time


def wait_for_socket(path, timeout=30):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if os.path.exists(path):
            return
        time.sleep(0.1)
    raise RuntimeError(f"Wayland socket did not appear: {path}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("video")
    parser.add_argument("capture")
    parser.add_argument("--evidence", required=True)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--vo", default="dmabuf-wayland")
    parser.add_argument("--frames", help="directory of the source stereo frames")
    args = parser.parse_args()

    runtime_dir = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime_dir:
        raise RuntimeError("XDG_RUNTIME_DIR must be set")
    socket_path = os.path.join(runtime_dir, "wayland-0")
    if os.path.isdir(socket_path):
        raise RuntimeError(f"Wayland socket path is a directory: {socket_path}")
    try:
        os.unlink(socket_path)
    except FileNotFoundError:
        pass

    kwin_log = open(os.path.join(args.evidence, "kwin.log"), "w")
    mpv_log = open(os.path.join(args.evidence, "mpv.log"), "w")
    kwin_environment = os.environ.copy()
    kwin_environment.pop("QT_QPA_PLATFORM", None)
    kwin_environment["KWIN_SCREENSHOT_NO_PERMISSION_CHECKS"] = "1"
    kwin = subprocess.Popen(
        [
            "kwin_wayland",
            "--virtual",
            "--xwayland",
            "--width=1024",
            "--height=640",
        ],
        env=kwin_environment,
        stdout=kwin_log,
        stderr=subprocess.STDOUT,
    )
    try:
        wait_for_socket(socket_path)
        environment = os.environ.copy()
        environment["WAYLAND_DISPLAY"] = "wayland-0"
        environment["WAYLAND_DEBUG"] = "client"
        mpv = subprocess.Popen(
            [
                "mpv",
                "--no-config",
                "--no-audio",
                f"--vo={args.vo}",
                "--fullscreen",
                "--video-unscaled=yes",
                "--no-osc",
                "--no-osd-bar",
                "--loop-file=inf",
                args.video,
            ],
            env=environment,
            stdout=mpv_log,
            stderr=subprocess.STDOUT,
        )
        time.sleep(3)
        capture_env = environment.copy()
        capture_env["QT_QPA_PLATFORM"] = "offscreen"
        capture_process = subprocess.run(
            [sys.executable, os.path.join(os.path.dirname(__file__), "capture_screen.py"), args.capture],
            env=capture_env,
            check=True,
        )
        if args.check:
            if not args.frames:
                raise RuntimeError("--check needs --frames")
            subprocess.run(
                [
                    sys.executable,
                    os.path.join(os.path.dirname(__file__), "check_playback_capture.py"),
                    args.capture,
                    "--evidence",
                    os.path.join(args.evidence, "playback-capture.json"),
                    "--metadata",
                    args.capture + ".json",
                    "--mpv-log",
                    os.path.join(args.evidence, "mpv.log"),
                    "--frames",
                    args.frames,
                ],
                env=capture_env,
                check=True,
            )
        mpv.send_signal(signal.SIGTERM)
        mpv.wait(timeout=5)
    finally:
        if kwin.poll() is None:
            kwin.terminate()
            try:
                kwin.wait(timeout=5)
            except subprocess.TimeoutExpired:
                kwin.kill()
                kwin.wait()
        kwin_log.close()
        mpv_log.close()
        try:
            os.unlink(socket_path)
        except FileNotFoundError:
            pass


if __name__ == "__main__":
    sys.exit(main())
