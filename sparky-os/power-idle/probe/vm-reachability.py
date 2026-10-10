#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-2.0-or-later
"""Check the documented development VM endpoint without authenticating."""

import argparse
import datetime
import json
import socket
import sys
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
result = {
    "utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "endpoint": "127.0.0.1:2222",
}
try:
    with socket.create_connection(("127.0.0.1", 2222), timeout=3) as connection:
        banner = connection.recv(255)
        if not banner.startswith(b"SSH-"):
            raise RuntimeError("The endpoint did not return an SSH banner")
        result["ssh_banner_received"] = True
except (OSError, RuntimeError) as error:
    result["ssh_banner_received"] = False
    result["error"] = str(error)
    if isinstance(error, OSError):
        result["errno"] = error.errno
args.output.write_text(json.dumps(result, indent=2) + "\n")
print(args.output.read_text(), end="")
sys.exit(0 if result["ssh_banner_received"] else 2)
