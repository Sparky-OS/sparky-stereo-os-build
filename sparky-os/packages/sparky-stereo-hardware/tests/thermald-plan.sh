#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/26
# Copyright 2026 under the GNU GPL3 License
# thermald on a processor that is not Intel's goes only when removing it removes it alone and brings nothing in: apt's plan
# is read by every kind of line (ORDER 675, continuation 3). Doubles for dpkg-query, apt-mark and apt-get; the step's own
# answer read from its check, which says nothing when there is nothing to do. Run in a container whose processor is not an
# Intel one (the check reads /proc/cpuinfo).
#   thermald-plan.sh PATH/TO/sparky-stereo-hardware-recipe
set -u
[ -e /.dockerenv ] || { echo "run in a container" >&2; exit 2; }
P=$(cd "${1:?the recipe folder}" && pwd)
grep -qs '^vendor_id[[:space:]]*:[[:space:]]*GenuineIntel' /proc/cpuinfo && { echo "this test needs a processor that is not Intel's" >&2; exit 2; }
T=$(mktemp -d) || exit 2
trap 'rm -rf "${T:?}"' EXIT
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1: got [$2], want [$3]"; fails=$((fails + 1)); fi; }
mkdir -p "$T/bin"
printf '#!/bin/sh\necho installed\n' > "$T/bin/dpkg-query"
printf '#!/bin/sh\n[ "$1" = showauto ] && echo thermald\nexit 0\n' > "$T/bin/apt-mark"
printf '#!/bin/sh\ncat %s\n' "$T/plan" > "$T/bin/apt-get"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/logger"
chmod 755 "$T"/bin/*
step() { PATH=$T/bin:$PATH bash "$P/bin/sparky-stereo-thermald-manual" check 2>&1 | grep -c 'needs settling'; }
printf 'Remv thermald [2.5.9-1]\n' > "$T/plan"
check "removing thermald removes it alone: it is settled (removed)" "$(step)" 1
printf 'Remv thermald [2.5.9-1]\nInst thermal-daemon-alt (1 Debian:testing [amd64])\n' > "$T/plan"
check "removing thermald would install another package in its place: nothing to do" "$(step)" 0
printf 'Remv thermald [2.5.9-1]\nRemv sensors-ui [1]\n' > "$T/plan"
check "removing thermald would take another package: nothing to do" "$(step)" 0
echo "== $( [ $fails = 0 ] && echo "ALL PASS" || echo "$fails FAILED")"
[ $fails = 0 ]
