# SPDX-License-Identifier: GPL-2.0-or-later
# Boot 2 of a hibernation scenario: optional tamper step, then ask the kernel to resume from the swap disk.
# If the image is restored this script never gets past the last write: the boot-1 userland continues instead.
bench_info kernel "$(uname -r) | $(uname -v)"
bench_info cmdline "$(cat /proc/cmdline)"
bench_info lockdown "$(cat /sys/kernel/security/lockdown 2>/dev/null)"
TP=$(cmdline_opt bench.tamper_pcr)
if [ -n "$TP" ]; then
    bench_info pcr_before "pcr$TP=$(tpm pcrread $TP 2>&1)"
    DG=$(cmdline_opt bench.tamper_digest); [ -z "$DG" ] && DG=0000000000000000000000000000000000000000000000000000000000000001
    tpm pcrextend "$TP" "$DG" >/dev/null 2>&1 && bench_info tamper "extended PCR$TP with $DG" || bench_check tamper_applied FAIL "could not extend PCR$TP"
    bench_info pcr_after "pcr$TP=$(tpm pcrread $TP 2>&1)"
fi
for p in 16 23; do bench_info pcr_state "pcr$p=$(tpm pcrread $p 2>&1)"; done
SWAPDISK=$(disk_by_serial benchswap)
DEVNO=$(cat "/sys/block/$SWAPDISK/dev")
bench_info resume_device "/dev/$SWAPDISK $DEVNO"
dmesg -c > /dev/null
echo "$DEVNO" > /sys/power/resume
bench_check resume_returned INFO "the kernel returned from /sys/power/resume without restoring an image"
bench_dmesg resume 'PM:|ockdown|hibernat|snapenc|swsusp|image|tpm|TPM'
