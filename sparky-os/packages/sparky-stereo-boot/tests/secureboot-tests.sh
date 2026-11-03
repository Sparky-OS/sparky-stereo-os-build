#!/bin/sh
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/25
# Copyright 2026 under the GNU GPL3 License
# Tests of lib/secureboot.py on fake EFI system partitions: where the certificate goes, the GRUB entry it writes
# in each of the nine languages, and what it says and keeps when the certificate cannot be placed (0.1.5); this
# computer's DKMS certificate beside it, its GRUB entry and, under a fake Secure Boot, the enrolment check (0.1.8).
# Needs python3, openssl and sparky-stereo-problems; run as root in a container.
#   secureboot-tests.sh PATH/TO/sparky-stereo-boot
set -u
P=$(cd "${1:?package source}" && pwd)
CERT=$P/../../secureboot/sparky-stereo-secureboot-2026.der
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1: got [$2], want [$3]"; fails=$((fails + 1)); fi; }
# the problems are kept by the engine (sparky-stereo-problems, 0.1.6), its messages from catalogs of the package's lang/
sparky-stereo-problems catalog sparky-stereo-boot "$P/lang" "$T/cat" --subject LOCAL19 >/dev/null
run() { SPARKY_STEREO_ESP=$T/$1 SPARKY_STEREO_CERT=${CERT_USED:-$CERT} SPARKY_STEREO_LANG_DIR=$P/lang SPARKY_STEREO_OS_RELEASE=$T/os-release \
	SPARKY_STEREO_PROBLEMS_CATALOG=$T/cat:/usr/lib/systemd/catalog SPARKY_STEREO_DKMS_CERT=${DKMS_USED:-$T/none.der} \
	SPARKY_STEREO_DKMS_TREE=$T/dkms SPARKY_STEREO_EFI=$T/efi SPARKY_STEREO_KERNEL=${KERNEL_USED:-7.3.1-stereo3d15} PATH=$T/bin:$PATH \
	SPARKY_STEREO_ROOT=$T/root SPARKY_STEREO_FSTAB=$T/fstab LANG=$2 python3 -I "$P/lib/secureboot.py" "$3"; }
printf 'ID=sparky\n' > "$T/os-release"
: > "$T/fstab"
REC=$T/root/var/lib/sparky-stereo-problems/sparky-stereo-boot_esp-certificate.json
key() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["message"])' "$REC" 2>/dev/null || echo none; }

# an installed system as Calamares leaves it: shim in EFI/sparky and EFI/debian, and shim as EFI/BOOT/BOOTX64.EFI
mkdir -p "$T/a/EFI/sparky" "$T/a/EFI/debian" "$T/a/EFI/boot" "$T/a/EFI/Microsoft/Boot"
for d in sparky debian; do echo shim > "$T/a/EFI/$d/shimx64.efi"; echo mm > "$T/a/EFI/$d/mmx64.efi"; done
echo shim > "$T/a/EFI/boot/BOOTX64.EFI"; echo windows > "$T/a/EFI/Microsoft/Boot/bootmgfw.efi"
run a en_US.UTF-8 esp >/dev/null
check "certificate beside shim in EFI/sparky" "$(cmp -s "$CERT" "$T/a/EFI/sparky/sparky-stereo-secureboot-2026.der" && echo same)" same
check "certificate beside shim in EFI/debian" "$(cmp -s "$CERT" "$T/a/EFI/debian/sparky-stereo-secureboot-2026.der" && echo same)" same
check "certificate on the removable-media path (BOOTX64.EFI is shim)" "$(cmp -s "$CERT" "$T/a/EFI/boot/sparky-stereo-secureboot-2026.der" && echo same)" same
check "nothing in Windows' folder" "$(ls "$T/a/EFI/Microsoft/Boot")" bootmgfw.efi
check "a second run writes nothing" "$(run a en_US.UTF-8 esp)" ""

