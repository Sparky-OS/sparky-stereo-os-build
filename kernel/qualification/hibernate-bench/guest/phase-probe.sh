# SPDX-License-Identifier: GPL-2.0-or-later
# One boot: what the firmware and the kernel say about Secure Boot, lockdown, keyrings, modules, hibernation.
bench_info kernel "$(uname -r) | $(uname -v)"
bench_info cmdline "$(cat /proc/cmdline)"
SBVAR=/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c
SMVAR=/sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c
efivar_byte() { dd if="$1" bs=1 skip=4 count=1 2>/dev/null | hexdump -v -e '1/1 "%u"'; }   # first payload byte, after the 4 attribute bytes
sb=$(efivar_byte "$SBVAR")
sm=$(efivar_byte "$SMVAR")
want_sb=$(cmdline_opt bench.expect_sb); [ -z "$want_sb" ] && want_sb=1
if [ "${sb:-0}" = "$want_sb" ]; then bench_check firmware_secure_boot PASS "SecureBoot=${sb:-0} SetupMode=${sm:-?} (expected $want_sb)"; else bench_check firmware_secure_boot FAIL "SecureBoot=${sb:-unreadable} SetupMode=${sm:-?} (expected $want_sb)"; fi
bench_dmesg secureboot 'ecure boot|integrity: secureboot|ima: |Lockdown|lockdown'
LD=$(cat /sys/kernel/security/lockdown 2>/dev/null)
bench_info lockdown "${LD:-unavailable}"
case "$LD" in *"[none]"*) bench_check lockdown_state INFO "none (kernel is not locked down)";; *"[integrity]"*) bench_check lockdown_state INFO "integrity";; *"[confidentiality]"*) bench_check lockdown_state INFO "confidentiality";; *) bench_check lockdown_state FAIL "unreadable: $LD";; esac
# keyrings (what /proc/keys lists)
cut -c1-120 /proc/keys 2>/dev/null | grep -E 'keyring' | while IFS= read -r l; do echo "BENCH|log|keyring|$l"; done
grep -E '\.platform|\.machine|\.builtin_trusted_keys|\.secondary_trusted_keys' /proc/keys 2>/dev/null | cut -c1-110 | while IFS= read -r l; do echo "BENCH|log|keys|$l"; done
# modules
want_unsigned=$(cmdline_opt bench.expect_unsigned)   # refuse (default) | load
[ -z "$want_unsigned" ] && want_unsigned=refuse
dmesg -c >/dev/null 2>&1
if insmod /bench/benchmod-unsigned.ko 2>/tmp/e1; then r1=loaded; rmmod benchmod 2>/dev/null; else r1="refused: $(cat /tmp/e1)"; fi
bench_info module_unsigned "$r1"
case "$r1" in refused*) [ "$want_unsigned" = refuse ] && bench_check module_unsigned_refused PASS "$r1" || bench_check module_unsigned_refused FAIL "$r1";; *) [ "$want_unsigned" = load ] && bench_check module_unsigned_refused PASS "loaded (expected)" || bench_check module_unsigned_refused FAIL "an unsigned module was loaded";; esac
bench_dmesg unsigned_load 'module|sig|key|Key'
dmesg -c >/dev/null 2>&1
if insmod /bench/benchmod-signed-trusted.ko 2>/tmp/e2; then r2=loaded; rmmod benchmod 2>/dev/null; else r2="refused: $(cat /tmp/e2)"; fi
want_trusted=$(cmdline_opt bench.expect_trusted); [ -z "$want_trusted" ] && want_trusted=load
case "$r2" in loaded) [ "$want_trusted" = load ] && bench_check module_signed_trusted_loads PASS "$r2" || bench_check module_signed_trusted_loads FAIL "$r2";; *) [ "$want_trusted" = refuse ] && bench_check module_signed_trusted_loads PASS "$r2 (expected)" || bench_check module_signed_trusted_loads FAIL "$r2";; esac
bench_dmesg trusted_load 'module|sig|key|Key|benchmod'
dmesg -c >/dev/null 2>&1
if insmod /bench/benchmod-signed-rogue.ko 2>/tmp/e3; then r3=loaded; rmmod benchmod 2>/dev/null; else r3="refused: $(cat /tmp/e3)"; fi
case "$r3" in
    refused*) [ "$want_unsigned" = refuse ] && bench_check module_signed_rogue_refused PASS "$r3" || bench_check module_signed_rogue_refused FAIL "$r3";;
    *) [ "$want_unsigned" = load ] && bench_check module_signed_rogue_refused PASS "loaded (expected: signatures are not enforced)" || bench_check module_signed_rogue_refused FAIL "a module signed by an unknown key was loaded";;
esac
# power
bench_info sys_power_disk "$(cat /sys/power/disk 2>/dev/null)"
bench_info sys_power_state "$(cat /sys/power/state 2>/dev/null)"
case "$(cat /sys/power/state 2>/dev/null)" in *disk*) bench_check hibernation_offered INFO "disk is in /sys/power/state";; *) bench_check hibernation_offered INFO "disk is NOT in /sys/power/state";; esac
case "$(cat /sys/power/disk 2>/dev/null)" in *shutdown*) bench_check sys_power_disk_modes INFO "modes listed";; *) bench_check sys_power_disk_modes INFO "no modes listed";; esac
ls /dev/tpm0 /dev/tpmrm0 2>/dev/null | tr '\n' ' ' | while IFS= read -r l; do bench_info tpm_devices "$l"; done
