#!/bin/bash
# Tests of the menu shown after a start that did not finish (0.1.11, ORDER 572b): the rule of 30-sparky-stereo-boot.cfg
# with a stand-in for grub-probe, what 01_sparky_stereo_menu, 10_linux and 90_sparky_stereo_start write (checked by
# grub-script-check), and sparky-stereo-boot's login-check and start-finished in a fake root.
#   unfinished-start-tests.sh PACKAGE_DIR      (needs grub-common, sparky-stereo-problems; run as root in a container)
PKG=$(readlink -f "$1"); HOOK=$PKG/grub/30-sparky-stereo-boot.cfg; FIX=$PKG/tests/fixtures
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
CAT=$W/cat; mkdir -p "$CAT"; sparky-stereo-problems catalog sparky-stereo-boot "$PKG/lang" "$CAT" --subject LOCAL19 >/dev/null
pass=0; total=0
ok() { total=$((total + 1)); if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "PASS  $1: $2"; else echo "FAIL  $1: got [$2] want [$3]"; fi; }
has() { total=$((total + 1)); if printf '%s' "$2" | grep -q -e "$3"; then pass=$((pass + 1)); echo "PASS  $1"; else echo "FAIL  $1: [$3] not in: $(printf '%s' "$2" | tail -3)"; fi; }
hasnot() { total=$((total + 1)); if printf '%s' "$2" | grep -q -e "$3"; then echo "FAIL  $1: [$3] found"; else pass=$((pass + 1)); echo "PASS  $1"; fi; }
# a stand-in for grub-probe: FAKE_FS and FAKE_ABS answer for /boot/grub; the EFI system partition is FAT with a UUID
cat > "$W/probe" <<'P'
#!/bin/sh
t=; for a in "$@"; do case $a in --target=*) t=${a#--target=} ;; *) p=$a ;; esac; done
case $p in
*/boot/efi) case $t in fs) echo fat ;; abstraction) echo ;; fs_uuid) echo ABCD-1234 ;; esac ;;
*) case $t in fs) [ "$FAKE_FS" = fail ] && exit 1; echo "$FAKE_FS" ;; abstraction) echo "$FAKE_ABS" ;; esac ;;
esac
P
chmod +x "$W/probe"
mkroot() { R=$(mktemp -d -p "$W"); mkdir -p "$R/etc/default" "$R/var/lib/sparky-stereo-boot" "$R/boot/grub" "$R/sys/class/drm"; printf '%b' "${1:-}" > "$R/etc/default/sparky-stereo-boot"; echo "$R"; }
rule() {   # rule ROOT PRESET FS ABS -> RECORD|TIMEOUT|CMDLINE, the said lines in $W/said
	env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin SPARKY_STEREO_ROOT="$1" SPARKY_FONT_DIR="$1/fonts" SPARKY_STEREO_LIB="$PKG/lib" SPARKY_STEREO_LANG_DIR="$PKG/lang" \
		SPARKY_STEREO_PROBLEMS_CATALOG="$CAT:/usr/lib/systemd/catalog" SPARKY_GRUB_PROBE="$W/probe" FAKE_FS="$3" FAKE_ABS="$4" SPARKY_OS_PROBER="$W/prober" LANG=C.UTF-8 bash -c "
		GRUB_CMDLINE_LINUX=''; GRUB_TIMEOUT=5; $2
		. '$HOOK'
		printf '%s|%s|%s' \"\$SPARKY_STEREO_RECORD\" \"\$SPARKY_STEREO_RECORD_TIMEOUT\" \"\$GRUB_CMDLINE_LINUX\"" 2>"$W/said"
}
VAR=' ${sparky_stereo_check}'
printf '#!/bin/sh\nprintf "/dev/sda1@/EFI/Microsoft/Boot/bootmgfw.efi:Windows Boot Manager:Windows:efi\\n"\n' > "$W/prober"; chmod +x "$W/prober"
R=$(mkroot); ok 'ext4 /boot, the only system: GRUB keeps the flag in its own block, 30 s' "$(rule $R '' ext2 '')" "grubenv|30|$VAR"
has 'said at update-grub' "$(cat $W/said)" 'After a start that does not finish, GRUB.s menu is shown at the next start for 30 seconds'
has 'recorded for status' "$(cat $R/var/lib/sparky-stereo-boot/grub-display)" '^RECORD=grubenv$'
R=$(mkroot); ok 'beside Windows (menu shown for 5 s): the menu keeps its time' "$(rule $R 'GRUB_DISABLE_OS_PROBER=false' ext2 '')" "grubenv|5|$VAR"
R=$(mkroot); ok "the person's GRUB_RECORDFAIL_TIMEOUT wins" "$(rule $R 'GRUB_RECORDFAIL_TIMEOUT=7' ext2 '')" "grubenv|7|$VAR"
R=$(mkroot); ok "the person's own shown menu (GRUB_TIMEOUT=10) keeps its time" "$(rule $R 'GRUB_TIMEOUT=10' ext2 '')" "grubenv|10|$VAR"
R=$(mkroot); ok "the person's own hidden menu: shown for 30 s after an unfinished start" "$(rule $R 'GRUB_TIMEOUT_STYLE=hidden; GRUB_TIMEOUT=0' ext2 '')" "grubenv|30|$VAR"
R=$(mkroot); ok 'sourced with the variable already there: added once' "$(rule $R "GRUB_CMDLINE_LINUX='\${sparky_stereo_check}'" ext2 '')" 'grubenv|30|${sparky_stereo_check}'
R=$(mkroot); mkdir -p $R/sys/firmware/efi $R/boot/efi
ok 'btrfs /boot on UEFI: the flag on the EFI system partition' "$(SPARKY_GRUB_EDITENV=grub-editenv rule $R '' btrfs '')" "esp:ABCD-1234:/EFI/sparky-stereo-boot/grubenv|30|$VAR"
has 'btrfs on UEFI is said' "$(cat $W/said)" 'GRUB cannot write to /boot/grub on this computer (btrfs), so it records each start on the EFI system partition'
ok 'the block on the EFI system partition was made (1024 bytes)' "$(stat -c %s $R/boot/efi/EFI/sparky-stereo-boot/grubenv 2>&1)" 1024
R=$(mkroot); ok 'btrfs /boot on BIOS: nothing can record a start' "$(rule $R '' btrfs '')" 'none||'
has 'btrfs on BIOS is said, with the way to always show the menu' "$(cat $W/said)" 'GRUB cannot write to /boot/grub on this computer (btrfs) and there is no EFI system partition.*SPARKY_STEREO_MENU=shown'
R=$(mkroot); ok 'LVM under /boot on BIOS: none' "$(rule $R '' ext2 lvm)" 'none||'
R=$(mkroot); ok 'RAID under /boot on BIOS: none' "$(rule $R '' ext2 'diskfilter mdraid1x')" 'none||'
R=$(mkroot); ok 'grub-probe fails: none, never a guess' "$(rule $R '' fail '')" 'none||'
has 'a failed grub-probe is said' "$(cat $W/said)" 'grub-probe failed'
R=$(mkroot 'SPARKY_STEREO_UNFINISHED_START=no\n'); ok 'SPARKY_STEREO_UNFINISHED_START=no: off' "$(rule $R '' ext2 '')" 'off||'
has 'off is said' "$(cat $W/said)" 'SPARKY_STEREO_UNFINISHED_START=no in /etc/default/sparky-stereo-boot'
R=$(mkroot 'SPARKY_STEREO_BOOT=no\n'); ok 'SPARKY_STEREO_BOOT=no: GRUB as it was' "$(rule $R '' ext2 '')" 'off||'
# what the menu's files write
header() { env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin SPARKY_STEREO_RECORD="$1" SPARKY_STEREO_RECORD_TIMEOUT="$2" SPARKY_GRUB_00_HEADER="${3:-/nonexistent}" sh "$PKG/grub/01_sparky_stereo_menu"; }
script_ok() { printf '%s\n' "$1" > "$W/t.cfg"; grub-script-check "$W/t.cfg" >/dev/null 2>&1 && echo valid || echo invalid; }
out=$(header grubenv 30); ok '01 (grubenv) is valid GRUB script' "$(script_ok "$out")" valid
has '01 (grubenv) writes the function with save_env' "$out" 'if \[ -n "${sparky_record_ok}" \]; then save_env recordfail; fi'
has '01 (grubenv) shows the menu and forces the check while the flag is set' "$out" 'set sparky_stereo_check="fsck.mode=force sparky_stereo.start=unfinished"'
has '01 exports the check for the entries of a submenu' "$out" '^export sparky_stereo_check$'
has '01 (grubenv) timeout' "$out" '^	set timeout=30$'
out=$(header esp:ABCD-1234:/EFI/sparky-stereo-boot/grubenv 30); ok '01 (EFI system partition) is valid GRUB script' "$(script_ok "$out")" valid
has '01 (EFI system partition) loads and saves the flag there' "$out" 'save_env -f "(${sparky_record})/EFI/sparky-stereo-boot/grubenv" recordfail'
out=$(header none ''); hasnot '01 (none) writes no function' "$out" recordfail
out=$(header off ''); hasnot '01 (off) writes no function' "$out" recordfail
printf 'quick_boot="1"\n' > "$W/00_header"; out=$(header grubenv 30 "$W/00_header")
hasnot "01 with a GRUB built with quick boot leaves the function to 00_header" "$out" 'function recordfail'
# the wrapper around Debian's 10_linux
printf '#!/bin/sh\ncat %s\n' "$FIX/debian-10_linux.out" > "$W/10_linux.debian"; chmod +x "$W/10_linux.debian"
wrap() { env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin SPARKY_STEREO_ROOT="$W/wr" SPARKY_STEREO_LIB="$PKG/lib" SPARKY_STEREO_LANG_DIR="$PKG/lang" SPARKY_STEREO_PROBLEMS_CATALOG="$CAT:/usr/lib/systemd/catalog" \
	LANG=C.UTF-8 SPARKY_STEREO_RECORD="$1" SPARKY_STEREO_DEBIAN_10_LINUX="${2:-$W/10_linux.debian}" sh "$PKG/grub/10_linux"; }