# BOOTX64.EFI that is not shim (another system's loader) gets no certificate
mkdir -p "$T/b/EFI/sparky" "$T/b/EFI/BOOT"; echo shim > "$T/b/EFI/sparky/shimx64.efi"; echo other > "$T/b/EFI/BOOT/BOOTX64.EFI"
run b en_US.UTF-8 esp >/dev/null
check "no certificate beside another loader's BOOTX64.EFI" "$(ls "$T/b/EFI/BOOT")" BOOTX64.EFI

# no shim at all (a BIOS boot, or another boot loader): no entry
mkdir -p "$T/c/EFI/other"; echo grub > "$T/c/EFI/other/grubx64.efi"
check "no shim: no GRUB entry" "$(run c en_US.UTF-8 grub)" ""

# the entry: title in the system's language, the steps in nine languages (the system's first), MokManager beside GRUB,
# and the fallback only under Secure Boot
for l in en_US pl_PL pt_BR fr_FR de_DE ja_JP ko_KR zh_CN zh_TW; do
	out=$(run a $l.UTF-8 grub)
	code=$l; case $l in pt_BR|zh_CN|zh_TW) ;; *) code=${l%_*} ;; esac
	title=$(sed -n 's/^LOCAL12="\(.*\)"$/\1/p' "$P/lang/$code")
	name=$(sed -n 's/^LOCAL14="\(.*\)"$/\1/p' "$P/lang/$code")
	check "$l: title" "$(echo "$out" | sed -n "s/^ *menuentry '\(.*\)' --id sparky-enroll {$/\1/p")" "$title"
	check "$l: its language first" "$(echo "$out" | grep -m1 'echo "' | sed 's/^ *echo "\([^:]*\):.*/\1/')" "$name"
	check "$l: nine languages" "$(echo "$out" | grep -c -E 'echo "(English|Polski|Português|Français|Deutsch|日本語|한국어|简体中文|繁體中文):')" 9
	check "$l: the system's folder named" "$(echo "$out" | grep -c 'sparky-stereo-secureboot-2026.der')" 9
done
out=$(run a de_DE.UTF-8 grub)
check "MokManager from the system's folder, the partition found by file" "$(echo "$out" | grep -c -E 'search --no-floppy --file --set=sparky_mm /EFI/sparky/mmx64.efi|chainloader \(\$sparky_mm\)/EFI/sparky/mmx64.efi')" 2
out2=$(SPARKY_STEREO_ESP_UUID=ABCD-1234 run a de_DE.UTF-8 grub)
check "the partition by its UUID first (each entry)" "$(echo "$out2" | grep -c 'search --no-floppy --fs-uuid --set=sparky_mm ABCD-1234')" 2
check "no kernel known: no Secure Boot test" "$(echo "$out" | grep -c shim_lock)" 0
out=$(SPARKY_STEREO_KERNEL_PATH=/boot/vmlinuz-7.3.0-rc6-stereo3d12 SPARKY_STEREO_KERNEL_ACCESS="$(printf 'insmod part_gpt\nsearch --no-floppy --fs-uuid --set=root 1234')" run a de_DE.UTF-8 grub)
check "under Secure Boot shim is asked about the kernel" "$(echo "$out" | grep -A4 'if \[ "$shim_lock" = y \]; then' | tail -1 | tr -d ' ')" "iflinux/boot/vmlinuz-7.3.0-rc6-stereo3d12;then"
check "a refused kernel makes the enrolment the default" "$(echo "$out" | grep -c 'set default=sparky-enroll')" 1
check "the menu's root comes back" "$(echo "$out" | grep -c 'set root="$sparky_root"')" 1
check "only on 64-bit UEFI" "$(echo "$out" | head -2 | tr -d ' ' | tr '\n' ' ')" 'if["$grub_platform"=efi];then if["$grub_cpu"=x86_64];then '
check "no character GRUB would expand in the texts" "$(echo "$out" | grep 'echo "' | grep -c -E '\$|\\')" 0
w=$(echo "$out" | grep 'echo "' | sed 's/^ *echo "//; s/"$//' | python3 -c 'import sys,unicodedata; print(max(sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in l.rstrip("\n")) for l in sys.stdin))')
check "lines fit 98 columns (800x600)" "$([ "$w" -le 98 ] && echo yes)" yes

# 0.1.5: what cannot be placed is said and kept (problems.py), and a success clears it
printf 'UUID=0B1C-2D3E %s vfat umask=0077 0 1\n' "$T/m" > "$T/fstab"; mkdir -p "$T/m"
out=$(run m en_US.UTF-8 esp 2>&1); rc=$?
check "ESP in /etc/fstab, not mounted: the step fails" "$rc" 1
check "ESP not mounted: said, with the mount to do" "$(echo "$out" | grep -c "The EFI system partition $T/m is not mounted.*sudo mount $T/m")" 1
check "ESP not mounted: kept for repair" "$(key)" LOCAL23
: > "$T/fstab"
out=$(run m en_US.UTF-8 esp 2>&1); rc=$?
check "no ESP for this system (a BIOS boot): nothing to do, nothing said" "$rc:$out" "0:"
check "a step that has nothing to do clears the kept problem" "$(key)" none
rm -f "$T/a/EFI/debian/sparky-stereo-secureboot-2026.der"; mkdir -p "$T/a/EFI/debian/sparky-stereo-secureboot-2026.der"   # a folder where the certificate goes: the copy fails
out=$(run a de_DE.UTF-8 esp 2>&1); rc=$?
check "copy fails: the step fails" "$rc" 1
check "copy fails: said in the system's language, naming the folder" "$(echo "$out" | grep -c "Das Secure-Boot-Zertifikat konnte nicht nach $T/a/EFI/debian/sparky-stereo-secureboot-2026.der geschrieben werden")" 1
check "copy fails: said in English too, for support" "$(echo "$out" | grep -c '(en) The Secure Boot certificate could not be written to')" 1
check "copy fails: kept, with the command that repairs it" "$(key):$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["repair"])' "$REC")" "LOCAL25:[['python3', '/usr/lib/sparky-stereo-boot/secureboot.py', 'esp']]"
check "copy fails: the other folders still get it" "$(cmp -s "$CERT" "$T/a/EFI/sparky/sparky-stereo-secureboot-2026.der" && echo same)" same
rmdir "$T/a/EFI/debian/sparky-stereo-secureboot-2026.der"
out=$(run a en_US.UTF-8 esp 2>&1); rc=$?
check "repaired: the step succeeds and clears the kept problem" "$rc:$(key)" "0:none"
out=$(CERT_USED=$T/missing.der run a en_US.UTF-8 esp 2>&1); rc=$?
check "certificate missing from the package: said and kept" "$rc:$(key):$(echo "$out" | grep -c 'is missing from this installation')" "1:LOCAL24:1"
out=$(run c en_US.UTF-8 esp 2>&1); rc=$?
check "an EFI system partition without shim: said, not failed" "$rc:$(echo "$out" | grep -c "No shim is on the EFI system partition $T/c")" "0:1"

# 0.1.8: this computer's DKMS certificate (ORDER 374), beside the edition's
mkdir -p "$T/bin" "$T/dkms" "$T/efi/efivars" "$T/efi/mok-variables"
openssl req -new -x509 -nodes -days 1 -subj "/CN=DKMS module signing key" -newkey rsa:2048 -keyout "$T/mok.key" \
	-addext "extendedKeyUsage=codeSigning" -outform DER -out "$T/mok.pub" >/dev/null 2>&1
openssl x509 -inform DER -in "$T/mok.pub" -out "$T/mok.pem"
DREC=$T/root/var/lib/sparky-stereo-problems/sparky-stereo-boot_esp-dkms-certificate.json
dkey() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["message"])' "$DREC" 2>/dev/null || echo none; }
rm -rf "$T/a"; mkdir -p "$T/a/EFI/sparky" "$T/a/EFI/debian" "$T/a/EFI/boot"
for d in sparky debian; do echo shim > "$T/a/EFI/$d/shimx64.efi"; echo mm > "$T/a/EFI/$d/mmx64.efi"; done
echo shim > "$T/a/EFI/boot/BOOTX64.EFI"
DKMS_USED=$T/mok.pub run a en_US.UTF-8 esp >/dev/null
for d in sparky debian boot; do
	check "DKMS certificate beside shim in EFI/$d" "$(cmp -s "$T/mok.pub" "$T/a/EFI/$d/dkms-this-computer.der" && echo same)" same
