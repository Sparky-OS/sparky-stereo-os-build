#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later
"""Summarize complete trace rotations without truncating a boot's call history."""
import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path
import re


CALL = re.compile(
    r"^method call time=(\S+) sender=(\S+) .*? serial=(\d+) "
    r"path=([^;]+); interface=org\.freedesktop\.UDisks2\.Filesystem; "
    r"member=(Mount|Unmount)$"
)


def summarize(paths):
    boots = defaultdict(list)
    counts = Counter()
    for path in paths:
        with path.open() as stream:
            for number, line in enumerate(stream, 1):
                row = json.loads(line)
                row["source"] = f"{path.name}:{number}"
                boots[row["boot"]].append(row)
                counts[row["event"]] += 1

    summaries = []
    for boot, rows in boots.items():
        rows.sort(key=lambda row: row["monotonic"])
        snapshot = None
        calls = []
        transitions = []
        recoveries = []
        for row in rows:
            event = row["event"]
            if event == "snapshot":
                snapshot = {key: row[key] for key in
                            ("source", "monotonic", "reason", "mountinfo")}
                if not transitions or snapshot["mountinfo"] != transitions[-1]["mountinfo"]:
                    transitions.append(snapshot)
            elif event == "dbus":
                match = CALL.fullmatch(row["line"])
                if match:
                    realtime, sender, serial, path, member = match.groups()
                    calls.append(dict(source=row["source"], monotonic=row["monotonic"],
                                      bus_realtime=float(realtime), sender=sender,
                                      serial=int(serial), path=path, member=member,
                                      preceding_snapshot=snapshot))
            elif event == "caller" and calls and row["sender"] == calls[-1]["sender"]:
                calls[-1]["caller"] = {key: row[key] for key in
                                       ("source", "pid_reply", "result")}
            elif event == "remount-result":
                recoveries.append({key: row[key] for key in
                                   ("source", "monotonic", "result", "mounted", "stderr")})
        summaries.append(dict(boot=boot, records=len(rows),
                              first_realtime=rows[0]["realtime"],
                              last_realtime=rows[-1]["realtime"],
                              calls=calls, mount_transitions=transitions,
                              remount_results=recoveries))
    summaries.sort(key=lambda boot: boot["first_realtime"])
    return dict(records=sum(counts.values()), event_counts=dict(sorted(counts.items())),
                boots=summaries)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("traces", nargs="+", type=Path,
                        help="all retained trace.jsonl rotations, in any order")
    args = parser.parse_args()
    print(json.dumps(summarize(args.traces), indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