mkdir -p "$W/wr"
out=$(wrap grubenv 2>/dev/null); ok 'each of the three Linux entries gets the call' "$(printf '%s\n' "$out" | grep -c '^[[:space:]]*recordfail$')" 3
ok 'the call is the first line of an entry, at its indentation' "$(printf '%s\n' "$out" | grep -A1 "^	menuentry 'Sparky GNU/Linux, with Linux 7.3.0" | tail -1)" '		recordfail'
ok 'nothing else changes' "$(printf '%s\n' "$out" | grep -v '^[[:space:]]*recordfail$' | cmp -s - $FIX/debian-10_linux.out && echo same)" same
ok 'the result is valid GRUB script' "$(script_ok "function recordfail { true; }
$out")" valid
ok 'off: Debian output as it is' "$(wrap off 2>/dev/null | cmp -s - $FIX/debian-10_linux.out && echo same)" same
ok 'none: Debian output as it is' "$(wrap none 2>/dev/null | cmp -s - $FIX/debian-10_linux.out && echo same)" same
printf '#!/bin/sh\nprintf "entry X {\\n\\tlinux /boot/vmlinuz\\n}\\n"\n' > "$W/odd"; chmod +x "$W/odd"
out=$(wrap grubenv "$W/odd" 2>"$W/err"); ok 'a form it does not know: the entries are still written' "$(printf '%s\n' "$out" | grep -c linux)" 1
has 'and that is said' "$(cat $W/err)" 'wrote its entries in a form sparky-stereo-boot does not know'
has 'and kept' "$(SPARKY_STEREO_ROOT=$W/wr SPARKY_STEREO_PROBLEMS_CATALOG="$CAT:/usr/lib/systemd/catalog" LANG=C.UTF-8 sparky-stereo-problems list 2>&1)" 'form sparky-stereo-boot does not know'
wrap grubenv >/dev/null 2>&1; hasnot 'cleared when the entries are known again' "$(SPARKY_STEREO_ROOT=$W/wr SPARKY_STEREO_PROBLEMS_CATALOG="$CAT:/usr/lib/systemd/catalog" LANG=C.UTF-8 sparky-stereo-problems list 2>&1)" 'form sparky-stereo-boot does not know'
wrap grubenv "$W/missing" >/dev/null 2>"$W/err"; ok "Debian's file gone: update-grub fails, said" "$?|$(grep -c 'no Linux entry can be written' $W/err)" '1|1'
chmod -x "$W/10_linux.debian"; ok 'switched off by the person (chmod -x): nothing written' "$(wrap grubenv 2>&1 | wc -c)" 0; chmod +x "$W/10_linux.debian"
# the reason on the menu
tool() { env -i PATH="$W/bin:/usr/sbin:/usr/bin:/sbin:/bin" SPARKY_STEREO_ROOT="$T" SPARKY_STEREO_LIB="$PKG/lib" SPARKY_STEREO_LANG_DIR="$PKG/lang" \
	SPARKY_STEREO_PROBLEMS_CATALOG="$CAT:/usr/lib/systemd/catalog" LANG="${TLANG:-C.UTF-8}" python3 "$PKG/bin/sparky-stereo-boot" "$@"; }
