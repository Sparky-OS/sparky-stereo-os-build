#!/bin/bash
# Row 813: --verify names a person's change to a file that maintainer scripts keep through ucf. Such a file is in no
# package's file list, so neither dpkg --verify nor dpkg-stereo's records judge it; ucf(1) records the md5sum of what it
# last wrote (/var/lib/ucf/hashfile) and ucfr(1) the package that registered it (/var/lib/ucf/registry).
# Usage: ucf-test.sh DPKG-STEREO.deb WORKDIR   (a throwaway container, root, no network, the published edition with ucf
# and packages that keep files through it: samba-common's smb.conf and grub-efi-amd64's /etc/default/grub registered
# with ucfr, nfs-common's /etc/nfs.conf and /etc/idmapd.conf without, and its /etc/default/nfs-common both a conffile
# of its list, which Lean Code projects, and a ucf-kept file). DEB is the one under test.
# Red on 0.1.45, and in U4 on continuation 12's first 0.1.46 build (a gone file was MISSING and counted); green on
# 0.1.46. Exit 1 on any FAIL.
set -u
DEB=$(readlink -f "$1") W=$2
export DEBIAN_FRONTEND=noninteractive
fail=0
ok() { echo "PASS $*"; }
bad() { echo "FAIL $*"; fail=1; [ ! -f "$W/v.txt" ] || tail -4 "$W/v.txt" | sed 's/^/      /'; }
check() { d=$1; shift; if "$@"; then ok "$d"; else bad "$d"; fi; }
mkdir -p "$W"
END='(changed by the person: left as they made it)'
v() { dpkg-stereo --verify "$@" >"$W/v.txt" 2>&1; echo $? >"$W/v.rc"; }
row() { grep -q -x -F "$1" "$W/v.txt"; }
no_ucf_rows() { ! grep -q -E '^(EDITED|MISSING) .* through ucf\)' "$W/v.txt"; }
rc() { [ "$(cat "$W/v.rc")" = "$1" ]; }
ucf_state() { find /var/lib/ucf -type f -exec sha256sum {} + | sort; }

dpkg -i "$DEB" >"$W/install.log" 2>&1 || { echo "FAIL installing $DEB"; tail -5 "$W/install.log"; exit 1; }
echo "dpkg-stereo $(dpkg-query -W -f='${Version}' dpkg-stereo); ucf $(dpkg-query -W -f='${Version}' ucf)"
for p in /etc/samba/smb.conf /etc/default/grub /etc/nfs.conf /etc/idmapd.conf /etc/default/nfs-common; do
	grep -q -F " $p" /var/lib/ucf/hashfile || { echo "FAIL the rig: ucf keeps no $p"; exit 1; }
done
ucf_state >"$W/ucf-before.txt"

# U1: an untouched system shows no row; /etc/default/nfs-common differs from ucf's md5sum only because Lean Code
# projected it as nfs-common's conffile, and stays with that judgement
v
check "U1 untouched: no row about a file kept through ucf, exit 0" no_ucf_rows
check "U1 untouched: --verify exit 0" rc 0
check "U1 untouched: the summary counts the files kept through ucf" grep -q -E 'dpkg-stereo: .*, [0-9]+ files kept through ucf checked' "$W/v.txt"
lean=$(md5sum </etc/default/nfs-common | cut -d' ' -f1)
kept=$(awk '$2 == "/etc/default/nfs-common" {print $1}' /var/lib/ucf/hashfile)
check "U1 the rig: /etc/default/nfs-common is lean ($lean), unlike ucf's md5sum ($kept)" [ "$lean" != "$kept" ]

# U2: a person's change to a registered file: named with its package, not counted
cp -p /etc/samba/smb.conf "$W/smb.conf"; cp -p /etc/default/grub "$W/grub"
echo '# a person was here' >>/etc/samba/smb.conf
sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=7/' /etc/default/grub
v
check "U2 edited smb.conf named with samba-common" row "EDITED    /etc/samba/smb.conf (kept by samba-common through ucf) $END"
check "U2 edited /etc/default/grub named with grub-efi-amd64" row "EDITED    /etc/default/grub (kept by grub-efi-amd64 through ucf) $END"
check "U2 the person's changes are not counted (exit 0)" rc 0

