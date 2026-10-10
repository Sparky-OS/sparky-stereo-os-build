#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""Replay recorded memory races through Daniel's decision rules.

analyze-race.py HARD_KIB SOFT_KIB RATE_KIB SWAPON_MS RUN_DIR...

For each run (race.sh output): when the floors were crossed, when PSI first
fired, when the allocation ended, and for which share of start phases a
3 s poller, a 0.5 s poller and the PSI wake-up (with a 10 s tick) decide to
deploy at least SWAPON_MS before the end.
"""
import gzip
import json
import sys
from pathlib import Path

hard, soft, rate, swapon_ms = (int(value) for value in sys.argv[1:5])
WINDOW = 10.0


def decide(samples):
    """First sample time at which Daniel's rules deploy, or None."""
    previous = None
    for t, avail in samples:
        if avail < hard:
            return t
        if previous and avail < soft:
            dt = t - previous[0]
            drop = previous[1] - avail
            if dt > 0 and drop > 0 and drop * WINDOW >= rate * dt:
                return t
        previous = (t, avail)
    return None


def at(rows, t):
    best = rows[0]
    for row in rows:
        if row[0] > t:
            break
        best = row
    return best


def poller(rows, end, interval, phase):
    times = []
    t = phase
    while t <= end:
        times.append(t)
        t += interval
    return decide([(time, at(rows, time)[1]) for time in times])


def psi_mode(rows, end, phase):
    times = sorted({row[0] for row in rows if row[3] and row[0] <= end} |
                   {phase + 10.0 * k for k in range(int(end / 10.0) + 2) if phase + 10.0 * k <= end})
    return decide([(time, at(rows, time)[1]) for time in times])


result = []
for directory in map(Path, sys.argv[5:]):
    sample = directory / "sample.json"
    data = json.loads(sample.read_text() if sample.exists() else gzip.decompress((directory / "sample.json.gz").read_bytes()))
    rows = data["rows"]
    run = dict(item.split("=", 1) for item in (directory / "run.txt").read_text().split())
    status = int((directory / "grow.status").read_text())
    killed = "Killed process" in (directory / "oom.txt").read_text() or status != 0
    # the end: the lowest MemAvailable before the allocation was released
    end_row = min(rows, key=lambda row: row[1])
    end = end_row[0]
    crossing = lambda limit: next((row[0] for row in rows if row[1] < limit), None)
    psi = [row[0] for row in rows if row[3]]
    first_psi = psi[0] if psi else None
    entry = {
        "run": directory.name, "rate_mib_s": run["rate"], "killed": killed, "grow_status": status,
        "mem_total_kib": data["mem_total_kib"], "start_avail_kib": rows[0][1], "min_avail_kib": end_row[1],
        "end_s": end, "soft_cross_s": crossing(soft), "hard_cross_s": crossing(hard),
        "first_psi_s": first_psi, "avail_at_first_psi_kib": at(rows, first_psi)[1] if psi else None,
        "psi_events_before_end": sum(1 for t in psi if t <= end),
    }
    deadline = end - swapon_ms / 1000.0
    for name, interval in (("poll_3s", 3.0), ("poll_0_5s", 0.5)):
        phases = [i * interval / 100 for i in range(100)]
        decisions = [poller(rows, end, interval, phase) for phase in phases]
        entry[name + "_in_time"] = sum(1 for d in decisions if d is not None and d <= deadline) / len(phases)
    phases = [i * 0.1 for i in range(100)]
    decisions = [psi_mode(rows, end, phase) for phase in phases]
    entry["psi_tick10s_in_time"] = sum(1 for d in decisions if d is not None and d <= deadline) / len(phases)
    entry["psi_only_decision_s"] = decide([(t, at(rows, t)[1]) for t in psi if t <= end])
    result.append(entry)
print(json.dumps(result, indent=1))
