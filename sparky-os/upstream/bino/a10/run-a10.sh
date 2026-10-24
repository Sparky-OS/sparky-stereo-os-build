#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
export LC_ALL=C.UTF-8
cd -- "$(dirname -- "$0")"
sha256sum -c SHA256SUMS
exec python3 "$PWD/inhibit.py" "$@"
