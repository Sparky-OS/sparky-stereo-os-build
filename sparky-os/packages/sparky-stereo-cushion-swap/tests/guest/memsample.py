#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""Guest only: MemAvailable every 20 ms, PSI trigger events, swap use.

memsample.py OUT.json SECONDS [TRIGGER]  (stops early when OUT.json.stop exists)
"""
import json
import os
import select
import sys
import time

out, duration = sys.argv[1], float(sys.argv[2])
trigger = sys.argv[3] if len(sys.argv) > 3 else "some 150000 1000000"
fd = os.open("/proc/pressure/memory", os.O_RDWR | os.O_NONBLOCK)
os.write(fd, trigger.encode() + b"\0")
poller = select.poll()
poller.register(fd, select.POLLPRI)
meminfo = os.open("/proc/meminfo", os.O_RDONLY)
rows = []
start = time.monotonic()
while time.monotonic() - start < duration and not os.path.exists(out + ".stop"):
    events = poller.poll(20)
    now = time.monotonic() - start
    data = os.pread(meminfo, 8192, 0).decode()
    fields = dict(line.split(":", 1) for line in data.splitlines())
    kib = lambda name: int(fields[name].split()[0])
    rows.append([round(now, 3), kib("MemAvailable"), kib("SwapTotal") - kib("SwapFree"), 1 if events else 0])
with open(out, "w") as handle:
    json.dump({"trigger": trigger, "mem_total_kib": kib("MemTotal"),
               "columns": ["t", "mem_available_kib", "swap_used_kib", "psi_event"], "rows": rows}, handle)
