#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/25
# Copyright 2026 under the GNU GPL3 License
# ORDER 664: the modalias functions of drivers/input/input.c, their own text, against a shim that has the kernel's
# size check of vsnprintf() (lib/vsprintf.c: "if (WARN_ON_ONCE(size > INT_MAX)) return 0;"). No kernel is built.
#   run.sh INPUT_C            prints "warnings N measured M printed P" for a device with 1 and with 128 buttons
#   exit status 0 when no call warned and the measured length equals the printed one, else 1
# The functions are taken unchanged, each from its definition line to the first line that is exactly "}".
set -euo pipefail
SRC=$(realpath "${1:?drivers/input/input.c of the tree to prove}")
HERE=$(cd "$(dirname "$0")" && pwd)
W=$(mktemp -d /tmp/ev-btn-modalias.XXXXXX)
trap 'rm -rf "${W:?}"' EXIT
python3 -I - "$SRC" > "$W/functions.c" <<'PY'
import re, sys
text = open(sys.argv[1]).read().split('\n')
for name in ('input_print_modalias_bits', 'input_print_modalias_parts', 'input_print_modalias'):
    start = next(i for i, line in enumerate(text) if re.match(r'static int %s\(' % name, line))
    end = next(i for i in range(start, len(text)) if text[i] == '}')
    print('\n'.join(text[start:end + 1]) + '\n')
PY
grep -c 'button_count' "$W/functions.c" >/dev/null || { echo "this tree's modalias has no button count (the EV_BTN series is not applied)" >&2; exit 2; }
gcc -O1 -Wall -Wno-unused-function -o "$W/prove" "$HERE/shim.c" -DFUNCTIONS="\"$W/functions.c\""
"$W/prove"
