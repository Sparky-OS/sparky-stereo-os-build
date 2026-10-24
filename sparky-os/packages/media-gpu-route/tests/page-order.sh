#!/bin/bash
# Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT
# The order the Graphics page's answer gives a list of GPUs, without any GPU: a fake sparky-stereo-gpu-env answers.
# Usage: page-order.sh PATH-TO-page-order-test
set -u
TEST=${1:?}
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
pass=0 fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL $1: got '$2', expected '$3'"; fi; }
fake() { mkdir -p "$T/bin"; printf '#!/bin/sh\n%s\n' "$1" >"$T/bin/sparky-stereo-gpu-env"; chmod +x "$T/bin/sparky-stereo-gpu-env"; }
run() { env PATH="$T/bin:/usr/bin:/bin" "$@" "$TEST" /dev/dri/renderD128 /dev/dri/renderD129 /dev/dri/renderD130; }
check "no page: unchanged" "$(run)" "/dev/dri/renderD128 /dev/dri/renderD129 /dev/dri/renderD130"
fake "echo /dev/dri/renderD130"
check "the last named: first, the others keep their order" "$(run)" "/dev/dri/renderD130 /dev/dri/renderD128 /dev/dri/renderD129"
fake "echo /dev/dri/renderD129"
check "the middle named" "$(run)" "/dev/dri/renderD129 /dev/dri/renderD128 /dev/dri/renderD130"
fake "echo /dev/dri/renderD128"
check "the first named: unchanged" "$(run)" "/dev/dri/renderD128 /dev/dri/renderD129 /dev/dri/renderD130"
fake "echo /dev/dri/renderD999"
check "a GPU that is not here: unchanged" "$(run)" "/dev/dri/renderD128 /dev/dri/renderD129 /dev/dri/renderD130"
fake "echo /dev/dri/renderD130; exit 3"
check "the page fails: unchanged" "$(run)" "/dev/dri/renderD128 /dev/dri/renderD129 /dev/dri/renderD130"
fake "echo /dev/dri/renderD130"
for assignment in DRI_PRIME=1 MESA_VK_DEVICE_SELECT=1002:1638 VK_LOADER_DRIVERS_SELECT='*radeon*' __NV_PRIME_RENDER_OFFLOAD=1; do
	check "$assignment set at launch: unchanged" "$(run "$assignment")" "/dev/dri/renderD128 /dev/dri/renderD129 /dev/dri/renderD130"
done
echo "page-order: $pass passed, $fail failed"
[ "$fail" = 0 ]