# U3: a file handed to ucf without ucfr: named, with no package
cp -p /etc/nfs.conf "$W/nfs.conf"; echo '# a person was here' >>/etc/nfs.conf
v
check "U3 edited /etc/nfs.conf named, kept through ucf with no package" row "EDITED    /etc/nfs.conf (kept through ucf) $END"

# U4 (continuation 13): a file kept through ucf that is gone is no fault and not the person's either: ucf leaves a
# removed file removed ("Not replacing deleted config file"), and who removed it cannot be told. --verify prints no row
# and counts nothing, its summary says how many, --verify --deep lists each as GONE, and the exit status is the same as
# with the files there. Two shapes: a registered file removed by hand (samba-common's smb.conf), and a record whose file
# a package's own script removed with no ucf --purge (libdebuginfod-common 0.196-1's postinst when its debconf answer is
# false: rm -f /etc/profile.d/debuginfod.sh). A link whose target is gone is no gone file: it stands at the name.
d=$W/uc-dropper; mkdir -p "$d/DEBIAN" "$d/usr/share/uc-dropper"
printf 'export UC_DROPPER=1\n' >"$d/usr/share/uc-dropper/uc-dropper.sh"
cat >"$d/DEBIAN/postrm" <<'UC_DROPPER_POSTRM_END'
#!/bin/sh
set -e
# unlike libdebuginfod-common's purge, which skips ucf's records when the file is already gone, this one leaves nothing
if [ "$1" = purge ] && command -v ucf >/dev/null; then
	ucf --purge /etc/profile.d/uc-dropper.sh
	ucfr --purge uc-dropper /etc/profile.d/uc-dropper.sh
	rm -f /etc/profile.d/uc-dropper.sh
fi
UC_DROPPER_POSTRM_END
for ver in 1.0 1.1; do
	printf 'Package: uc-dropper\nVersion: %s\nArchitecture: all\nMaintainer: test <t@example.org>\nDepends: ucf\nDescription: keeps a file through ucf, then removes it\n' "$ver" >"$d/DEBIAN/control"
	if [ "$ver" = 1.0 ]; then
		printf '#!/bin/sh\nset -e\nif [ "$1" = configure ]; then\n\tDEBIAN_FRONTEND=noninteractive ucf /usr/share/uc-dropper/uc-dropper.sh /etc/profile.d/uc-dropper.sh\n\tucfr uc-dropper /etc/profile.d/uc-dropper.sh\nfi\n' >"$d/DEBIAN/postinst"
	else
		printf '#!/bin/sh\nset -e\nif [ "$1" = configure ]; then\n\trm -f /etc/profile.d/uc-dropper.sh\nfi\n' >"$d/DEBIAN/postinst"
	fi
	chmod 755 "$d/DEBIAN/postinst" "$d/DEBIAN/postrm"
	dpkg-deb --root-owner-group -b "$d" "$W/uc-dropper_$ver.deb" >/dev/null
