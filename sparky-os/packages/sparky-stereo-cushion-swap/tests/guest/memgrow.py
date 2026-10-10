#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""Guest only: allocate and touch MIB of anonymous memory at RATE MiB/s
(0: as fast as the CPU can), hold it HOLD seconds, report on stdout.
The OOM killer is asked to pick this process first.

memgrow.py RATE MIB HOLD [mixed]

mixed: each page is 1 KiB of random bytes and 3 KiB of zeros, so it
compresses about as much as desktop memory does, not to nothing.
"""
import mmap
import os
import sys
import time

rate, total, hold = float(sys.argv[1]), int(sys.argv[2]), float(sys.argv[3])
mixed = len(sys.argv) > 4 and sys.argv[4] == "mixed"
with open("/proc/self/oom_score_adj", "w") as handle:
    handle.write("1000")
chunk = 32
pages = (chunk << 20) // mmap.PAGESIZE
maps = []
start = time.monotonic()
done = 0
while done < total:
    area = mmap.mmap(-1, chunk << 20, flags=mmap.MAP_PRIVATE | mmap.MAP_ANONYMOUS)
    if mixed:
        for offset in range(0, chunk << 20, mmap.PAGESIZE):
            area[offset:offset + 1024] = os.urandom(1024)
    else:
        area[::mmap.PAGESIZE] = b"\x01" * pages
    maps.append(area)
    done += chunk
    if rate:
        delay = start + done / rate - time.monotonic()
        if delay > 0:
            time.sleep(delay)
print(f"reached {done} MiB in {time.monotonic() - start:.3f} s", flush=True)
time.sleep(hold)
print("released", flush=True)
