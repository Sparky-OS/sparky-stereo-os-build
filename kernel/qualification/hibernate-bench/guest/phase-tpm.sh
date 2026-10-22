# SPDX-License-Identifier: GPL-2.0-or-later
# One boot: is there a TPM 2.0 and can the resettable debug/application PCRs (16 and 23) be extended and reset from user space?
bench_info kernel "$(uname -r) | $(uname -v)"
if [ -e /dev/tpmrm0 ] || [ -e /dev/tpm0 ]; then bench_check tpm_device PASS "$(ls /dev/tpm0 /dev/tpmrm0 2>/dev/null | tr '\n' ' ')"; else bench_check tpm_device FAIL "no /dev/tpm0 or /dev/tpmrm0"; fi
bench_dmesg tpm 'tpm|TPM'
ZERO=0000000000000000000000000000000000000000000000000000000000000000
for p in 16 23; do
    b=$(tpm pcrread $p 2>&1)
    tpm pcrextend $p 0000000000000000000000000000000000000000000000000000000000000007 2>&1
    m=$(tpm pcrread $p 2>&1)
    tpm pcrreset $p 2>&1
    a=$(tpm pcrread $p 2>&1)
    if [ "$b" = "$ZERO" ] && [ "$m" != "$ZERO" ] && [ "$a" = "$ZERO" ]; then bench_check "pcr${p}_extend_reset" PASS "before zero, extended $m, reset to zero"; else bench_check "pcr${p}_extend_reset" FAIL "before=$b extended=$m after=$a"; fi
done
bench_dmesg tpmerr 'TPM error|tpm tpm'
