#!/bin/sh
# dpkg-stereo's upgrade proof, in a throwaway Debian container (root): install, project, then upgrade a
# package with one conffile the person edited and one they did not, with no terminal (stdin closed): dpkg
# must not ask, the person's edit must stay, the untouched conffile must arrive in its new version and be
# projected again; then --verify, and --restore must give back the pristine files.
# Usage: upgrade-test.sh DPKG-STEREO.deb WORKDIR
set -u
DEB=$1 W=$2
export DEBIAN_FRONTEND=noninteractive
fail=0
ok() { echo "PASS $*"; }
bad() { echo "FAIL $*"; fail=1; }
mkdir -p "$W"
mk() {   # mk VERSION SYSCTL-VALUE
	d=$W/lean-demo-$1
	rm -rf "$d"
	mkdir -p "$d/DEBIAN" "$d/etc/sysctl.d" "$d/etc/xdg" "$d/usr/bin" "$d/usr/lib/systemd/system"
	cat > "$d/etc/sysctl.d/90-lean-demo.conf" <<EOF
# lean-demo: a setting the package changes between versions.
# Explanations like this one move to the HR copy; the kernel reads only the line below.
vm.swappiness = $2
EOF
	cat > "$d/etc/xdg/leandemorc" <<'EOF'
# lean-demo's defaults, the same in both versions; the person edits this one.
# KConfig reads groups and keys; these lines are commentary.
[General]
Mode=fast
EOF
	cat > "$d/usr/bin/lean-demo" <<'EOF'
#!/bin/sh
# lean-demo: prints its settings. This comment and the next go in the lean form.
# A second line of commentary that the shell skips at every start.
cat <<'END'
# this line is data inside a heredoc and stays
END
echo "lean-demo $(cat /etc/xdg/leandemorc | grep Mode)"   # trailing commentary
EOF
	chmod 755 "$d/usr/bin/lean-demo"
	cat > "$d/usr/lib/systemd/system/lean-demo.service" <<'EOF'
# lean-demo's unit; systemd skips this line and the next.
# More commentary for people.
[Unit]
Description=lean-demo
[Service]
ExecStart=/usr/bin/lean-demo
EOF
	printf '/etc/sysctl.d/90-lean-demo.conf\n/etc/xdg/leandemorc\n' > "$d/DEBIAN/conffiles"
	printf 'Package: lean-demo\nVersion: %s\nArchitecture: all\nMaintainer: test <t@example.org>\nDescription: lean demo\n' "$1" > "$d/DEBIAN/control"
	dpkg-deb --root-owner-group -b "$d" "$W/lean-demo_$1_all.deb" >/dev/null
}
mk 1.0 10
mk 2.0 20
echo "== install dpkg-stereo (its postinst projects what is installed)"
DPKG_STEREO_NO_PROJECT=1 dpkg -i "$DEB" < /dev/null > "$W/install.log" 2>&1 || bad "dpkg-stereo install: $(tail -3 "$W/install.log")"
echo "== install lean-demo 1.0 (dpkg's post-invoke hook projects it)"
dpkg -i "$W/lean-demo_1.0_all.deb" < /dev/null > "$W/v1.log" 2>&1 || bad "lean-demo 1.0 install"
grep -q 'explanations\|Explanations' /etc/sysctl.d/90-lean-demo.conf && bad "sysctl conffile not projected" || ok "conffile projected after install"
grep -q 'commentary' /usr/bin/lean-demo && bad "script not projected" || ok "script projected"
grep -q '# this line is data inside a heredoc and stays' /usr/bin/lean-demo && ok "heredoc data kept" || bad "heredoc data lost"
[ "$(/usr/bin/lean-demo)" = "$(printf '# this line is data inside a heredoc and stays\nlean-demo Mode=fast')" ] && ok "script output unchanged" || bad "script output: $(/usr/bin/lean-demo)"
grep -q 'skips this line' /usr/lib/systemd/system/lean-demo.service && bad "unit not projected" || ok "unit projected"
head -1 /etc/sysctl.d/90-lean-demo.conf | grep -q 'Lean Code' && ok "pointer line: $(head -1 /etc/sysctl.d/90-lean-demo.conf)" || bad "no pointer line"
dpkg-stereo --verify lean-demo > "$W/verify1.log" 2>&1 && ok "dpkg-stereo --verify after install" || bad "verify after install: $(cat "$W/verify1.log")"
echo "== the person edits leandemorc (its lean form)"
printf 'Mode=slow\n' >> /etc/xdg/leandemorc
cp /etc/xdg/leandemorc "$W/edited.rc"
echo "== upgrade to 2.0 with no terminal: dpkg must not ask"
dpkg -i "$W/lean-demo_2.0_all.deb" < /dev/null > "$W/v2.log" 2>&1
rc=$?
[ $rc = 0 ] && ok "upgrade exit 0" || bad "upgrade exit $rc: $(tail -5 "$W/v2.log")"
grep -qi "configuration file\|conffile.*modified\|\*\*\* .* (Y/I/N/O/D/Z)" "$W/v2.log" && bad "dpkg asked: $(grep -i 'configuration file' "$W/v2.log")" || ok "no conffile prompt"
cmp -s /etc/xdg/leandemorc "$W/edited.rc" && ok "the person's edit kept" || bad "the edit changed: $(cat /etc/xdg/leandemorc)"
grep -q 'vm.swappiness = 20' /etc/sysctl.d/90-lean-demo.conf && ok "untouched conffile now version 2.0" || bad "sysctl conffile not upgraded"
grep -q 'Explanations' /etc/sysctl.d/90-lean-demo.conf && bad "version 2.0 conffile not projected" || ok "version 2.0 conffile projected again"
[ ! -e /etc/sysctl.d/90-lean-demo.conf.dpkg-new ] && [ ! -e /etc/sysctl.d/90-lean-demo.conf.dpkg-old ] && [ ! -e /etc/xdg/leandemorc.dpkg-new ] && ok "no .dpkg-new or .dpkg-old left" || bad "dpkg left .dpkg-new/.dpkg-old files"
dpkg-stereo --verify lean-demo > "$W/verify2.log" 2>&1; cat "$W/verify2.log"
grep -q 'leandemorc (changed by the person' "$W/verify2.log" && ok "verify names the person's edit" || bad "verify misses the edit"
echo "== dpkg's own view"
dpkg --verify lean-demo > "$W/dpkgverify.log" 2>&1; cat "$W/dpkgverify.log"
echo "== reinstall through dpkg again (same version): no prompt, still lean"
dpkg -i "$W/lean-demo_2.0_all.deb" < /dev/null > "$W/v2b.log" 2>&1 && ok "reinstall exit 0" || bad "reinstall"
grep -q 'Explanations' /etc/sysctl.d/90-lean-demo.conf && bad "reinstalled conffile not projected" || ok "reinstalled conffile projected"
echo "== the way back"
cp "$W/lean-demo_2.0_all.deb" /var/cache/apt/archives/
dpkg-stereo --restore lean-demo > "$W/restore.log" 2>&1; cat "$W/restore.log"
grep -q 'Explanations' /etc/sysctl.d/90-lean-demo.conf && ok "conffile restored" || bad "conffile not restored"
grep -q 'commentary' /usr/bin/lean-demo && ok "script restored" || bad "script not restored"
cmp -s /etc/xdg/leandemorc "$W/edited.rc" && ok "the person's edit still kept" || bad "restore touched the edit"
dpkg --verify lean-demo > "$W/dpkgverify2.log" 2>&1; cat "$W/dpkgverify2.log"
[ "$(grep -c . "$W/dpkgverify2.log")" = 1 ] && grep -q leandemorc "$W/dpkgverify2.log" && ok "dpkg --verify: only the person's edit differs" || bad "dpkg --verify after restore: $(cat "$W/dpkgverify2.log")"
echo "== purge"
dpkg --purge lean-demo < /dev/null > "$W/purge.log" 2>&1 && ok "purge" || bad "purge"
[ $fail = 0 ] && echo "ALL PASS" || echo "SOME FAILED"
exit $fail
