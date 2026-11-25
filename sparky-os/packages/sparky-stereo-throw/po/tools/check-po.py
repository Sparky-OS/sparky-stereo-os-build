#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-2.0-or-later
"""Fails when a language lacks a sentence, a translation drops or adds a %N, or "Throw" is translated away.
Exit status: the number of faults."""
import os
import re
import sys

# check-po.py [STRINGS_FILE]: the table to check (strings.py beside this script by default)
import importlib.util  # noqa: E402

path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "strings.py")
spec = importlib.util.spec_from_file_location("strings", path)
strings = importlib.util.module_from_spec(spec)
spec.loader.exec_module(strings)

faults = 0
for group in ("DAEMON", "PAGE"):
    for ctx, msgid, tr in getattr(strings, group, []):
        want = sorted(re.findall(r"%\d", msgid))
        for lang in strings.LANGS:
            text = tr.get(lang)
            problem = None
            if not text:
                problem = "missing"
            elif sorted(re.findall(r"%\d", text)) != want:
                found = sorted(re.findall(r"%\d", text))
                problem = f"placeholders {found} != {want}"
            elif "Throw" in msgid and "Throw" not in text:
                problem = "the name Throw is not kept"
            if problem:
                faults += 1
                print(f"FAIL {lang}: {problem}: {msgid[:60]}")
print(f"RESULT: {'PASS' if not faults else 'FAIL'} ({faults} faults)")
sys.exit(faults)
