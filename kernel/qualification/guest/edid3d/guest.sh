# SPDX-License-Identifier: GPL-2.0-or-later
# Guest script of the edid3d test (hibernate-bench --guest-script): needs drm.ko loaded (--load-modules "... drm") and /guest/edid3d.ko (--guest-dir).
# The module reports through the kernel log and returns an error on purpose (it never stays loaded); this script copies its lines to the console as BENCH|log|edid3d|...
bench_info kernel "$(uname -r) | $(uname -v)"
dmesg -c >/dev/null 2>&1
insmod /guest/edid3d.ko 2>/run/edid3d.err
bench_info edid3d_insmod "$(cat /run/edid3d.err) (an error is expected: the module never stays loaded)"
dmesg | grep 'EDID3D|' | sed 's/^\[[^]]*\] //' | while IFS= read -r l; do echo "BENCH|log|edid3d|$l"; done
grep -q 'EDID3D|done|' /dev/kmsg 2>/dev/null
dmesg | grep -q 'EDID3D|done|' && bench_check edid3d_ran PASS "the module ran to the end" || bench_check edid3d_ran FAIL "no EDID3D|done line: $(dmesg | tail -n 5 | tr '\n' ';')"
