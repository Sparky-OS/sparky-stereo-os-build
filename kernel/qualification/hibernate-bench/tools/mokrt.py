#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""mokrt.py VARS.fd : copy the MokList variable of an OVMF variable store to MokListRT (non-volatile, boot + runtime).

shim copies the MOK database it read at boot into the runtime variable MokListRT; the kernel reads that one
(security/integrity/platform_certs/load_uefi.c). The bench boots without shim, so this stand-in gives the kernel the
same variable. The bench therefore tests the kernel half of the MOK path, not shim itself."""
import json, subprocess, sys, tempfile, os

vars_fd = sys.argv[1]
with tempfile.TemporaryDirectory() as d:
    j = os.path.join(d, "v.json")
    subprocess.run(["virt-fw-vars", "--input", vars_fd, "--output-json", j], check=True, capture_output=True)
    doc = json.load(open(j))
    mok = [v for v in doc["variables"] if v["name"] == "MokList"]
    if not mok:
        sys.exit("no MokList variable in " + vars_fd)
    rt = dict(mok[0]); rt["name"] = "MokListRT"; rt["attr"] = 7   # NV | BS | RT
    out = os.path.join(d, "rt.json")
    json.dump({"version": doc.get("version", 2), "variables": [rt]}, open(out, "w"))
    subprocess.run(["virt-fw-vars", "--input", vars_fd, "--output", vars_fd + ".new", "--set-json", out], check=True, capture_output=True)
os.replace(vars_fd + ".new", vars_fd)
