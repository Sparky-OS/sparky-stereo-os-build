#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""Check guest-probe detection and wire decoding; this is not a VM result."""

import copy
import importlib.util
import json
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch
from pathlib import Path

spec = importlib.util.spec_from_file_location("guest_tty", Path(__file__).with_name("guest-tty.py"))
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class Detection(unittest.TestCase):
    def setUp(self):
        self.baseline = {"consoles": {"1": {"kd_mode": 0, "screen_sha256": "one"},
                                     "2": {"kd_mode": 0, "screen_sha256": "two"}},
                         "consoleblank": "0", "blanked_vt": 0,
                         "power": {"/sys/class/graphics/fb0/blank": "0"},
                         "screensaver_processes": []}

    def test_unchanged(self):
        probe.check_snapshot(self.baseline, copy.deepcopy(self.baseline), True)

    def test_each_console_is_detected(self):
        for number in (1, 2):
            state = copy.deepcopy(self.baseline)
            state["blanked_vt"] = number
            with self.assertRaisesRegex(probe.Mismatch, f"tty{number} was blanked"):
                probe.check_snapshot(self.baseline, state, True)

    def test_ioctl_return_value_is_not_the_argument_buffer(self):
        def ioctl(fd, request, argument, mutate=True):
            return 2 if isinstance(argument, bytearray) and mutate else bytes(argument)

        with patch.object(probe.fcntl, "ioctl", ioctl):
            state = copy.deepcopy(self.baseline)
            state["blanked_vt"] = probe.blanked_vt(10)
            json.dumps(state)
            with self.assertRaisesRegex(probe.Mismatch, "tty2 was blanked"):
                probe.check_snapshot(self.baseline, state, True)

    def test_console_contents_and_mode(self):
        for key, value in (("screen_sha256", "changed"), ("kd_mode", 1)):
            state = copy.deepcopy(self.baseline)
            state["consoles"]["2"][key] = value
            with self.assertRaisesRegex(probe.Mismatch, "consoles changed"):
                probe.check_snapshot(self.baseline, state, True)

    def test_blanking_interval(self):
        state = copy.deepcopy(self.baseline)
        state["consoleblank"] = "60"
        with self.assertRaisesRegex(probe.Mismatch, "consoleblank changed"):
            probe.check_snapshot(self.baseline, state, True)

    def test_console_power(self):
        state = copy.deepcopy(self.baseline)
        state["power"]["/sys/class/graphics/fb0/blank"] = "4"
        with self.assertRaisesRegex(probe.Mismatch, "power state changed"):
            probe.check_snapshot(self.baseline, state, True)
        probe.check_snapshot(self.baseline, state, False)

    def test_screensaver(self):
        state = copy.deepcopy(self.baseline)
        state["screensaver_processes"] = [{"name": "xscreensaver"}]
        with self.assertRaisesRegex(probe.Mismatch, "process is running"):
            probe.check_snapshot(self.baseline, state, True)

    def test_container_is_not_a_vm_result(self):
        with tempfile.TemporaryDirectory() as directory:
            for flags in ([], ["--negative"]):
                output = Path(directory) / "result.json"
                result = subprocess.run([sys.executable, str(Path(__file__).with_name("guest-tty.py")),
                                         str(output), *flags], capture_output=True)
                self.assertEqual(result.returncode, 2)
                evidence = json.loads(output.read_text())
                self.assertFalse(evidence["verified"])
                self.assertNotIn("negative_injected", evidence)


class Protocol(unittest.TestCase):
    def test_read_only_wire_protocol(self):
        errors = []
        with tempfile.TemporaryDirectory() as directory:
            path = str(Path(directory) / "wayland")
            server = socket.socket(socket.AF_UNIX)
            server.bind(path)
            server.listen(1)

            def serve():
                try:
                    connection, address = server.accept()
                    connection.settimeout(5)
                    with connection:
                        buffer = b""
                        manager = None
                        registry = None
                        binds = 0

                        def send(target, opcode, payload):
                            connection.sendall(struct.pack("=II", target, ((len(payload) + 8) << 16) | opcode) + payload)

                        while True:
                            while len(buffer) < 8:
                                data = connection.recv(4096)
                                if not data:
                                    self.assertEqual(binds, 1)
                                    return
                                buffer += data
                            target, word = struct.unpack_from("=II", buffer)
                            size, opcode = word >> 16, word & 0xFFFF
                            while len(buffer) < size:
                                buffer += connection.recv(4096)
                            payload, buffer = buffer[8:size], buffer[size:]
                            if target == 1 and opcode == 1:
                                registry = struct.unpack("=I", payload)[0]
                                for name, interface in ((10, "org_kde_kwin_dpms_manager"), (11, "wl_output")):
                                    send(registry, 0, struct.pack("=I", name) + probe.DpmsReader.string(interface) + struct.pack("=I", 1))
                            elif target == 1 and opcode == 0:
                                callback = struct.unpack("=I", payload)[0]
                                send(callback, 0, struct.pack("=I", 0))
                            elif target == registry:
                                self.assertEqual(opcode, 0)
                                name, length = struct.unpack_from("=II", payload)
                                version, identifier = struct.unpack_from("=II", payload, 8 + ((length + 3) & ~3))
                                self.assertEqual(version, 1)
                                if name == 10:
                                    manager = identifier
                                else:
                                    self.assertEqual(name, 11)
                            elif target == manager:
                                self.assertEqual(opcode, 0)
                                identifier, output = struct.unpack("=II", payload)
                                send(identifier, 0, struct.pack("=I", 1))
                                send(identifier, 1, struct.pack("=I", 3))
                                send(identifier, 2, b"")
                                binds += 1
                            else:
                                self.fail("The observer sent a DPMS set or unexpected request")
                except Exception as error:
                    errors.append(error)

            thread = threading.Thread(target=serve)
            thread.start()
            try:
                self.assertEqual(probe.DpmsReader(path).read(), [{"global": 11, "supported": 1, "mode": 3}])
            finally:
                thread.join(timeout=6)
                server.close()
            self.assertFalse(thread.is_alive())
            self.assertEqual(errors, [])


if __name__ == "__main__":
    assert Path("/.dockerenv").exists(), "Run logic checks in Docker"
    unittest.main()
