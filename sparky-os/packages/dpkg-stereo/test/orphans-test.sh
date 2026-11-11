#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: MIT
# The records dpkg-stereo 0.1.28 and older lost come back on an upgrade, and a removed package's lean conffiles go back
# to its package's bytes (ORDER 373), in a throwaway Debian container (root, no network needed) with systemd, the
# edition's dpkg and the problems engine installed. 0.1.28 is installed first and loses the records the way ORDER 367
# found: one `dpkg --no-triggers -i` of a package that ships a file under /usr/lib/systemd/catalog (and one under a
# fixture's trigger folder) leaves systemd and the fixtures triggers-pending, 0.1.28's post-invoke drops their records,
# and the run that processes the triggers leaves their lean files as "changed since its package installed it" (lean
# conffiles as "changed by the person"). Then the package under test is installed over it:
#   A. systemd's lean files get their records back from its .deb in APT's cache (conffiles too, with their pristine
#      copies), --verify checks them, and --restore brings back every original; a systemd file the person edited after
#      its projection stays theirs
#   B. fixtures: a script and a conffile get their records back; a file the person edited stays theirs; a package whose
#      .deb a configured source offers gets its records from that source inside the dpkg run; a projection today's check
#      refuses (made by hand, as an older engine's) goes back to its package's bytes; what came back and what stayed is
#      said once
#   C. a package whose .deb is nowhere: its rows stay, --verify names its files (UNRECORDED, exit 2), the step is kept
#      as a problem naming the version, why and what gives the records back; --repair asks snapshot.debian.org (a local
#      server answering as its interface does) and gives the records back, and the problem goes
#   D. removal: a removed package's lean conffile goes back to its package's bytes, so installing it again is quiet and
#      the conffile is projected and recorded again; a conffile the person changed stays as they made it; a purge
#      removes them; a record whose lean hash is wrong (forged here to the person's edit, so every hash passes) never
#      gets the person's edit overwritten: only a file today's renderer makes from the original goes back, and the
#      other is said
# Usage: orphans-test.sh OLD.deb (0.1.28) NEW.deb (the package under test) SYSTEMD.deb (the installed systemd's .deb)
#   WORKDIR
set -u
# apt over HTTPS only (ORDER 400b, CVE-2026-109518): the container mounts the host's CA bundle at /run/host-ca.crt and
# tools/https-only-apt.sh at /run/https-only-apt.sh (read-only); a missing helper stops the script
sh /run/https-only-apt.sh || exit 1
OLD=$1 NEW=$2 SYSTEMD_DEB=$3 W=$4
export DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8
fail=0 passed=0 failed=0
ok() { echo "PASS $*"; passed=$((passed + 1)); }
bad() { echo "FAIL $*"; fail=1; failed=$((failed + 1)); }
check() { local name=$1; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
R=/var/lib/dpkg-stereo
recorded() { grep -q "^$2	" "$R/records/$1.tsv" 2>/dev/null; }
leftrow() { grep -q "^$2	$1	" "$R/left/$1.tsv" 2>/dev/null; }
leftwhy() { grep "^$2	$1	" "$R/left/$1.tsv" 2>/dev/null | cut -f4; }
md5ok() { [ "$(md5sum <"$2" | cut -d' ' -f1)" = "$(grep "  ${2#/}\$" "/var/lib/dpkg/info/$1.md5sums" | cut -c1-32)" ]; }
confok() { [ "$(md5sum <"$2" | cut -d' ' -f1)" = "$(dpkg-query -W -f '${Conffiles}\n' "$1" | awk -v p="$2" '$1 == p {print $2}')" ]; }
lean() { grep -q '^# Lean Code: HR in' "$1"; }
command -v sparky-stereo-problems >/dev/null || { echo "needs the problems engine (sparky-stereo-problems)"; exit 2; }
[ "$(dpkg-query -W -f '${Version}' systemd 2>/dev/null)" = "$(dpkg-deb -f "$SYSTEMD_DEB" Version)" ] ||
	{ echo "$SYSTEMD_DEB is not the installed systemd's version"; exit 2; }
CACHE=/var/cache/apt/archives
PORT=18373
rm -rf "$W"
mkdir -p "$W/debs" "$W/srv/mr" "$W/srv/file" /srv/orph "$CACHE"
printf '#!/bin/sh\nexit 101\n' >/usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d
# no network and no other source: what a case needs is where it puts it
rm -f /etc/apt/sources.list /etc/apt/sources.list.d/* "$CACHE"/*.deb
apt-get update -qq >/dev/null 2>&1

mk() {   # mk NAME VERSION OUT-DIR [TRIGGER-INTEREST]: a script, a script the person edits, a script bash refuses, a conffile
	local d=$W/src/$1-$2
	rm -rf "$d"
	mkdir -p "$d/DEBIAN" "$d/usr/bin" "$d/usr/share/$1" "$d/etc/xdg"
	printf '#!/bin/sh\n# %s %s: commentary the shell skips at every start, a line long enough to count.\n# A second line of commentary, long enough that the projection is worth its pointer line.\n# A third line of commentary for people.\necho "%s %s"\n' "$1" "$2" "$1" "$2" >"$d/usr/bin/$1"
	printf '#!/bin/sh\n# %s: a helper the person will edit; commentary for people, long enough to count.\n# A second line of commentary, long enough that the projection is worth its pointer line.\necho helper\n' "$1" >"$d/usr/share/$1/helper.sh"
	# a fragment bash does not accept on its own (an if another script closes): today's check refuses to project it
	printf '#!/bin/bash\n# %s: a fragment another script sources; commentary long enough to be worth the pointer line.\n# A second line of commentary, long enough that the projection is worth its pointer line.\n# A third line of commentary for people.\nif [ -n "$X" ]; then\n\techo fragment\n' "$1" >"$d/usr/share/$1/fragment.sh"
	chmod 755 "$d/usr/bin/$1" "$d/usr/share/$1/helper.sh" "$d/usr/share/$1/fragment.sh"
	printf '# %s defaults: commentary for people; KConfig reads groups and keys only.\n# A second line of commentary, long enough that the projection is worth its pointer line.\n[General]\nMode=fast\n' "$1" >"$d/etc/xdg/$1rc"
	printf '/etc/xdg/%src\n' "$1" >"$d/DEBIAN/conffiles"
	printf 'Package: %s\nVersion: %s\nArchitecture: all\nMaintainer: test <t@example.org>\nDescription: orphans test\n' "$1" "$2" >"$d/DEBIAN/control"
	if [ -n "${4:-}" ]; then
		printf 'interest-noawait %s\n' "$4" >"$d/DEBIAN/triggers"
		printf '#!/bin/sh\nexit 0\n' >"$d/DEBIAN/postinst"
		chmod 755 "$d/DEBIAN/postinst"
	fi
	dpkg-deb --root-owner-group -b "$d" "$3/$1_$2_all.deb" >/dev/null
}
mk orph-watch 1.0 "$W/debs" /usr/share/orph-watched
mk orph-src 1.0 "$W/debs" /usr/share/orph-watched
mk orph-gone 1.0 "$W/debs" /usr/share/orph-watched
mk orph-rm 1.0 "$W/debs"
mk orph-rm2 1.0 "$W/debs"
mk orph-rm3 1.0 "$W/debs"
d=$W/src/orph-feed; mkdir -p "$d/DEBIAN" "$d/usr/share/orph-watched" "$d/usr/lib/systemd/catalog"
echo data >"$d/usr/share/orph-watched/feed.txt"
printf -- '-- 0123456789abcdef0123456789abcdef\nSubject: orphans test\n' >"$d/usr/lib/systemd/catalog/orph-feed.catalog"
printf 'Package: orph-feed\nVersion: 1.0\nArchitecture: all\nMaintainer: test <t@example.org>\nDescription: activates the triggers\n' >"$d/DEBIAN/control"
dpkg-deb --root-owner-group -b "$d" "$W/debs/orph-feed_1.0_all.deb" >/dev/null

echo "== 0.1.28 installed, and its records lost"
# what the image itself changed in systemd's files, before any projection
dpkg --verify systemd 2>/dev/null | awk '$1 ~ /^..5/ {print $NF}' | sort >"$W/systemd-changed-before.txt"
dpkg -i "$OLD" </dev/null >"$W/old.log" 2>&1 || bad "install $OLD: $(tail -3 "$W/old.log")"
check "control: the old version is 0.1.28" [ "$(dpkg-query -W -f '${Version}' dpkg-stereo)" = 0.1.28 ]
dpkg -i "$W/debs/orph-watch_1.0_all.deb" "$W/debs/orph-src_1.0_all.deb" "$W/debs/orph-gone_1.0_all.deb" </dev/null \
	>"$W/fixtures.log" 2>&1 || bad "install the fixtures: $(tail -3 "$W/fixtures.log")"
before=$(grep -vc '^#' "$R/records/systemd.tsv")
check "control: systemd projected and recorded by 0.1.28 ($before records)" [ "$before" -gt 100 ]
check "control: orph-watch's script lean and recorded" bash -c "$(declare -f lean recorded); R=$R; lean /usr/bin/orph-watch && recorded orph-watch /usr/bin/orph-watch"
pre=$(grep -c "	systemd	.*changed since its package installed it" "$R/left/systemd.tsv" 2>/dev/null)
preconf=$(grep -c "	systemd	.*conffile changed by the person" "$R/left/systemd.tsv" 2>/dev/null)
check "control: today's check leaves the fragment authored" sh -c "! grep -q '^# Lean Code' /usr/share/orph-watch/fragment.sh"
dpkg --no-triggers -i "$W/debs/orph-feed_1.0_all.deb" </dev/null >"$W/feed.log" 2>&1 || bad "install orph-feed: $(tail -3 "$W/feed.log")"
check "control: systemd's trigger pending" [ "$(dpkg-query -W -f '${Status}' systemd)" = "install ok triggers-pending" ]
dpkg --triggers-only -a </dev/null >"$W/triggers.log" 2>&1 || bad "dpkg --triggers-only -a: $(tail -3 "$W/triggers.log")"
check "control: systemd installed again" [ "$(dpkg-query -W -f '${Status}' systemd)" = "install ok installed" ]
# the same through a removal (apt's runs pass --no-triggers to removals too): pre-invoke puts no conffile back for a
# removal, so the conffiles are lean when post-invoke drops their records, and the next projection calls them the
# person's (as /etc/default/nss on the station)
dpkg --no-triggers -r orph-feed </dev/null >"$W/feed-rm.log" 2>&1 || bad "remove orph-feed: $(tail -3 "$W/feed-rm.log")"
check "control: systemd's trigger pending again" [ "$(dpkg-query -W -f '${Status}' systemd)" = "install ok triggers-pending" ]
dpkg --triggers-only -a </dev/null >"$W/triggers2.log" 2>&1 || bad "dpkg --triggers-only -a: $(tail -3 "$W/triggers2.log")"
lost=$(grep -c "	systemd	.*changed since its package installed it" "$R/left/systemd.tsv" 2>/dev/null)
lostconf=$(grep -c "	systemd	.*conffile changed by the person" "$R/left/systemd.tsv" 2>/dev/null)
check "control: 0.1.28 lost systemd's records ($lost files left as changed, $lostconf conffiles as the person's; $pre and $preconf before)" \
	bash -c "[ $lost -gt $((pre + 100)) ] && [ $lostconf -gt $preconf ]"
check "control: systemd records left ($(grep -vc '^#' "$R/records/systemd.tsv" 2>/dev/null))" [ "$(grep -vc '^#' "$R/records/systemd.tsv" 2>/dev/null || echo 0)" -lt 20 ]
check "control: orph-watch's script left as changed since its package installed it" bash -c "$(declare -f leftrow); R=$R; leftrow orph-watch /usr/bin/orph-watch"
check "control: orph-watch's conffile left as changed by the person" bash -c "$(declare -f leftwhy); R=$R; leftwhy orph-watch /etc/xdg/orph-watchrc | grep -q 'conffile changed by the person'"
check "control: its script still lean" bash -c "$(declare -f lean); lean /usr/bin/orph-watch"
# the person edits two lean files after their projection: one of systemd's, one of orph-watch's
EDITED=$(grep -l '^# Lean Code: HR in' $(dpkg -L systemd | grep '^/usr/lib/tmpfiles.d/.*\.conf$') 2>/dev/null | head -1)
check "control: a lean systemd file to edit ($EDITED)" [ -n "$EDITED" ]
echo '# the person keeps this line' >>"$EDITED"
echo '# the person keeps this line' >>/usr/share/orph-watch/helper.sh
cp "$EDITED" "$W/edited.copy"
cp /usr/share/orph-watch/helper.sh "$W/helper.copy"
# an older engine's projection that today's check refuses: the fragment rendered without its check, left as changed
python3 - <<'EOF'
import sys
sys.path.insert(0, '/usr/lib/dpkg-stereo')
from lean import project
p = '/usr/share/orph-watch/fragment.sh'
r = project.project(p, open(p, 'rb').read(), 'orph-watch', check=False)
assert r.status == 'projected', r.reason
open(p, 'wb').write(r.lean)
t = '/var/lib/dpkg-stereo/left/orph-watch.tsv'
lines = [l for l in open(t) if not l.startswith(p + '\t')]
lines.append(f"{p}\torph-watch\tshell\tchanged since its package installed it (not the package's bytes)\n")
open(t, 'w').writelines(lines)
EOF
# every row a projection left for a lean file it found without its record, before the package under test comes
python3 - >"$W/orphans-before.tsv" <<'EOF'
import os
R = '/var/lib/dpkg-stereo/left'
for f in sorted(os.listdir(R)):
    for line in open(os.path.join(R, f), encoding='utf-8', errors='surrogateescape'):
        v = line.rstrip('\n').split('\t')
        if len(v) == 4 and v[3].startswith(('changed since its package installed it', 'conffile changed by the person')):
            print(v[0] + '\t' + v[1])
EOF
check "control: the fragment lean, unrecorded" bash -c "$(declare -f lean recorded); R=$R; lean /usr/share/orph-watch/fragment.sh && ! recorded orph-watch /usr/share/orph-watch/fragment.sh"

echo "== the package under test installed over it"
# where the originals are: systemd's and orph-watch's .deb in APT's cache, orph-src's offered by a configured source,
# orph-gone's nowhere
cp "$W/debs/orph-src_1.0_all.deb" /srv/orph/
(cd /srv/orph && dpkg-scanpackages . >Packages 2>/dev/null &&
	printf 'Origin: Orph\nLabel: Orph\nSuite: stable\nCodename: orph\nDate: Tue, 03 Nov 2026 00:00:00 UTC\nSHA256:\n %s %s Packages\n' \
		"$(sha256sum <Packages | cut -d' ' -f1)" "$(stat -c %s Packages)" >Release)
echo 'deb [trusted=yes] file:/srv/orph ./' >/etc/apt/sources.list.d/orph.list
apt-get update -qq >/dev/null 2>&1 || bad "apt-get update of the local source"
chmod -R a+rX /srv/orph
# Container APT update hooks may empty the cache: place the test originals after refreshing indexes.
cp "$SYSTEMD_DEB" "$CACHE/systemd_$(dpkg-deb -f "$SYSTEMD_DEB" Version | sed 's/:/%3a/')_amd64.deb"
cp "$W/debs/orph-watch_1.0_all.deb" "$CACHE/"
dpkg -i "$NEW" </dev/null >"$W/new.log" 2>&1 || bad "install $NEW: $(tail -3 "$W/new.log")"
cat "$W/new.log"
NEWV=$(dpkg-deb -f "$NEW" Version)
check "control: dpkg-stereo $NEWV installed" [ "$(dpkg-query -W -f '${Version}' dpkg-stereo)" = "$NEWV" ]

echo "== A. systemd"
left=$(grep -c "	systemd	.*changed since its package installed it" "$R/left/systemd.tsv" 2>/dev/null)
check "A: no systemd file left as changed but the person's and what was so before the loss ($left rows, $pre before)" [ "$left" = $((pre + 1)) ]
check "A: the file the person edited stays theirs, as they made it" bash -c "$(declare -f leftrow); R=$R; leftrow systemd '$EDITED' && cmp -s '$EDITED' '$W/edited.copy'"
leftconf=$(grep -c "	systemd	.*conffile changed by the person" "$R/left/systemd.tsv" 2>/dev/null)
check "A: no lean systemd conffile left as changed by the person ($leftconf of $lostconf, $preconf before)" [ "$leftconf" = "$preconf" ]
after=$(grep -vc '^#' "$R/records/systemd.tsv")
check "A: systemd's records back ($after of $before; the person's file is not one)" [ "$after" = $((before - 1)) ]
nconf=$(awk -F'\t' '$2 == "systemd" && $4 == 1' "$R/conffiles.tsv" | wc -l)
check "A: its conffiles in the index pre-invoke reads ($nconf), each with its pristine copies" bash -c "[ $nconf -gt 0 ] && awk -F'\t' '\$2 == \"systemd\" && \$4 == 1 {print \$5; print \$7}' $R/conffiles.tsv | while read h; do [ -e $R/pristine/\$h.xz ] || exit 1; done"
dpkg-stereo --verify systemd >"$W/verify-a.log" 2>&1; rc=$?
check "A: --verify checks them, clean (exit $rc: $(tail -1 "$W/verify-a.log"))" bash -c "[ $rc = 0 ] && grep -q ' 0 problems' '$W/verify-a.log' && [ \$(grep -vc '^dpkg-stereo:' '$W/verify-a.log') = 0 ]"
dpkg --configure -a </dev/null >"$W/again.log" 2>&1
dpkg-stereo --verify systemd >"$W/verify-a2.log" 2>&1; rc=$?
check "A: a dpkg run after it keeps them (exit $rc, $(grep -vc '^#' "$R/records/systemd.tsv") records)" \
	bash -c "[ $rc = 0 ] && [ \$(grep -vc '^#' $R/records/systemd.tsv) = $after ]"
check "A: the summary said once, in the upgrade" bash -c "[ \$(grep -c 'have theirs back' '$W/new.log') = 1 ] && ! grep -q 'have theirs back' '$W/again.log'"

echo "== B. the fixtures"
check "B: orph-watch's script recorded again" bash -c "$(declare -f lean recorded leftrow); R=$R; lean /usr/bin/orph-watch && recorded orph-watch /usr/bin/orph-watch && ! leftrow orph-watch /usr/bin/orph-watch"
check "B: its conffile recorded again, with its pristine copy" bash -c "$(declare -f recorded leftrow); R=$R; recorded orph-watch /etc/xdg/orph-watchrc && ! leftrow orph-watch /etc/xdg/orph-watchrc && grep -q '^/etc/xdg/orph-watchrc	' $R/conffiles.tsv"
check "B: the helper the person edited stays theirs, as they made it" bash -c "$(declare -f leftrow recorded); R=$R; leftrow orph-watch /usr/share/orph-watch/helper.sh && ! recorded orph-watch /usr/share/orph-watch/helper.sh && cmp -s /usr/share/orph-watch/helper.sh '$W/helper.copy'"
check "B: the projection today's check refuses is back in its package's bytes" bash -c "$(declare -f md5ok recorded); R=$R; md5ok orph-watch /usr/share/orph-watch/fragment.sh && ! recorded orph-watch /usr/share/orph-watch/fragment.sh"
check "B: and its row says why ($(bash -c "$(declare -f leftwhy); R=$R; leftwhy orph-watch /usr/share/orph-watch/fragment.sh"))" bash -c "$(declare -f leftwhy); R=$R; leftwhy orph-watch /usr/share/orph-watch/fragment.sh | grep -q 'not accepted by bash'"
check "B: orph-src's records back from the configured source, inside the dpkg run" bash -c "$(declare -f recorded leftrow); R=$R; recorded orph-src /usr/bin/orph-src && recorded orph-src /etc/xdg/orph-srcrc && ! leftrow orph-src /usr/bin/orph-src"
# an independent count of what became of each row: recorded now, still a row (the person's), or waiting
python3 - "$W/orphans-before.tsv" "$R" >"$W/orphans-after.txt" <<'EOF'
import os, sys
rows = [l.rstrip('\n').split('\t') for l in open(sys.argv[1])]
R = sys.argv[2]
def table(kind, pkg):
    out = {}
    try:
        for line in open(os.path.join(R, kind, pkg + '.tsv'), encoding='utf-8', errors='surrogateescape'):
            v = line.rstrip('\n').split('\t')
            if not line.startswith('#') and len(v) > 1:
                out[v[0]] = v
    except FileNotFoundError:
        pass
    return out
pending = set()
if os.path.exists(os.path.join(R, 'orphaned-lean-v1.pending')):
    pending = {l.split('\t')[0] for l in open(os.path.join(R, 'orphaned-lean-v1.pending')) if not l.startswith('#')}
back = stay = wait = other = 0
for path, pkg in rows:
    rec, left = table('records', pkg).get(path), table('left', pkg).get(path)
    if path in pending:
        wait += 1
    elif rec and not left:
        back += 1
    elif left and left[3].startswith(('changed since its package installed it', 'conffile changed by the person')):
        stay += 1
    else:
        other += 1
print(back, stay, wait, other)
EOF
read back stay wait other <"$W/orphans-after.txt"
check "B: the summary's numbers are what became of the rows ($back back, $stay the person's, $wait waiting, $other else)" \
	grep -q "Records that dpkg-stereo 0.1.28 or older lost: $back lean files have theirs back .*; $stay files stay the person" "$W/new.log"
check "B: control: both edits among those that stay, orph-gone's script and helper waiting, the fragment the one else" \
	bash -c "[ $stay -ge 2 ] && [ $wait = 2 ] && [ $other = 1 ]"
check "B: and the one put back" grep -q '1 of them went back to their package' "$W/new.log"

echo "== C. a package whose .deb is nowhere"
check "C: orph-gone's rows stay" bash -c "$(declare -f leftrow); R=$R; leftrow orph-gone /usr/bin/orph-gone && leftrow orph-gone /usr/share/orph-gone/helper.sh"
check "C: its conffile's record back all the same, from its pristine copy (no .deb needed)" bash -c "$(declare -f recorded leftrow); R=$R; recorded orph-gone /etc/xdg/orph-gonerc && ! leftrow orph-gone /etc/xdg/orph-gonerc"
check "C: its files listed as waiting" grep -q '^/usr/bin/orph-gone	orph-gone	1.0$' "$R/orphaned-lean-v1.pending"
check "C: the upgrade said it, with the version and why" grep -q 'have no record yet, so --restore cannot bring back their originals; the first is orph-gone 1.0' "$W/new.log"
dpkg-stereo --verify orph-gone >"$W/verify-c.log" 2>&1; rc=$?
check "C: --verify names them (exit $rc)" bash -c "[ $rc = 2 ] && grep -q '^UNRECORDED /usr/bin/orph-gone' '$W/verify-c.log'"
dpkg-stereo --problems >"$W/problems-c.log" 2>&1; rc=$?
check "C: the problem is kept (exit $rc), naming the version, why and what to do" bash -c "[ $rc = 1 ] && grep -q 'orph-gone 1.0: 2 lean files have no record yet: no configured source offers this version, and this step does not ask snapshot.debian.org' '$W/problems-c.log' && grep -q 'sudo dpkg-stereo --repair (it also asks snapshot.debian.org)' '$W/problems-c.log'"
dpkg-stereo --status >"$W/status-c.log" 2>&1
check "C: --status counts them" grep -q 'unrecorded: 2 lean files' "$W/status-c.log"
dpkg --configure -a </dev/null >"$W/again-c.log" 2>&1
check "C: a dpkg run that changes nothing does not say it again" sh -c "! grep -q 'no record yet' '$W/again-c.log'"
dpkg-stereo --restore orph-gone >"$W/restore-c.log" 2>&1; rc=$?
cat "$W/restore-c.log"
check "C: --restore of the package says its unrecorded files stay lean, and why (exit $rc)" bash -c "[ $rc = 1 ] && grep -q 'orph-gone 1.0: 2 files stay lean: no configured source offers this version' '$W/restore-c.log' && grep -q '1 files restored, 2 stay lean' '$W/restore-c.log'"
check "C: its recorded conffile restored, its unrecorded files still lean" bash -c "$(declare -f confok lean); confok orph-gone /etc/xdg/orph-gonerc && lean /usr/bin/orph-gone && lean /usr/share/orph-gone/helper.sh"
# snapshot.debian.org's interface, answered locally: the .deb by its SHA-1
sha=$(sha1sum <"$W/debs/orph-gone_1.0_all.deb" | cut -d' ' -f1)
mkdir -p "$W/srv/mr/orph-gone"
printf '{"result": [{"architecture": "all", "hash": "%s"}], "fileinfo": {"%s": [{"archive_name": "debian", "first_seen": "20261001T000000Z", "name": "orph-gone_1.0_all.deb", "path": "/pool/main/o/orph-gone", "size": %s}]}}\n' \
	"$sha" "$sha" "$(stat -c %s "$W/debs/orph-gone_1.0_all.deb")" >"$W/srv/mr/orph-gone/1.0.json"
cp "$W/debs/orph-gone_1.0_all.deb" "$W/srv/file/$sha"
cat >"$W/server.py" <<'EOF'
import http.server, os, sys, urllib.parse
root, port = sys.argv[1], int(sys.argv[2])
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        url = urllib.parse.urlsplit(self.path)
        parts = [urllib.parse.unquote(p) for p in url.path.split('/')]
        name = None
        if len(parts) == 6 and parts[1:3] == ['mr', 'binary'] and parts[5] == 'binfiles' and url.query == 'fileinfo=1':
            name = os.path.join(root, 'mr', parts[3], parts[4] + '.json')
        elif len(parts) == 3 and parts[1] == 'file':
            name = os.path.join(root, 'file', parts[2])
        if name and os.path.isfile(name):
            data = open(name, 'rb').read()
            self.send_response(200)
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        else:
            self.send_error(404, 'No such file')
    def log_message(self, *args):
        pass
http.server.ThreadingHTTPServer(('127.0.0.1', port), Handler).serve_forever()
EOF
python3 "$W/server.py" "$W/srv" $PORT &
SERVER=$!
trap 'kill $SERVER 2>/dev/null' EXIT
for i in $(seq 50); do (exec 3<>/dev/tcp/127.0.0.1/$PORT) 2>/dev/null && break; sleep 0.1; done
DPKG_STEREO_SNAPSHOT=http://127.0.0.1:$PORT dpkg-stereo --repair-consumers >"$W/repair-consumers.log" 2>&1; rc=$?
cat "$W/repair-consumers.log"
check "C: the person's --repair-consumers gives them their records from snapshot (exit $rc)" bash -c "$(declare -f recorded leftrow); R=$R; [ $rc = 0 ] && recorded orph-gone /usr/bin/orph-gone && recorded orph-gone /usr/share/orph-gone/helper.sh && ! leftrow orph-gone /usr/bin/orph-gone"
check "C: the fetched .deb kept in APT's cache" test -f "$CACHE/orph-gone_1.0_all.deb"
check "C: the orphans problem cleared, the migration done" bash -c "! grep -q '^\[.*\] orphans:' <(dpkg-stereo --problems 2>&1) && test -e $R/orphaned-lean-v1 && test ! -e $R/orphaned-lean-v1.pending"
DPKG_STEREO_SNAPSHOT=http://127.0.0.1:$PORT dpkg-stereo --repair >"$W/repair.log" 2>&1; rc=$?
cat "$W/repair.log"
check "C: --repair completes the restore kept as a problem (exit $rc): every file of orph-gone in its package's bytes" bash -c "$(declare -f md5ok confok); [ $rc = 0 ] && md5ok orph-gone /usr/bin/orph-gone && md5ok orph-gone /usr/share/orph-gone/helper.sh && confok orph-gone /etc/xdg/orph-gonerc"
check "C: no problem left" sh -c "dpkg-stereo --problems >/dev/null 2>&1"
dpkg-stereo --verify orph-gone orph-watch orph-src >"$W/verify-c2.log" 2>&1; rc=$?
check "C: --verify clean (exit $rc: $(tail -1 "$W/verify-c2.log"))" bash -c "[ $rc = 0 ] && ! grep -q UNRECORDED '$W/verify-c2.log'"

echo "== restore brings back every original"
dpkg-stereo --restore systemd orph-watch orph-src orph-gone >"$W/restore.log" 2>&1; rc=$?
check "restore: exit $rc ($(grep -E 'files restored' "$W/restore.log" | tail -1))" [ $rc = 0 ]
changed=$(dpkg --verify systemd 2>/dev/null | awk '$1 ~ /^..5/ {print $NF}' | grep -vxF "$EDITED" | sort | comm -23 - "$W/systemd-changed-before.txt")
check "restore: every systemd file in its package's bytes but the person's and what the image changed (${changed:-none other})" [ -z "$changed" ]
check "restore: the person's file as they made it" cmp -s "$EDITED" "$W/edited.copy"
check "restore: orph-watch's script and conffile in their package's bytes" bash -c "$(declare -f md5ok confok); md5ok orph-watch /usr/bin/orph-watch && confok orph-watch /etc/xdg/orph-watchrc"
check "restore: orph-gone's and orph-src's too" bash -c "$(declare -f md5ok confok); md5ok orph-gone /usr/bin/orph-gone && confok orph-gone /etc/xdg/orph-gonerc && md5ok orph-src /usr/bin/orph-src"

echo "== D. removal, then the package installed again"
dpkg -i "$W/debs/orph-rm_1.0_all.deb" "$W/debs/orph-rm2_1.0_all.deb" </dev/null >"$W/d1.log" 2>&1 || bad "D: install: $(tail -3 "$W/d1.log")"
check "D: control: both conffiles lean and recorded" bash -c "$(declare -f lean recorded); R=$R; lean /etc/xdg/orph-rmrc && recorded orph-rm /etc/xdg/orph-rmrc && lean /etc/xdg/orph-rm2rc"
# the person changes orph-rm2's conffile
sed -i 's/^Mode=fast$/Mode=mine/' /etc/xdg/orph-rm2rc
cp /etc/xdg/orph-rm2rc "$W/rm2.copy"
dpkg -r orph-rm orph-rm2 </dev/null >"$W/d2.log" 2>&1 || bad "D: remove: $(tail -3 "$W/d2.log")"
check "D: control: removed, its conffiles kept" bash -c "[ \"\$(dpkg-query -W -f '\${Status}' orph-rm)\" = 'deinstall ok config-files' ] && test -f /etc/xdg/orph-rmrc"
check "D: the lean conffile back in its package's bytes" confok orph-rm /etc/xdg/orph-rmrc
check "D: the person's conffile as they made it" cmp -s /etc/xdg/orph-rm2rc "$W/rm2.copy"
dpkg -i "$W/debs/orph-rm_1.0_all.deb" "$W/debs/orph-rm2_1.0_all.deb" </dev/null >"$W/d3.log" 2>&1; rc=$?
check "D: installing them again is quiet (exit $rc)" bash -c "[ $rc = 0 ] && ! grep -qi 'conffile\|modified' '$W/d3.log'"
check "D: the conffile lean and recorded again" bash -c "$(declare -f lean recorded leftrow); R=$R; lean /etc/xdg/orph-rmrc && recorded orph-rm /etc/xdg/orph-rmrc && ! leftrow orph-rm /etc/xdg/orph-rmrc"
dpkg-stereo --verify orph-rm orph-rm2 >"$W/verify-d.log" 2>&1
check "D: --verify: orph-rm clean, only the person's file named as theirs" bash -c "! grep -q 'orph-rmrc' '$W/verify-d.log' && grep -q '^EDITED    /etc/xdg/orph-rm2rc' '$W/verify-d.log'"
check "D: the person's conffile still as they made it" cmp -s /etc/xdg/orph-rm2rc "$W/rm2.copy"
# a record whose lean hash is wrong: the person edits orph-rm3's lean conffile, and its record's sha_lean and bytes_lean
# are forged to the edited bytes (the pristine original and dpkg's config-files hash stay right, so every hash passes)
dpkg -i "$W/debs/orph-rm3_1.0_all.deb" </dev/null >"$W/d5.log" 2>&1 || bad "D: install orph-rm3: $(tail -3 "$W/d5.log")"
check "D: control: orph-rm3's conffile lean and recorded" bash -c "$(declare -f lean recorded); R=$R; lean /etc/xdg/orph-rm3rc && recorded orph-rm3 /etc/xdg/orph-rm3rc"
sed -i 's/^Mode=fast$/Mode=mine/' /etc/xdg/orph-rm3rc
cp /etc/xdg/orph-rm3rc "$W/rm3.copy"
python3 - "$R" <<'EOF'
import hashlib, sys
R, p = sys.argv[1], '/etc/xdg/orph-rm3rc'
data = open(p, 'rb').read()
for t in (R + '/records/orph-rm3.tsv', R + '/conffiles.tsv'):
    lines = open(t, encoding='utf-8').read().splitlines(True)
    cols = lines[0].lstrip('#').rstrip('\n').split('\t')
    out = []
    for line in lines:
        v = line.rstrip('\n').split('\t')
        if v[0] == p:
            v[cols.index('sha_lean')] = hashlib.sha256(data).hexdigest()
            v[cols.index('bytes_lean')] = str(len(data))
            line = '\t'.join(v) + '\n'
        out.append(line)
    open(t, 'w', encoding='utf-8').writelines(out)
EOF
check "D: control: the forged record's lean hash is the person's file" bash -c "grep '^/etc/xdg/orph-rm3rc	' $R/records/orph-rm3.tsv | cut -f7 | grep -qx \$(sha256sum </etc/xdg/orph-rm3rc | cut -d' ' -f1)"
dpkg -r orph-rm3 </dev/null >"$W/d6.log" 2>&1 || bad "D: remove orph-rm3: $(tail -3 "$W/d6.log")"
cat "$W/d6.log"
check "D: a record whose lean hash is wrong never overwrites the person's edit" cmp -s /etc/xdg/orph-rm3rc "$W/rm3.copy"
check "D: and that is said, naming the file and the package" grep -q "/etc/xdg/orph-rm3rc, a setting of the removed package orph-rm3, stays as it is: today's renderer does not make it from the package's own file" "$W/d6.log"
dpkg -P orph-rm orph-rm2 orph-rm3 </dev/null >"$W/d4.log" 2>&1 || bad "D: purge: $(tail -3 "$W/d4.log")"
check "D: a purge removes them" bash -c "test ! -e /etc/xdg/orph-rmrc && test ! -e /etc/xdg/orph-rm2rc && test ! -e /etc/xdg/orph-rm3rc"

dpkg --audit >"$W/audit.log" 2>&1
check "dpkg --audit empty" test ! -s "$W/audit.log"
check "no hook errors" test ! -s "$R/error.log"
echo "SUMMARY: $passed passed, $failed failed"
exit $fail
