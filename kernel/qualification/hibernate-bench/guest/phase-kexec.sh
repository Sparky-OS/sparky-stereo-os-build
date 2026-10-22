# SPDX-License-Identifier: GPL-2.0-or-later
# One boot: what the kernel answers to kexec_load(2) and kexec_file_load(2), first with kernel.kexec_load_disabled as the kernel booted with it
# (normally 0), then after the toggle is set to 1 (by applying the distribution's sysctl file when --guest-sysctl was given, else directly).
#
#   kexec_load       with no segments, so it changes nothing when permitted; the answer is what counts
#   kexec_file_load  of the signed kernel image (the one that booted) and, when there is one, of the unsigned image; an accepted image is unloaded at once
#
# The questions behind it: under Secure Boot, can root stage a kernel that nobody signed (kexec_load has no file to check; kexec_file_load can verify a
# signature), and what does kernel.kexec_load_disabled=1 take away besides that. Nothing is executed.
KT=/bench/kexectest
SIGNED=/bench/kernel.signed
UNSIGNED=/bench/kernel.unsigned
EXPECT_FILE=$(cmdline_opt bench.expect_kexec_file); [ -z "$EXPECT_FILE" ] && EXPECT_FILE=refuse   # what a signed kexec_file_load should do after the toggle: refuse (documented) | allow

bench_info kernel "$(uname -r) | $(uname -v)"
sb=$(efivar_byte /sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c)
bench_info secure_boot "firmware SecureBoot=${sb:-unreadable}"
[ -x "$KT" ] && [ -f "$SIGNED" ] || { bench_check kexec_inputs FAIL "kexectest or the signed image is missing in the initramfs"; return 0 2>/dev/null || exit 0; }

field() { echo "$1" | sed -n "s/.* $2=\([^ ]*\).*/\1/p" | head -n 1; }
probe() {   # probe load0 | fload IMAGE [crash] [keep] : sets R (the answer), RC (0 accepted, -1 refused), NAME (errno name)
    if [ "$1" = load0 ]; then R=$($KT load0 2>&1); else R=$($KT "$@" 2>&1); fi
    RC=$(field "$R" rc); NAME=$(field "$R" name)
}
ima_line() { dmesg | grep -i 'impossible to appraise\|kexec' | tail -n 2 | tr '\n' ';' | cut -c1-220; }

# ---- 1. the toggle as the kernel booted with it
bench_info kexec_load_disabled_before "$(cat /proc/sys/kernel/kexec_load_disabled 2>/dev/null)"
dmesg -c >/dev/null 2>&1
probe load0
if [ "$RC" = -1 ] && { [ "$NAME" = EPERM ] || [ "$NAME" = EACCES ]; }; then
    bench_check kexec_load_refused_before PASS "kexec_load answered $NAME. $(ima_line)"
elif [ "$RC" = 0 ]; then
    bench_check kexec_load_refused_before FAIL "kexec_load was ACCEPTED: root can stage a kernel without any signature check"
else
    bench_check kexec_load_refused_before FAIL "kexec_load answered $RC $NAME ($R)"
fi
if [ -f "$UNSIGNED" ]; then
    probe fload "$UNSIGNED"
    if [ "$RC" = -1 ]; then bench_check kexec_file_unsigned_refused_before PASS "the unsigned image was refused with $NAME. $(ima_line)"
    else bench_check kexec_file_unsigned_refused_before FAIL "the UNSIGNED image was accepted by kexec_file_load"; fi
else
    bench_check kexec_file_unsigned_refused_before INFO "no unsigned image given (--kernel-signed)"
fi
probe fload "$SIGNED"
if [ "$RC" = 0 ]; then bench_check kexec_file_signed_loads_before PASS "the signed image was accepted (and unloaded again)"
else bench_check kexec_file_signed_loads_before FAIL "the signed image was refused with $NAME ($R). $(ima_line)"; fi

probe fload "$SIGNED" crash
bench_info kexec_file_crash_before "$R (a refusal for another reason than the toggle is expected here: this guest reserves no crashkernel= memory)"
CRASH_BEFORE=$NAME
# stage the signed image and keep it staged across the toggle (the documentation says an image loaded before the toggle stays usable)
probe fload "$SIGNED" keep
staged_before=$(cat /sys/kernel/kexec_loaded 2>/dev/null)
bench_info kexec_loaded_before "/sys/kernel/kexec_loaded=${staged_before:-absent}"

