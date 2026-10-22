# SPDX-License-Identifier: GPL-2.0-or-later
# Boot 1 of a hibernation scenario: prepare swap, plant a canary and a witness process, hibernate. If the kernel
# resumes the image, this script continues after the write to /sys/power/state and proves continuity.
HMODE=$(cmdline_opt bench.hmode); [ -z "$HMODE" ] && HMODE=shutdown
bench_info kernel "$(uname -r) | $(uname -v)"
bench_info cmdline "$(cat /proc/cmdline)"
bench_info lockdown "$(cat /sys/kernel/security/lockdown 2>/dev/null)"
bench_info sys_power_disk "$(cat /sys/power/disk 2>/dev/null)"
bench_info sys_power_state "$(cat /sys/power/state 2>/dev/null)"
SWAPDISK=$(disk_by_serial benchswap)
mkswap "/dev/$SWAPDISK" >/dev/null 2>&1 && swapon "/dev/$SWAPDISK" && bench_check swap_ready PASS "/dev/$SWAPDISK is swap" || bench_check swap_ready FAIL "cannot set up swap on /dev/$SWAPDISK"
# canary: random bytes and a text marker in tmpfs (RAM), so they are part of the image if one is written
head -c 4096 /dev/urandom > /run/canary.bin
CAN_HEAD=$(head -c 32 /run/canary.bin | hexdump -v -e '/1 "%02x"')
CAN_TAIL=$(tail -c 32 /run/canary.bin | hexdump -v -e '/1 "%02x"')
CAN_TXT="HBENCH-CANARY-$(head -c 8 /dev/urandom | hexdump -v -e '/1 "%02x"')"
i=0; while [ $i -lt 64 ]; do echo "$CAN_TXT"; i=$((i+1)); done > /run/canary.txt
bench_info canary_head "$CAN_HEAD"
bench_info canary_tail "$CAN_TAIL"
bench_info canary_text "$CAN_TXT"
# witness: a background loop whose counter keeps running after a successful resume
( n=0; while :; do n=$((n+1)); echo $n > /run/witness; sleep 1; done ) &
sleep 3
W1=$(cat /run/witness)
MARK=$(head -c 8 /dev/urandom | hexdump -v -e '/1 "%02x"')
echo "$MARK" > /run/mark
bench_info hibernating "mode=$HMODE mark=$MARK witness=$W1"
echo "$HMODE" > /sys/power/disk 2>/dev/null
sync
dmesg -c > /tmp/dmesg-before.txt
echo disk > /sys/power/state
RC=$?
# Here: the write failed (hibernation refused) or the image was resumed.
sleep 3
W2=$(cat /run/witness 2>/dev/null)
MARK2=$(cat /run/mark 2>/dev/null)
bench_info hibernate_write_rc "$RC"
if [ "$RC" -ne 0 ]; then
    bench_check hibernate_entered FAIL "write to /sys/power/state failed (rc=$RC): hibernation was refused or impossible"
    bench_dmesg refusal 'PM:|ockdown|hibernat|snapenc|swsusp'
elif [ "$MARK2" = "$MARK" ] && [ "${W2:-0}" -gt "${W1:-0}" ]; then
    bench_check hibernate_resumed PASS "resumed: mark intact, witness $W1 -> $W2"
    bench_dmesg resume 'PM:|ockdown|hibernat|snapenc|swsusp'
else
    bench_check hibernate_resumed FAIL "write returned 0 but state is not continuous (mark '$MARK2' vs '$MARK', witness '$W2' vs '$W1')"
    bench_dmesg resume 'PM:|ockdown|hibernat|snapenc|swsusp'
fi