done
check "nothing beside another loader's BOOTX64.EFI" "$(DKMS_USED=$T/mok.pub run b en_US.UTF-8 esp >/dev/null; ls "$T/b/EFI/BOOT")" BOOTX64.EFI
check "a second run writes nothing" "$(DKMS_USED=$T/mok.pub run a en_US.UTF-8 esp)" ""
DKMS_USED=$T/mok.pem run a en_US.UTF-8 esp >/dev/null
check "a PEM certificate goes as DER, as MokManager wants" "$(cmp -s "$T/mok.pub" "$T/a/EFI/sparky/dkms-this-computer.der" && echo same)" same
DKMS_USED=$T/none.der run a en_US.UTF-8 esp >/dev/null
check "no DKMS key on the computer: no copy left beside shim" "$(ls "$T/a/EFI/sparky" "$T/a/EFI/debian" "$T/a/EFI/boot" | grep -c dkms-this-computer.der)" 0
check "the edition's certificate stays" "$(ls "$T/a/EFI/sparky" | grep -c sparky-stereo-secureboot-2026.der)" 1
echo 'not a certificate' > "$T/bad.der"
out=$(DKMS_USED=$T/bad.der run a de_DE.UTF-8 esp 2>&1); rc=$?
check "an unreadable DKMS certificate: said and kept, with its repair" "$rc:$(dkey):$(echo "$out" | grep -c "Das DKMS-Zertifikat dieses Computers, $T/bad.der, konnte nicht als Zertifikat gelesen werden")" "1:LOCAL65:1"
mkdir -p "$T/a/EFI/debian/dkms-this-computer.der"
out=$(DKMS_USED=$T/mok.pub run a en_US.UTF-8 esp 2>&1); rc=$?
check "the DKMS copy fails: said and kept, naming the folder" "$rc:$(dkey):$(echo "$out" | grep -c "This computer's DKMS certificate could not be written to $T/a/EFI/debian/dkms-this-computer.der")" "1:LOCAL64:1"
check "the DKMS copy fails: the edition's step is not kept" "$(key)" none
check "the DKMS copy fails: the other folders still get it" "$(cmp -s "$T/mok.pub" "$T/a/EFI/sparky/dkms-this-computer.der" && echo same)" same
rmdir "$T/a/EFI/debian/dkms-this-computer.der"
out=$(DKMS_USED=$T/mok.pub run a en_US.UTF-8 esp 2>&1); rc=$?
check "repaired: the DKMS step succeeds and clears its problem" "$rc:$(dkey)" "0:none"