T=$W/none; mkdir -p $T
for l in en_US pt_BR fr_FR ja_JP zh_TW; do
	out=$(TLANG=$l.UTF-8 tool grub-unfinished); ok "the reason entry in $l is valid GRUB script" "$(script_ok "$out")" valid
done
has 'the reason in pt_BR' "$(TLANG=pt_BR.UTF-8 tool grub-unfinished)" "menuentry 'A última inicialização não terminou. Kernel anterior: em Opções avançadas' --id sparky-unfinished-start"
has 'only while the flag is set' "$(tool grub-unfinished)" '^if \[ "${recordfail}" = 1 \]; then$'
ok '90_sparky_stereo_start writes nothing when a start cannot be recorded' "$(SPARKY_STEREO_RECORD=none sh $PKG/grub/90_sparky_stereo_start | wc -c)" 0
# login-check: a display manager that failed to start means the start did not finish
mkdir -p "$W/bin"
dm() { printf '#!/bin/sh\nprintf "LoadState=%s\\nActiveState=%s\\n"\n' "$1" "$2" > "$W/bin/systemctl"; chmod +x "$W/bin/systemctl"; }
dm loaded failed; tool login-check 2>/dev/null; ok 'the login screen failed to start: not finished' $? 1
dm loaded active; tool login-check; ok 'the login screen started: finished' $? 0
dm not-found inactive; tool login-check; ok 'no login screen on this system: finished' $? 0
# start-finished
fin() {   # fin CMDLINE ROOTLOG FSTAB RECORD -> exit status; the kept problems in $W/list
	T=$(mktemp -d -p "$W"); mkdir -p $T/proc $T/run/initramfs $T/etc $T/boot/grub $T/var/lib/sparky-stereo-boot $T/usr/sbin
	printf '%s\n' "$1" > $T/proc/cmdline; [ -z "$2" ] || printf '%b' "$2" > $T/run/initramfs/fsck.log; printf '%b' "$3" > $T/etc/fstab
	: > $T/usr/sbin/fsck.ext4; : > $T/usr/sbin/fsck.vfat
	printf 'RECORD=%s\n' "$4" > $T/var/lib/sparky-stereo-boot/grub-display
	grub-editenv $T/boot/grub/grubenv create; grub-editenv $T/boot/grub/grubenv set recordfail=1 sparky_stereo_boot=x
	rm -f "$W/bin/systemctl"
	tool start-finished 2>"$W/err"; rc=$?
	SPARKY_STEREO_ROOT=$T SPARKY_STEREO_PROBLEMS_CATALOG="$CAT:/usr/lib/systemd/catalog" LANG=C.UTF-8 sparky-stereo-problems list > "$W/list" 2>&1
	return $rc
}
FST='UUID=aaaa / ext4 defaults 0 1\nUUID=bbbb /home btrfs defaults 0 2\nUUID=cccc swap swap noauto 0 0\nUUID=dddd /data xfs defaults 0 0\n'
LOGCLEAN='Log of fsck -C -f -a -T -t ext4 /dev/sda3\nsparky: 100/200 files (0.1% non-contiguous), 300/400 blocks\n'
LOGFIX='Log of fsck -C -f -a -T -t ext4 /dev/sda3\nsparky: Inode 12 ref count is 3, should be 1.  FIXED.\nfsck exited with status code 1\n'
LOGFIX2='Log of fsck -C -f -a -T -t ext4 /dev/sda3\nsparky: 100/200 files, 300/400 blocks\nfsck exited with status code 1\n'
LOGBAD='Log of fsck -C -f -a -T -t ext4 /dev/sda3\nsparky: UNEXPECTED INCONSISTENCY; RUN fsck MANUALLY.\nfsck exited with status code 4\n'
MARK='BOOT_IMAGE=/boot/vmlinuz root=UUID=aaaa ro fsck.mode=force sparky_stereo.start=unfinished quiet'
fin "$MARK" "$LOGCLEAN" "$FST" grubenv; ok 'a finished start after an unfinished one: exit 0' $? 0
ok 'the flag is cleared, the other variables stay' "$(grub-editenv $T/boot/grub/grubenv list | tr '\n' ' ')" 'sparky_stereo_boot=x '
has 'the person is told: the previous start did not finish' "$(cat $W/list)" 'The previous start of this computer did not finish'
has 'a clean root' "$(cat $W/list)" 'UUID=aaaa (ext4): no errors'
has 'btrfs checks itself' "$(cat $W/list)" 'UUID=bbbb (btrfs): not checked, this type checks itself when it is mounted'
hasnot 'a file system with pass 0 is not listed' "$(cat $W/list)" 'UUID=dddd'
hasnot 'swap is not listed' "$(cat $W/list)" 'UUID=cccc'
fin "$MARK" "$LOGFIX" "$FST" grubenv; has 'a repaired root is said' "$(cat $W/list)" 'UUID=aaaa (ext4): errors were repaired'
fin "$MARK" "$LOGFIX2" "$FST" grubenv; has 'the exit status alone says repaired (the real words of logsave 1.47)' "$(cat $W/list)" 'UUID=aaaa (ext4): errors were repaired'
fin "$MARK" "$LOGBAD" "$FST" grubenv; has 'errors that remain are said, with what to do' "$(cat $W/list)" 'UUID=aaaa (ext4): errors remain. Check it from another system: sudo fsck UUID=aaaa'
fin "$MARK" '' "$FST" grubenv; has 'no trace of a check is said' "$(cat $W/list)" 'UUID=aaaa (ext4): no trace of a check was found'
fin "$MARK" "$LOGCLEAN" 'UUID=aaaa / ext4 defaults 0 1\nUUID=eeee /old reiserfs defaults 0 2\n' grubenv; has 'a type with no checker installed is said' "$(cat $W/list)" 'UUID=eeee (reiserfs): not checked, no checker for this type is installed'
fin 'BOOT_IMAGE=/boot/vmlinuz root=UUID=aaaa ro quiet' "$LOGCLEAN" "$FST" grubenv; hasnot 'a start after a finished one tells nothing' "$(cat $W/list)" 'did not finish'
ok 'and the flag is cleared there too' "$(grub-editenv $T/boot/grub/grubenv list | grep -c recordfail)" 0
# the note of the start before goes at the next start
T2=$T; fin "$MARK" "$LOGCLEAN" "$FST" grubenv; printf '%s\n' 'root=UUID=aaaa ro quiet' > $T/proc/cmdline; rm -f $T/run/sparky-stereo-boot/start-finished
tool start-finished 2>/dev/null; hasnot 'the note goes at the start after that' "$(SPARKY_STEREO_ROOT=$T SPARKY_STEREO_PROBLEMS_CATALOG="$CAT:/usr/lib/systemd/catalog" LANG=C.UTF-8 sparky-stereo-problems list 2>&1)" 'did not finish'
# a flag that cannot be cleared is said and kept
T=$(mktemp -d -p "$W"); mkdir -p $T/proc $T/boot/grub $T/var/lib/sparky-stereo-boot; echo quiet > $T/proc/cmdline; echo 'RECORD=grubenv' > $T/var/lib/sparky-stereo-boot/grub-display
printf 'not an environment block\n' > $T/boot/grub/grubenv
tool start-finished 2>"$W/err"; ok 'a block that cannot be read: exit 1' $? 1
has 'said and kept' "$(SPARKY_STEREO_ROOT=$T SPARKY_STEREO_PROBLEMS_CATALOG="$CAT:/usr/lib/systemd/catalog" LANG=C.UTF-8 sparky-stereo-problems list 2>&1)" 'This start could not be recorded as finished'
# the block on the EFI system partition
T=$(mktemp -d -p "$W"); mkdir -p $T/proc $T/boot/grub $T/boot/efi/EFI/sparky-stereo-boot $T/var/lib/sparky-stereo-boot; echo quiet > $T/proc/cmdline
echo 'RECORD=esp:ABCD-1234:/EFI/sparky-stereo-boot/grubenv' > $T/var/lib/sparky-stereo-boot/grub-display
grub-editenv $T/boot/efi/EFI/sparky-stereo-boot/grubenv create; grub-editenv $T/boot/efi/EFI/sparky-stereo-boot/grubenv set recordfail=1
tool start-finished 2>/dev/null; ok 'the flag on the EFI system partition is cleared' "$?|$(grub-editenv $T/boot/efi/EFI/sparky-stereo-boot/grubenv list | grep -c recordfail)" '0|0'
# every message in the ten languages
for l in pl pt_BR fr de es ja ko zh_CN zh_TW; do
	ok "lang/$l has the keys of lang/en" "$(sed 's/=.*//' $PKG/lang/$l | sort | cmp -s - <(sed 's/=.*//' $PKG/lang/en | sort) && echo same)" same
done
echo "SUMMARY $pass of $total pass"
[ "$pass" = "$total" ]