# ---- 2. set kernel.kexec_load_disabled=1
if [ -f /bench/sysctl.conf ]; then
    apply_sysctl_file /bench/sysctl.conf
    bench_info sysctl_file "applied $SYSCTL_N lines, $SYSCTL_BAD not accepted by the kernel"
    if [ "$SYSCTL_BAD" = 0 ]; then bench_check sysctl_file_accepted PASS "all $SYSCTL_N keys of the file exist in this kernel and took their value"
    else bench_check sysctl_file_accepted FAIL "$SYSCTL_BAD of $SYSCTL_N keys missing or rejected (see the sysctl_missing / sysctl_rejected lines)"; fi
else
    echo 1 > /proc/sys/kernel/kexec_load_disabled
    bench_info sysctl_file "no --guest-sysctl given: kernel.kexec_load_disabled set to 1 directly"
fi
v=$(cat /proc/sys/kernel/kexec_load_disabled 2>/dev/null)
bench_info kexec_load_disabled_after "$v"
[ "$v" = 1 ] && bench_check kexec_load_disabled_set PASS "kernel.kexec_load_disabled=1" || bench_check kexec_load_disabled_set FAIL "kernel.kexec_load_disabled is '$v' after the sysctl file was applied"

# ---- 3. the same questions with the toggle set
dmesg -c >/dev/null 2>&1
probe load0
if [ "$RC" = -1 ] && [ "$NAME" = EPERM ]; then bench_check kexec_load_refused_after PASS "kexec_load answered EPERM"
else bench_check kexec_load_refused_after FAIL "kexec_load answered rc=$RC $NAME (EPERM was expected)"; fi
if [ -f "$UNSIGNED" ]; then
    probe fload "$UNSIGNED"
    if [ "$RC" = -1 ]; then bench_check kexec_file_unsigned_refused_after PASS "the unsigned image was refused with $NAME"
    else bench_check kexec_file_unsigned_refused_after FAIL "the UNSIGNED image was accepted by kexec_file_load"; fi
fi
probe fload "$SIGNED"
if [ "$EXPECT_FILE" = allow ]; then
    if [ "$RC" = 0 ]; then bench_check kexec_file_signed_loads_after PASS "the signed image was accepted with the toggle set"
    else bench_check kexec_file_signed_loads_after FAIL "expected: a signed kexec_file_load still loads. Answer: $NAME. kernel.kexec_load_disabled refuses kexec_file_load too (kernel/kexec_core.c kexec_load_permitted(), Documentation/admin-guide/sysctl/kernel.rst)"; fi
else
    if [ "$RC" = -1 ] && [ "$NAME" = EPERM ]; then bench_check kexec_file_signed_refused_after PASS "the signed image was refused with EPERM: the toggle closes kexec_file_load as well (as documented)"
    elif [ "$RC" = 0 ]; then bench_check kexec_file_signed_refused_after FAIL "the signed image was accepted with the toggle set (the documentation says both syscalls are disabled)"
    else bench_check kexec_file_signed_refused_after FAIL "answer: rc=$RC $NAME ($R)"; fi
fi
probe fload "$SIGNED" crash
if [ "$NAME" = EPERM ]; then bench_check kexec_file_crash_after PASS "a panic (kdump) kernel cannot be loaded after the toggle: EPERM (before the toggle the answer was ${CRASH_BEFORE:-?})"
else bench_check kexec_file_crash_after INFO "answer $NAME (before the toggle: ${CRASH_BEFORE:-?})"; fi
staged_after=$(cat /sys/kernel/kexec_loaded 2>/dev/null)
if [ "$staged_before" = 1 ] && [ "$staged_after" = 1 ]; then bench_check kexec_staged_survives_toggle PASS "an image staged before the toggle is still staged after it (/sys/kernel/kexec_loaded=1)"
else bench_check kexec_staged_survives_toggle INFO "kexec_loaded before=${staged_before:-absent} after=${staged_after:-absent}"; fi