# the second GRUB entry: with the partition's UUID GRUB looks for the certificate when it reads the menu, so it is
# written whether or not DKMS has made its key yet; without the UUID it follows what update-grub finds
for l in en_US pl_PL pt_BR fr_FR de_DE ja_JP ko_KR zh_CN zh_TW; do
	out=$(SPARKY_STEREO_ESP_UUID=ABCD-1234 run a $l.UTF-8 grub)
	code=$l; case $l in pt_BR|zh_CN|zh_TW) ;; *) code=${l%_*} ;; esac
	title=$(sed -n 's/^LOCAL62="\(.*\)"$/\1/p' "$P/lang/$code")
	check "$l: DKMS title" "$(echo "$out" | sed -n "s/^ *menuentry [\"']\(.*\)[\"'] --id sparky-enroll-dkms {$/\1/p")" "$title"
	check "$l: DKMS steps in nine languages" "$(echo "$out" | sed -n '/sparky-enroll-dkms/,/^ *}/p' | grep -c -E 'echo "(English|Polski|Português|Français|Deutsch|日本語|한국어|简体中文|繁體中文):')" 9
	check "$l: the certificate named in each" "$(echo "$out" | grep -c 'dkms-this-computer.der')" 10
done
out=$(SPARKY_STEREO_ESP_UUID=ABCD-1234 run a en_US.UTF-8 grub)
check "English title in double quotes, its apostrophe kept" "$(echo "$out" | grep -c "menuentry \"Secure Boot: enroll this computer's DKMS key\" --id sparky-enroll-dkms {")" 1
check "shown when the certificate is on the partition found by its UUID" "$(echo "$out" | sed -n '/set sparky_dkms=/,/sparky-enroll-dkms/p' | tr -s ' ' | tr '\n' ';')" \
	' set sparky_dkms=; search --no-floppy --fs-uuid --set=sparky_dkms ABCD-1234; if [ -n "$sparky_dkms" ]; then; if [ -f "($sparky_dkms)/EFI/sparky/dkms-this-computer.der" ]; then; menuentry "Secure Boot: enroll this computer'"'"'s DKMS key" --id sparky-enroll-dkms {;'
