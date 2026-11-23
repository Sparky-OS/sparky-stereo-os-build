#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Run only in the lane container with an isolated network and no input devices."""
from contextlib import ExitStack
from dataclasses import astuple
import os
from pathlib import Path
import select
import socket
import struct
import subprocess
import sys
import tempfile
import time

from foottroller_protocol import decode

HUB, MOCK, CONFIG = map(lambda item: Path(item).resolve(), sys.argv[1:])
DEST = ("127.0.0.1", 45041)
NEUTRAL = bytes((31, 128, 128, 0, 128, 0, 128, 0))
MOTION = bytes((31, 255, 0, 191, 160, 64, 96, 6))
TIMEOUT = 30


def records(events):
    return b"".join(struct.pack("=IhBB", 0, value, kind, ordinal)
                    for kind, ordinal, value in events)


INIT = records([(130, i, 0) for i in range(6)] + [(129, i, 0) for i in range(4)])
MOVE = records([(2, 0, 32767), (2, 1, -32768), (2, 2, 16384), (2, 3, -8192),
                (2, 4, -16384), (2, 5, 8192), (1, 1, 1), (1, 2, 1)])
RELEASE = records([(2, i, 0) for i in range(6)] + [(1, 1, 0), (1, 2, 0)])


def unity(data, ready):
    # FoottrollerNet.cs at f9182997, ReceiveData. The C# integer division on
    # TSRF and the precedence of the handshake over state parsing are explicit.
    if not ready and len(data) == 2:
        return data == bytes((1, 2))
    if ready and len(data) == 8 and data[0] == 31:
        return ((data[1] - 128) / 128.0, (data[2] - 128) / 128.0,
                data[3] * 360.0 / 255.0, data[4] - 128,
                data[5] * 360.0 / 255.0, data[6] - 128,
                (data[7] & 0x0C) // 4, data[7] & 0x03)
    return None


def pair(stack):
    for _ in range(128):
        sender = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        listener = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sender.bind(("127.0.0.1", 0))
        try:
            listener.bind(("127.0.0.1", sender.getsockname()[1] + 1))
        except (OSError, OverflowError):
            sender.close()
            listener.close()
            continue
        stack.enter_context(sender)
        stack.enter_context(listener)
        listener.settimeout(TIMEOUT)
        return sender, listener
    raise AssertionError("Could not reserve adjacent client ports")


def receive(listener, expected):
    deadline = time.monotonic() + TIMEOUT
    while time.monotonic() < deadline:
        data, address = listener.recvfrom(100)
        assert address == DEST, address
        if data == expected:
            return data
    raise AssertionError(f"Did not get {expected.hex()}")


def drain(listener):
    packets = []
    listener.setblocking(False)
    try:
        while True:
            try:
                packets.append(listener.recv(100))
            except BlockingIOError:
                return packets
    finally:
        listener.settimeout(TIMEOUT)


def environment(trace, **options):
    return dict(os.environ, LD_PRELOAD=str(MOCK), FT37_TRACE=str(trace), **options)


def invocation(config, path):
    return [HUB, "--config", config, "--replay", path]


def run_red(root, config, name, expected, raw=None, **options):
    trace = root / f"{name}.trace"
    file = root / name
    if raw is not None:
        file.write_bytes(raw)
    result = subprocess.run(invocation(config, file),
                            env=environment(trace, **options), capture_output=True,
                            text=True, timeout=TIMEOUT)
    assert result.returncode == 1, (name, result)
    assert expected in result.stderr, (name, result.stderr)
    return trace


def connect(sender, listener):
    sender.sendto(b"\x01\x02", DEST)
    data, address = listener.recvfrom(100)
    assert address == DEST and unity(data, False) is True, (data, address)


def prove_live(root, config, settings_override=False):
    fifo = root / "events"
    os.mkfifo(fifo)
    trace = root / "green.trace"
    log = root / "green.log"
    with ExitStack() as stack:
        writer = os.open(fifo, os.O_RDWR | os.O_NONBLOCK)
        stack.callback(os.close, writer)
        child_log = stack.enter_context(log.open("w"))
        process = subprocess.Popen(invocation(config, fifo), stderr=child_log,
                                   env=environment(trace))
        try:
            os.write(writer, INIT)
            deadline = time.monotonic() + TIMEOUT
            while "Hub ready" not in log.read_text():
                assert process.poll() is None, log.read_text()
                assert time.monotonic() < deadline, log.read_text()
                time.sleep(0.025)

            source, listener = pair(stack)
            stranger, stray = pair(stack)
            for packet in (b"", b"\x01", b"\x01\x02\x00", b"\x02\x02", b"\x01\x21", b"\x01\x15"):
                stranger.sendto(packet, DEST)
            # Our valid request is queued after the malformed packets above.
            # Its response marks completion of the server's reads.
            connect(source, listener)
            assert not select.select([source, stranger, stray], [], [], 0)[0], "Reply to bad request or to sending port"
            assert astuple(decode(receive(listener, NEUTRAL))) == unity(NEUTRAL, True)

            os.write(writer, MOVE[:3])
            receive(listener, NEUTRAL)
            os.write(writer, MOVE[3:])
            if settings_override:
                # Y is inverted and the two foot pairs are swapped.
                expected = bytes((31, 255, 255, 64, 96, 191, 160, 6))
            else:
                expected = MOTION
            data = receive(listener, expected)
            assert unity(data, True) == astuple(decode(data))
            assert unity(data[:-1], True) is None
            try:
                decode(data[:-1])
            except ValueError:
                pass
            else:
                raise AssertionError("Earlier decoder accepted a truncated output")
            print(f"UDP received and decoded {data.hex()} at source port + 1", flush=True)

            if settings_override:
                os.write(writer, records([(2, 0, 4096)]))
                receive(listener, bytes((31, 128, 255, 64, 96, 191, 160, 6)))
            else:
                connect(stranger, stray)
                receive(stray, MOTION)
                lease_start = time.monotonic()
                # Renew one peer beyond the 15 s initial lease. A second peer
                # receives no heartbeat and must expire.
                while time.monotonic() - lease_start < 17:
                    source.sendto(b"\x01\x15", DEST)
                    receive(listener, MOTION)
                    time.sleep(2)
                    drain(listener)
                    drain(stray)
                os.write(writer, RELEASE)
                receive(listener, NEUTRAL)
                # Stop refreshing the expired client only after proving the
                # neutral sample is absent from its accumulated datagrams.
                assert NEUTRAL not in drain(stray)
                connect(stranger, stray)
                receive(stray, NEUTRAL)
                print("Heartbeat renewed one peer, unrenewed peer expired and reconnected", flush=True)
            process.terminate()
            assert process.wait(TIMEOUT) == 0, log.read_text()
        finally:
            if process.poll() is None:
                process.kill()
                process.wait(TIMEOUT)
    return trace.read_text().splitlines()


def main():
    assert not Path("/dev/uinput").exists() and not Path("/dev/input").exists()
    with tempfile.TemporaryDirectory(prefix="foottroller-proof-") as work:
        root = Path(work)
        config = root / "hub.conf"
        config.write_text(CONFIG.read_text().replace("0.0.0.0", "127.0.0.1"))
        chooser = subprocess.run([HUB, "--config", config], capture_output=True, text=True, timeout=TIMEOUT)
        assert chooser.returncode == 1 and "Select the Crampon with --device" in chooser.stderr, chooser
        assert not run_red(root, config, "absent", "Cannot open the selected joystick").exists()
        wrong_mode = records([(130, 0, 0), (130, 1, 0)])
        assert not run_red(root, config, "wrong-mode", "lacks the configured Dev mode", wrong_mode).exists()
        broken = run_red(root, config, "broken-record", "Invalid joystick record", INIT + MOVE[:3])
        assert broken.read_text().splitlines()[-2:] == ["DESTROY", "CLOSE"]
        failed = run_red(root, config, "uinput-refused", "Cannot create the virtual gamepad",
                         INIT, FT37_FAIL_CREATE="1")
        assert failed.read_text().splitlines()[-2:] == ["CREATE FAILED", "CLOSE"]
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as busy:
            busy.bind(DEST)
            assert not run_red(root, config, "busy-socket", "Cannot open UDP 45041", INIT).exists()
        print("Absent, wrong mode, truncated record, rejected uinput and occupied UDP port returned 1", flush=True)

        lines = prove_live(root, config)
        assert lines == [
            "OPEN /dev/uinput 1", "EVBIT 3", "EVBIT 1",
            "ABSBIT 0", "ABSSETUP 0 -32767 32767", "ABSBIT 1", "ABSSETUP 1 -32767 32767",
            "KEYBIT 304", "KEYBIT 305", "KEYBIT 307", "KEYBIT 308",
            "SETUP 6 0 0 1 Foottroller Hub Gamepad", "CREATE", "SYSNAME",
            "EVENT 3 0 32767", "EVENT 0 0 0", "EVENT 3 1 -32767", "EVENT 0 0 0",
            "EVENT 1 305 1", "EVENT 0 0 0", "EVENT 1 307 1", "EVENT 0 0 0",
            "EVENT 3 0 0", "EVENT 0 0 0", "EVENT 3 1 0", "EVENT 0 0 0",
            "EVENT 1 305 0", "EVENT 0 0 0", "EVENT 1 307 0", "EVENT 0 0 0",
            "DESTROY", "CLOSE",
        ], "\n".join(lines)
        print("\n".join(lines))
        alternate = root / "alternate"
        alternate.mkdir()
        adjusted = root / "adjusted.conf"
        adjusted.write_text(config.read_text()
                            .replace("axis_left_heading = 2", "axis_left_heading = 4")
                            .replace("axis_right_heading = 4", "axis_right_heading = 2")
                            .replace("axis_left_tilt = 3", "axis_left_tilt = 5")
                            .replace("axis_right_tilt = 5", "axis_right_tilt = 3")
                            .replace("invert_y = false", "invert_y = true")
                            .replace("deadzone_x = 0", "deadzone_x = 0.2"))
        lines = prove_live(alternate, adjusted, settings_override=True)
        assert "EVENT 3 1 32767" in lines and "EVENT 3 0 0" in lines, lines
        assert lines[-2:] == ["DESTROY", "CLOSE"], lines
        print("Foot-pair swap, inversion and dead zone verified; shutdown destroyed gamepad")


if __name__ == "__main__":
    main()