done
summary_has() { grep '^dpkg-stereo: ' "$W/v.txt" | grep -q -F -- "$1"; }
GONE_SUM=', 2 files kept through ucf are gone (ucf leaves a removed file removed)'
dpkg -i "$W/uc-dropper_1.0.deb" >>"$W/uc.log" 2>&1
check "U4 setup: uc-dropper 1.0 keeps /etc/profile.d/uc-dropper.sh through ucf" bash -c 'grep -q -F " /etc/profile.d/uc-dropper.sh" /var/lib/ucf/hashfile && grep -q "^uc-dropper .*/etc/profile.d/uc-dropper.sh" /var/lib/ucf/registry && [ -f /etc/profile.d/uc-dropper.sh ]'
v; base=$(cat "$W/v.rc")
v --deep samba-common uc-dropper; base_deep=$(cat "$W/v.rc")
mv /etc/samba/smb.conf "$W/smb.conf.u2"
dpkg -i "$W/uc-dropper_1.1.deb" >>"$W/uc.log" 2>&1
check "U4 setup: smb.conf removed by hand, uc-dropper 1.1's postinst removed its file; ucf's records name both" bash -c '[ ! -e /etc/samba/smb.conf ] && [ ! -e /etc/profile.d/uc-dropper.sh ] && grep -q -F " /etc/profile.d/uc-dropper.sh" /var/lib/ucf/hashfile && grep -q -F " /etc/samba/smb.conf" /var/lib/ucf/hashfile'
v
check "U4 gone: --verify prints no row for either" bash -c '! grep -q -E "^[A-Z]+ +(/etc/samba/smb.conf|/etc/profile.d/uc-dropper.sh) " '"$W/v.txt"
check "U4 gone: not counted, --verify exit 0 as before ($base)" bash -c '[ "$(cat '"$W/v.rc"')" = 0 ] && [ '"$base"' = 0 ]'
check "U4 gone: the summary says 2 files kept through ucf are gone" summary_has "$GONE_SUM"
check "U4 gone: the summary counts no problem" grep -q -E '^dpkg-stereo: [0-9]+ projected files checked, 0 problems' "$W/v.txt"
v --deep samba-common uc-dropper
check "U4 gone: --deep lists smb.conf as GONE" row "GONE      /etc/samba/smb.conf (kept by samba-common through ucf)"
check "U4 gone: --deep lists uc-dropper's file as GONE" row "GONE      /etc/profile.d/uc-dropper.sh (kept by uc-dropper through ucf)"
check "U4 gone: --deep's exit status as before ($base_deep)" rc "$base_deep"
check "U4 gone: --deep has no MISSING row" bash -c '! grep -q "^MISSING" '"$W/v.txt"
mv /etc/idmapd.conf "$W/idmapd.conf"; ln -s /nonexistent/idmapd.conf /etc/idmapd.conf
v
check "U4 a link whose target is gone stands at the name: EDITED" row "EDITED    /etc/idmapd.conf (kept through ucf) $END"
check "U4 the link is not counted among the gone (still 2)" summary_has "$GONE_SUM"
rm -f /etc/idmapd.conf; mv "$W/idmapd.conf" /etc/idmapd.conf
mv "$W/smb.conf.u2" /etc/samba/smb.conf
dpkg -P uc-dropper >>"$W/uc.log" 2>&1
v
check "U4 back: no gone file left, nothing about uc-dropper" bash -c '! grep -q -E "are gone|uc-dropper" '"$W/v.txt"

# U5: only the named packages: --verify samba-common leaves grub's and the unregistered nfs.conf out
v samba-common
check "U5 --verify samba-common names smb.conf" row "EDITED    /etc/samba/smb.conf (kept by samba-common through ucf) $END"
check "U5 --verify samba-common leaves out grub and nfs.conf" bash -c '! grep -q -E "/etc/default/grub|/etc/nfs.conf" '"$W/v.txt"

# U6: nfs-common's /etc/default/nfs-common, its conffile and ucf-kept, changed by the person: named once, by its
# conffile record, never by the ucf reading
echo 'NEED_STATD=no' >>/etc/default/nfs-common
v
check "U6 the conffile also kept through ucf is named by its record" grep -q -E '^CHANGED   /etc/default/nfs-common \(changed by the person\)$' "$W/v.txt"
check "U6 and not by the ucf reading" bash -c '! grep -q "/etc/default/nfs-common (kept" '"$W/v.txt"

