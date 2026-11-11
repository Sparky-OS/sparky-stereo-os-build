#!/bin/bash
# Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT
# The order the Graphics page's answer gives a list of GPUs, and what it answered, without any GPU: a fake
# sparky-stereo-gpu-env answers. A page that fails, answers nothing or names a GPU that is not here is said, and the
# order is left as it was (the caller then decodes on no other GPU; ORDER 346a).
# Usage: page-order.sh PATH-TO-page-order-test
set -u
TEST=${1:?}
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0 fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL $1: got '$2', expected '$3'"; fi; }
fake() { mkdir -p "$T/bin"; printf '#!/bin/sh\n%s\n' "$1" >"$T/bin/sparky-stereo-gpu-env"; chmod +x "$T/bin/sparky-stereo-gpu-env"; }
run() { env PATH="$T/bin:/usr/bin:/bin" "$@" "$TEST" /dev/dri/renderD128 /dev/dri/renderD129 /dev/dri/renderD130 2>/dev/null; }
check "no page installed: unchanged, not asked" "$(run)" "/dev/dri/renderD128 /dev/dri/renderD129 /dev/dri/renderD130 | not-asked"
fake "echo /dev/dri/renderD130"
check "the last named: first, the others keep their order" "$(run)" "/dev/dri/renderD130 /dev/dri/renderD128 /dev/dri/renderD129 | named"
fake "echo /dev/dri/renderD129"
check "the middle named" "$(run)" "/dev/dri/renderD129 /dev/dri/renderD128 /dev/dri/renderD130 | named"
fake "echo /dev/dri/renderD128"
check "the first named: unchanged" "$(run)" "/dev/dri/renderD128 /dev/dri/renderD129 /dev/dri/renderD130 | named"
fake "echo /dev/dri/renderD999"
check "a GPU that is not here: said" "$(run)" "/dev/dri/renderD128 /dev/dri/renderD129 /dev/dri/renderD130 | not-found /dev/dri/renderD999"
fake "echo /dev/dri/renderD130; exit 3"
check "the page fails: said with its status" "$(run)" "/dev/dri/renderD128 /dev/dri/renderD129 /dev/dri/renderD130 | failed 3"
fake "echo 'the chosen GPU is not here' >&2; exit 4"
check "the chosen GPU cannot be used (exit 4): said" "$(run)" "/dev/dri/renderD128 /dev/dri/renderD129 /dev/dri/renderD130 | failed 4"
check "the page's own words reach the program's stderr" "$(env PATH="$T/bin:/usr/bin:/bin" "$TEST" /dev/dri/renderD128 2>&1 >/dev/null)" "the chosen GPU is not here"
fake ":"
check "the page answers nothing: said" "$(run)" "/dev/dri/renderD128 /dev/dri/renderD129 /dev/dri/renderD130 | failed 0"
check "one GPU: the page is asked too" "$(env PATH="$T/bin:/usr/bin:/bin" "$TEST" /dev/dri/renderD128 2>/dev/null)" "/dev/dri/renderD128 | failed 0"
fake "echo /dev/dri/renderD130"
for assignment in DRI_PRIME=1 MESA_VK_DEVICE_SELECT=1002:1638 VK_LOADER_DRIVERS_SELECT='*radeon*' __NV_PRIME_RENDER_OFFLOAD=1; do
	check "$assignment set at launch: unchanged, not asked" "$(run "$assignment")" "/dev/dri/renderD128 /dev/dri/renderD129 /dev/dri/renderD130 | not-asked"
done
echo "page-order: $pass passed, $fail failed"
[ "$fail" = 0 ]