check "MokManager from the system's folder" "$(echo "$out" | sed -n '/sparky-enroll-dkms/,/^ *}/p' | grep -c 'chainloader ($sparky_mm)/EFI/sparky/mmx64.efi')" 1
check "the edition's entry comes first" "$(echo "$out" | grep -o -E -- '--id sparky-enroll(-dkms)?' | tr '\n' ' ')" "--id sparky-enroll --id sparky-enroll-dkms "
check "no character GRUB would expand in the DKMS texts" "$(echo "$out" | grep 'echo "' | grep -c -E '\$|\\')" 0
w=$(echo "$out" | grep 'echo "' | sed 's/^ *echo "//; s/"$//' | python3 -c 'import sys,unicodedata; print(max(sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in l.rstrip("\n")) for l in sys.stdin))')
check "DKMS lines fit 98 columns (800x600)" "$([ "$w" -le 98 ] && echo yes)" yes
check "no UUID, no certificate yet: no DKMS entry" "$(DKMS_USED=$T/none.der run a en_US.UTF-8 grub | grep -c sparky-enroll-dkms)" 0
out=$(DKMS_USED=$T/mok.pub run a en_US.UTF-8 grub)
check "no UUID, the certificate there: the entry, MokManager by file" "$(echo "$out" | grep -c -E 'sparky-enroll-dkms|search --no-floppy --file --set=sparky_mm /EFI/sparky/mmx64.efi')" 3
out=$(SPARKY_STEREO_KERNEL_PATH=/boot/vmlinuz-7.3.1-stereo3d15 SPARKY_STEREO_ESP_UUID=ABCD-1234 run a en_US.UTF-8 grub)
check "a refused kernel still makes the edition's enrolment the default" "$(echo "$out" | grep -c 'set default=sparky-enroll$')" 1
check "GRUB's syntax: if and fi pair up" "$(echo "$out" | grep -c -E '^ *if ')" "$(echo "$out" | grep -c -E '^ *fi$')"