# U7: a package that diverts another package's conffile and keeps its own file at the name through ucf (as
# sparky-stereo-console keeps /etc/issue): named at the name; the owner's copy at the diverted name keeps its own rule
d=$W/uc-owner; mkdir -p "$d/DEBIAN" "$d/etc/default"
printf '# uc-owner: the package that owns this setting.\n# Commentary nothing reads.\nUC_DEMO=owner\n' >"$d/etc/default/uc-demo"
echo /etc/default/uc-demo >"$d/DEBIAN/conffiles"
printf 'Package: uc-owner\nVersion: 1.0\nArchitecture: all\nMaintainer: test <t@example.org>\nDescription: owner of a conffile\n' >"$d/DEBIAN/control"
dpkg-deb --root-owner-group -b "$d" "$W/uc-owner.deb" >/dev/null
d=$W/uc-keeper; mkdir -p "$d/DEBIAN" "$d/usr/share/uc-keeper"
printf 'UC_DEMO=keeper\n' >"$d/usr/share/uc-keeper/uc-demo"
printf 'Package: uc-keeper\nVersion: 1.0\nArchitecture: all\nMaintainer: test <t@example.org>\nDepends: ucf\nDescription: keeps its own file at a diverted name\n' >"$d/DEBIAN/control"
cat >"$d/DEBIAN/preinst" <<'UC_PREINST_END'
#!/bin/sh
set -e
[ "$1" = install ] && dpkg-divert --quiet --package uc-keeper --add --rename --divert /etc/default/uc-demo.debian /etc/default/uc-demo
exit 0
UC_PREINST_END
cat >"$d/DEBIAN/postinst" <<'UC_POSTINST_END'
#!/bin/sh
set -e
if [ "$1" = configure ]; then
	DEBIAN_FRONTEND=noninteractive ucf --package uc-keeper /usr/share/uc-keeper/uc-demo /etc/default/uc-demo
	ucfr uc-keeper /etc/default/uc-demo
fi
UC_POSTINST_END
cat >"$d/DEBIAN/postrm" <<'UC_POSTRM_END'
#!/bin/sh
set -e
if { [ "$1" = remove ] || [ "$1" = purge ]; } && [ "$(dpkg-divert --listpackage /etc/default/uc-demo)" = uc-keeper ]; then
	rm -f /etc/default/uc-demo /etc/default/uc-demo.ucf-dist
	if command -v ucf >/dev/null; then ucf --package uc-keeper --purge /etc/default/uc-demo; ucfr --purge uc-keeper /etc/default/uc-demo; fi
	dpkg-divert --quiet --package uc-keeper --remove --rename --divert /etc/default/uc-demo.debian /etc/default/uc-demo
fi
UC_POSTRM_END
chmod 755 "$d/DEBIAN/preinst" "$d/DEBIAN/postinst" "$d/DEBIAN/postrm"
dpkg-deb --root-owner-group -b "$d" "$W/uc-keeper.deb" >/dev/null
dpkg -i "$W/uc-owner.deb" >"$W/uc.log" 2>&1 && dpkg -i "$W/uc-keeper.deb" >>"$W/uc.log" 2>&1
check "U7 setup: uc-keeper's file at the name, the owner's at the diverted name" bash -c 'grep -q keeper /etc/default/uc-demo && grep -q owner /etc/default/uc-demo.debian' || tail -8 "$W/uc.log"
v uc-owner uc-keeper
check "U7 untouched: no row for the diverted name or its owner's copy" bash -c '! grep -q uc-demo '"$W/v.txt"
echo 'UC_DEMO=person' >/etc/default/uc-demo
v uc-owner uc-keeper
check "U7 the person's change at the diverted name: named with uc-keeper" row "EDITED    /etc/default/uc-demo (kept by uc-keeper through ucf) $END"
dpkg -P uc-keeper >>"$W/uc.log" 2>&1
check "U7 removal: the owner's file back, ucf's records gone" bash -c 'grep -q owner /etc/default/uc-demo && ! grep -q uc-demo /var/lib/ucf/hashfile /var/lib/ucf/registry'
v uc-owner
check "U7 after the removal: no row" bash -c '! grep -q uc-demo '"$W/v.txt"
dpkg -P uc-owner >>"$W/uc.log" 2>&1

