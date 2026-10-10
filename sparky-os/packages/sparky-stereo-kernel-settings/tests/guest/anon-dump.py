#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""Guest only, root: copy the resident anonymous memory of one user's
processes (the pages zram would hold) into OUT, up to LIMIT MiB.

anon-dump.py UID OUT LIMIT_MIB
"""
import os
import sys

uid, out, limit = int(sys.argv[1]), sys.argv[2], int(sys.argv[3]) << 20
page = os.sysconf("SC_PAGE_SIZE")
written = 0
with open(out, "wb") as target:
    for pid in sorted(int(name) for name in os.listdir("/proc") if name.isdigit()):
        try:
            if os.stat(f"/proc/{pid}").st_uid != uid:
                continue
            maps = open(f"/proc/{pid}/maps").read().splitlines()
            memory = os.open(f"/proc/{pid}/mem", os.O_RDONLY)
            pagemap = os.open(f"/proc/{pid}/pagemap", os.O_RDONLY)
        except OSError:
            continue
        for line in maps:
            fields = line.split()
            if "w" not in fields[1] or (len(fields) > 5 and not fields[5].startswith("[heap")):
                continue
            start, end = (int(value, 16) for value in fields[0].split("-"))
            for address in range(start, end, page):
                if written >= limit:
                    break
                entry = int.from_bytes(os.pread(pagemap, 8, address // page * 8), "little")
                if not entry & (1 << 63):
                    continue
                try:
                    data = os.pread(memory, page, address)
                except OSError:
                    continue
                target.write(data)
                written += len(data)
        os.close(memory)
        os.close(pagemap)
print(written)