# the enrolment under a fake Secure Boot: shim's MokListRT (EFI_SIGNATURE_LIST of X.509 entries), modinfo faked
# for the module's signer
EREC=$T/root/var/lib/sparky-stereo-problems/sparky-stereo-boot_dkms-key-enrolment.json
ekey() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["message"], d["args"])' "$EREC" 2>/dev/null || echo none; }
sb() { { printf '\007\000\000\000'; printf "\\$(printf %03o "$1")"; } > "$T/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"; }
moklist() { python3 - "$T/efi/mok-variables/MokListRT" "$@" <<'EOF'
import struct, sys, uuid
out = b''
for path in sys.argv[2:]:
    der = open(path, 'rb').read()
    entry = uuid.UUID('605dab50-e046-4300-abb6-3dd810dd8b23').bytes_le + der
    out += uuid.UUID('a5c059a1-94e4-4aa7-87b5-ab155c2bf072').bytes_le + struct.pack('<III', 28 + len(entry), 0, len(entry)) + entry
open(sys.argv[1], 'wb').write(out)
EOF
}
serial=$(openssl x509 -inform DER -in "$T/mok.pub" -noout -serial | sed 's/^serial=//; s/\(..\)/\1:/g; s/:$//')
eserial=$(openssl x509 -inform DER -in "$CERT" -noout -serial | sed 's/^serial=//; s/\(..\)/\1:/g; s/:$//')
mkdir -p "$T/dkms/hid-tmff2/0.83/7.3.1-stereo3d15/x86_64/module"
ln -sfn 0.83/7.3.1-stereo3d15/x86_64 "$T/dkms/hid-tmff2/kernel-7.3.1-stereo3d15-x86_64"
: > "$T/dkms/hid-tmff2/0.83/7.3.1-stereo3d15/x86_64/module/hid-tmff-new.ko.xz"
printf '%s\n' "$serial" > "$T/sig_key"
cat > "$T/bin/modinfo" <<EOF
#!/bin/sh
[ "\$1" = -k ] && exit 1
cat "$T/sig_key"
EOF
chmod 755 "$T/bin/modinfo"
sb 0; moklist "$CERT"
DKMS_USED=$T/mok.pub run a pt_BR.UTF-8 dkms-key >/dev/null 2>&1
check "Secure Boot off: nothing kept" "$(ekey)" none
sb 1
out=$(DKMS_USED=$T/mok.pub run a pt_BR.UTF-8 dkms-key 2>&1); rc=$?
check "Secure Boot on, the DKMS key not enrolled: kept, naming the module and the entry" "$(ekey)" "LOCAL66 ['hid-tmff2/0.83', ['LOCAL62']]"
check "said in the system's language, the entry by its title" "$(echo "$out" | grep -c 'recusa os módulos DKMS assinados com ela (hid-tmff2/0.83). Reinicie, abra o menu do GRUB (segure Shift ou aperte Esc), escolha “Secure Boot: registrar a chave DKMS deste computador”')" 1
check "the step itself succeeded (the unit does not fail too)" "$rc" 0
moklist "$CERT" "$T/mok.pub"
DKMS_USED=$T/mok.pub run a pt_BR.UTF-8 dkms-key >/dev/null 2>&1
check "enrolled: cleared" "$(ekey)" none
moklist "$CERT"; printf '%s\n' "$eserial" > "$T/sig_key"
DKMS_USED=$T/mok.pub run a pt_BR.UTF-8 dkms-key >/dev/null 2>&1
check "modules signed with another enrolled key (the edition's): nothing kept" "$(ekey)" none
printf '%s\n' "$serial" > "$T/sig_key"
DKMS_USED=$T/none.der run a pt_BR.UTF-8 dkms-key >/dev/null 2>&1
check "no DKMS key on the computer: nothing kept" "$(ekey)" none
DKMS_USED=$T/mok.pub KERNEL_USED=7.3.1-stereo3d14 run a pt_BR.UTF-8 dkms-key >/dev/null 2>&1
check "no DKMS module for the running kernel: nothing kept" "$(ekey)" none
echo "== $( [ $fails = 0 ] && echo "ALL PASS" || echo "$fails FAILED")"
[ $fails = 0 ]