# U8: a non-root run: said once, never a row per file; incomplete (exit 2). A non-root --verify stops at dpkg-stereo's
# own guard (LOCAL23) before it reads anything; a file kept through ucf that root cannot read is counted the same way
cp -p "$W/smb.conf" /etc/samba/smb.conf; cp -p "$W/grub" /etc/default/grub; cp -p "$W/nfs.conf" /etc/nfs.conf
sed -i '$d' /etc/default/nfs-common
chmod 600 /etc/default/grub /etc/samba/smb.conf
id -u ucftest >/dev/null 2>&1 || useradd -M ucftest
runuser -u ucftest -- dpkg-stereo --verify >"$W/v.txt" 2>&1; echo $? >"$W/v.rc"
check "U8 non-root: no row for the unreadable files" bash -c '! grep -q -E "^(EDITED|MISSING) +/etc/(default/grub|samba/smb.conf)" '"$W/v.txt"
check "U8 non-root: said once, with the command" bash -c '[ "$(grep -c "This needs root: sudo dpkg-stereo --verify" '"$W/v.txt"')" = 1 ]'
check "U8 non-root: an incomplete check (exit 2)" rc 2
chmod 644 /etc/default/grub /etc/samba/smb.conf
v
check "U8 root again: no row about a file kept through ucf" no_ucf_rows
check "U8 root again: exit 0" rc 0

# U9: --verify writes nothing in /var/lib/ucf (U7's package added and purged its own rows: compare the files of ucf
# itself, every one but the rotated copies ucf makes at each change)
ucf_state | grep -v -E '/(hashfile|registry)\.[0-9]+$' >"$W/ucf-after.txt"
grep -v -E '/(hashfile|registry)\.[0-9]+$' "$W/ucf-before.txt" >"$W/ucf-before-main.txt"
check "U9 nothing in /var/lib/ucf changed by --verify" cmp -s "$W/ucf-before-main.txt" "$W/ucf-after.txt"

# U10: the dpkg hooks read nothing of ucf's; --verify does (an audit hook logs every open under /var/lib/ucf)
mkdir -p "$W/audit"
cat >"$W/audit/sitecustomize.py" <<'UC_AUDIT_END'
import sys


def _log(event, args):
    if event == 'open' and args and isinstance(args[0], str) and args[0].startswith('/var/lib/ucf'):
        with open('/tmp/ucf-opens.log', 'a') as f:
            f.write(' '.join(sys.argv[1:3]) + ' ' + args[0] + '\n')


sys.addaudithook(_log)
UC_AUDIT_END
rm -f /tmp/ucf-opens.log
PYTHONPATH="$W/audit" dpkg -i "$W/uc-owner.deb" >>"$W/uc.log" 2>&1
PYTHONPATH="$W/audit" dpkg -P uc-owner >>"$W/uc.log" 2>&1
hook_opens=$(cat /tmp/ucf-opens.log 2>/dev/null | wc -l)
check "U10 the dpkg hooks (pre-invoke, post-invoke) open nothing under /var/lib/ucf ($hook_opens)" [ "$hook_opens" = 0 ]
PYTHONPATH="$W/audit" dpkg-stereo --verify >/dev/null 2>&1
check "U10 control: --verify does read ucf's hashfile" grep -q '/var/lib/ucf/hashfile' /tmp/ucf-opens.log

# the cost of the reading in --verify: median of five, with ucf's files and with /var/lib/ucf moved away
t() { s=$(date +%s%N); dpkg-stereo --verify >/dev/null 2>&1; echo $(( ($(date +%s%N) - s) / 1000000 )); }
with=$(for i in 1 2 3 4 5; do t; done | sort -n | sed -n 3p)
mv /var/lib/ucf /var/lib/ucf.away
without=$(for i in 1 2 3 4 5; do t; done | sort -n | sed -n 3p)
mv /var/lib/ucf.away /var/lib/ucf
echo "INFO --verify median of five: $with ms with $(wc -l </var/lib/ucf/hashfile) files kept through ucf, $without ms without /var/lib/ucf"

[ $fail = 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit $fail
