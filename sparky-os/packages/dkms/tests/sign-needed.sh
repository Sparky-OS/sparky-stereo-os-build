#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/25
# Copyright 2026 under the GNU GPL2 License
# dkms-sign-unsigned builds only where a module without a signature can be refused (ORDER 666). Fake firmware trees
# (SPARKY_DKMS_EFI), a fake sig_enforce, one installed DKMS module without a signature, a dkms and a modinfo that only
# record and mark; the edition's real engine keeps and clears. Run as root in a throwaway container, never on a host.
#   sign-needed.sh PATH/TO/dkms-recipe [PATH/TO/dkms-sign-unsigned]
set -u
[ -e /.dockerenv ] || { echo "run in a container" >&2; exit 2; }
R=$(cd "${1:?the dkms recipe folder}" && pwd)
SCRIPT=${2:-$R/debian/scripts/dkms-sign-unsigned}
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1: got [$2], want [$3]"; fails=$((fails + 1)); fi; }
install -D -m 755 "$SCRIPT" /usr/lib/dkms/dkms-sign-unsigned
sparky-stereo-problems catalog dkms "$R/debian/problems-lang" /usr/lib/systemd/catalog --subject LOCAL1 >/dev/null
K=7.3.4-stereo3d18
D=/var/lib/dkms/acpi-call/1.2.2/$K/x86_64
VAR=SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c
# dkms: records each call; "build" marks the built copy as signed unless told to fail
cat > /usr/local/sbin/dkms <<FAKE
#!/bin/sh
echo "\$*" >> $T/dkms.calls
[ -e $T/dkms.fail ] && exit 1
case \$1 in build) mkdir -p $D/module; printf 'elf~Module signature appended~\n' > $D/module/acpi_call.ko ;; esac
exit 0
FAKE
# modinfo: no modules.dep here (-k fails, so the built copy is what is checked); sig_id only for a marked file
cat > /usr/local/sbin/modinfo <<'FAKE'
#!/bin/sh
[ "$1" = -k ] && exit 1
[ "$1" = -F ] && [ "$2" = sig_id ] && grep -q '~Module signature appended~' "$3" 2>/dev/null && echo PKCS#7
exit 0
FAKE
chmod 755 /usr/local/sbin/dkms /usr/local/sbin/modinfo
fresh() {
	rm -rf /var/lib/dkms "$T/dkms.calls" "$T/dkms.fail"
	mkdir -p "$D/module"; printf 'elf\n' > "$D/module/acpi_call.ko"
	ln -sfn "1.2.2/$K/x86_64" "/var/lib/dkms/acpi-call/kernel-$K-x86_64"
	: > "$T/dkms.calls"
}
firmware() { # bios | unsupported | off | on | unreadable | odd
	rm -rf "$T/efi"
	case $1 in
	bios) ;;
	unreadable) mkdir -p "$T/efi/efivars" ;;
	unsupported) mkdir -p "$T/efi/efivars"; printf '\007\000\000\000\001\000' > "$T/efi/efivars/Boot0000-8be4df61-93ca-11d2-aa0d-00e098032b8c" ;;
	off) mkdir -p "$T/efi/efivars"; printf '\007\000\000\000\000' > "$T/efi/efivars/$VAR" ;;
	on) mkdir -p "$T/efi/efivars"; printf '\007\000\000\000\001' > "$T/efi/efivars/$VAR" ;;
	odd) mkdir -p "$T/efi/efivars"; printf '\007\000\000\000\002' > "$T/efi/efivars/$VAR" ;;
	esac
}
run() { SPARKY_DKMS_EFI=$T/efi SPARKY_DKMS_SIG_ENFORCE=$T/sig_enforce LC_ALL=C.UTF-8 /usr/lib/dkms/dkms-sign-unsigned "$@"; }
kept() { find /var/lib/sparky-stereo-problems -name 'dkms_*' 2>/dev/null | wc -l; }
builds() { grep -c '^build ' "$T/dkms.calls"; }
STAMP=/var/lib/dkms/dkms-sign-unsigned.first-boot
echo N > "$T/sig_enforce"

for row in "bios:bios not-needed" "unsupported:unsupported not-needed" "off:off not-needed" "on:on needed" "unreadable:unknown needed" "odd:unknown needed"; do
	firmware "${row%%:*}"
	check "state, firmware ${row%%:*}" "$(run state 2>&1)" "${row#*:}"
done
firmware off; echo Y > "$T/sig_enforce"
check "state, Secure Boot off and the kernel enforcing signatures by itself" "$(run state 2>&1)" "enforced needed"
echo N > "$T/sig_enforce"

for row in "off:Secure Boot is turned off in this computer's firmware" "unsupported:This computer's firmware has no Secure Boot" "bios:This computer started without EFI"; do
	fresh; firmware "${row%%:*}"
	out=$(run first-boot 2>&1); rc=$?
	check "first start, ${row%%:*}: exit status" "$rc" 0
	check "first start, ${row%%:*}: no dkms build" "$(builds)" 0
	check "first start, ${row%%:*}: says why" "$(echo "$out" | grep -c "${row#*:}")" 1
	check "first start, ${row%%:*}: no mark, so a later Secure Boot is met" "$([ -e $STAMP ] && echo mark || echo none)" none
	check "first start, ${row%%:*}: the module is left as it was" "$(cat "$D/module/acpi_call.ko")" elf
done
fresh; firmware off
run >/dev/null 2>&1
check "the package's configure step, Secure Boot off: no dkms build" "$(builds)" 0

# with Secure Boot on: as before
fresh; firmware on; touch "$T/dkms.fail"
run first-boot >/dev/null 2>&1
check "Secure Boot on, the build fails: kept by the engine" "$(kept)" 1
check "Secure Boot on, the build fails: the first start is still marked done" "$([ -e $STAMP ] && echo mark || echo none)" mark
firmware off
run >/dev/null 2>&1
check "Secure Boot then switched off: what was kept for the module is cleared" "$(kept)" 0
fresh; firmware on
run first-boot >/dev/null 2>&1; rc=$?
check "Secure Boot on: the module is built again and installed" "$(cut -d' ' -f1 "$T/dkms.calls" | tr '\n' ' ')" "build install "
check "Secure Boot on: it has its signature" "$(modinfo -F sig_id "$D/module/acpi_call.ko")" "PKCS#7"
check "Secure Boot on: marked done, nothing kept, exit status" "$([ -e $STAMP ] && echo mark):$(kept):$rc" "mark:0:0"
fresh; firmware unreadable
run first-boot >/dev/null 2>&1
check "a state that cannot be read: signed as before" "$(builds)" 1
fresh; firmware off; echo Y > "$T/sig_enforce"
run first-boot >/dev/null 2>&1
check "Secure Boot off, the kernel enforcing signatures: signed" "$(builds)" 1
echo "== $( [ $fails = 0 ] && echo "ALL PASS" || echo "$fails FAILED")"
[ $fails = 0 ]
