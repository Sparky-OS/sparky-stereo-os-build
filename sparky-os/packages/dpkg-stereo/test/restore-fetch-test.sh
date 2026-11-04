#!/bin/bash
# dpkg-stereo's way back for originals whose package version neither APT's cache nor its sources hold (ORDER 365),
# in a throwaway Debian container (root) with no internet: a local HTTP server answers as snapshot.debian.org's
# machine-readable interface does (/mr/binary/NAME/VERSION/binfiles?fileinfo=1 names each architecture's .deb by
# its SHA-1, /file/SHA1 is the file), from fixtures this test makes, and DPKG_STEREO_SNAPSHOT points dpkg-stereo at
# it. Restore must fetch the exact version and put every original back; a file with another SHA-1, a .deb of another
# version and a .deb with another file must each be refused and said; a version snapshot does not hold, a package of
# another archive and an unreachable server must each be said with the one thing that brings the files back, never
# apt-get's reinstall of a version no source offers; --deb must take a person's file only when it is exactly the
# installed version. Each case has its control.
# Usage: restore-fetch-test.sh DPKG-STEREO-PROGRAM LIB-DIR LANG-DIR WORKDIR
#   (the program to test, the folder holding its lean package, its language files' folder, a scratch folder; the
#   program's journal catalogs are read from ../lib/systemd/catalog beside it, so the problems engine knows them)
set -u
BIN=$1 LIB=$2 LANGS=$3 W=$4
export DEBIAN_FRONTEND=noninteractive DPKG_STEREO_LIB=$LIB DPKG_STEREO_LANG_DIR=$LANGS LANG=C.UTF-8
export SPARKY_STEREO_PROBLEMS_CATALOG="$(cd "$(dirname "$BIN")/../lib/systemd/catalog" 2>/dev/null && pwd):/usr/lib/systemd/catalog"
unset DPKG_STEREO_DISABLE DPKG_STEREO_NO_PROJECT
fail=0 passed=0 failed=0
ok() { echo "PASS $*"; passed=$((passed + 1)); }
bad() { echo "FAIL $*"; fail=1; failed=$((failed + 1)); }
check() { local name=$1; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
ds() { python3 "$BIN" "$@"; }
command -v dpkg-deb >/dev/null && command -v dpkg-scanpackages >/dev/null && [ -x /usr/lib/apt/apt-helper ] ||
	{ echo "needs dpkg-dev and apt's apt-helper"; exit 2; }
command -v sparky-stereo-problems >/dev/null || { echo "needs the problems engine (sparky-stereo-problems)"; exit 2; }
CACHE=/var/cache/apt/archives
PORT=18365
export DPKG_STEREO_SNAPSHOT=http://127.0.0.1:$PORT
rm -rf "$W" /var/lib/dpkg-stereo /var/lib/sparky-stereo-problems/dpkg-stereo_*
mkdir -p "$W/debs" "$W/wrong" "$W/srv/mr" "$W/srv/file" "$CACHE"
rm -f /etc/apt/sources.list /etc/apt/sources.list.d/* "$CACHE"/*.deb

mk() {     # mk NAME VERSION ARCH OUT-DIR [VARIANT]: a package with a script and a Python module full of commentary
	local d=$W/build/$1-$3-${5:-real} v=${2#*:}
	rm -rf "$d"
	mkdir -p "$d/DEBIAN" "$d/usr/bin" "$d/usr/lib/python3/dist-packages"
	cat >"$d/usr/bin/$1" <<EOF
#!/bin/sh
# $1: prints its version. This comment and the four after it are commentary the shell reads and skips.
# The installed program does not need any of these lines; they explain it to a person reading the file.
# A third line of commentary, long enough that the projection is worth its pointer line.
# A fourth line of commentary, long enough that the projection is worth its pointer line.
echo "$1 $2"
EOF
	chmod 755 "$d/usr/bin/$1"
	cat >"$d/usr/lib/python3/dist-packages/${1//-/_}.py" <<EOF
# ${1//-/_}: a module whose commentary the interpreter skips at every import, a few lines of it.
# The installed program does not need any of these lines; they explain it to a person reading the file.
# A third line of commentary, long enough that the projection is worth its pointer line.${5:+ (${5})}
VALUE = "$2"
EOF
	printf 'Package: %s\nVersion: %s\nArchitecture: %s\nMaintainer: %s\nDescription: d\n' "$1" "$2" "$3" "${MAINT:-t <t@example.org>}" \
		>"$d/DEBIAN/control"
	dpkg-deb --root-owner-group -b "$d" "$4/$1_${v}_$3.deb" >/dev/null
}
# serve NAME VERSION ARCH FILE: the interface names FILE (by its SHA-1, or by SHA if given) as NAME VERSION ARCH
serve() {
	local sha=${5:-$(sha1sum <"$4" | cut -d' ' -f1)}
	mkdir -p "$W/srv/mr/$1"
	printf '{"_comment": "foo", "binary": "%s", "binary_version": "%s", "result": [{"architecture": "%s", "hash": "%s"}], "fileinfo": {"%s": [{"archive_name": "debian", "first_seen": "20261001T000000Z", "name": "%s", "path": "/pool/main/l/%s", "size": %s}]}}\n' \
		"$1" "$2" "$3" "$sha" "$sha" "$(basename "$4")" "$1" "$(stat -c %s "$4")" >"$W/srv/mr/$1/$2.json"
	cp "$4" "$W/srv/file/$sha"
}
cat >"$W/server.py" <<'EOF'
import http.server, os, sys, urllib.parse
root, port, log = sys.argv[1], int(sys.argv[2]), sys.argv[3]
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        url = urllib.parse.urlsplit(self.path)
        with open(log, 'a') as f:
            f.write(url.path + ('?' + url.query if url.query else '') + '\n')
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
python3 "$W/server.py" "$W/srv" $PORT "$W/requests.log" &
SERVER=$!
trap 'kill $SERVER 2>/dev/null' EXIT
for i in $(seq 50); do (exec 3<>/dev/tcp/127.0.0.1/$PORT) 2>/dev/null && break; sleep 0.1; done

# the packages: each installed from its real .deb, which is then nowhere but where a case puts it
for p in lean-snap lean-gone lean-net lean-net2 lean-sha lean-ver lean-file lean-vendor lean-deb; do mk $p 1.0 all "$W/debs"; done
MAINT='Media Packager <m@example.org>' mk lean-dmo 1.0 all "$W/debs"
mk lean-epoch 2:1.0-1 all "$W/debs"
mk lean-arch 1.0 amd64 "$W/debs"
# This suite projects its named fixtures explicitly below; do not project the base image here.
DPKG_STEREO_DISABLE=1 dpkg -i "$W"/debs/*.deb >/dev/null 2>&1 || bad "install of the test packages"
serve lean-snap 1.0 all "$W/debs/lean-snap_1.0_all.deb"
serve lean-epoch 2:1.0-1 all "$W/debs/lean-epoch_1.0-1_all.deb"
serve lean-arch 1.0 amd64 "$W/debs/lean-arch_1.0_amd64.deb"
serve lean-net 1.0 all "$W/debs/lean-net_1.0_all.deb"
serve lean-net2 1.0 all "$W/debs/lean-net2_1.0_all.deb"
serve lean-deb 1.0 all "$W/debs/lean-deb_1.0_all.deb"
serve lean-dmo 1.0 all "$W/debs/lean-dmo_1.0_all.deb"
# the refusals: another file under the SHA-1 the interface gives, another version, another file inside
mk lean-sha 1.0 all "$W/wrong" other
serve lean-sha 1.0 all "$W/wrong/lean-sha_1.0_all.deb" "$(sha1sum <"$W/debs/lean-sha_1.0_all.deb" | cut -d' ' -f1)"
mk lean-ver 1.1 all "$W/wrong"
serve lean-ver 1.0 all "$W/wrong/lean-ver_1.1_all.deb"
mk lean-file 1.0 all "$W/wrong" other
serve lean-file 1.0 all "$W/wrong/lean-file_1.0_all.deb"
# another archive's package: a source whose Release says Origin: Example Vendor offers lean-vendor 2.0 only, and
# lean-dmo 3.0 by lean-dmo 1.0's Maintainer; a source whose Release says Origin: Debian offers lean-deb 2.0 and
# lean-dmo 2.0 by another Maintainer
flat() {   # flat DIR ORIGIN: a flat source of the .debs in DIR whose Release names ORIGIN
	(cd "$1" && dpkg-scanpackages --multiversion . >Packages 2>/dev/null &&
		printf 'Origin: %s\nLabel: %s\nSuite: stable\nCodename: example\nDate: Tue, 03 Nov 2026 00:00:00 UTC\nSHA256:\n %s %s Packages\n' \
			"$2" "$2" "$(sha256sum <Packages | cut -d' ' -f1)" "$(stat -c %s Packages)" >Release)
	echo "deb [trusted=yes] file:$1 ./" >"/etc/apt/sources.list.d/$(basename "$1").list"
}
mkdir -p /srv/vendor /srv/debian
mk lean-vendor 2.0 all /srv/vendor
MAINT='Media Packager <m@example.org>' mk lean-dmo 3.0 all /srv/vendor
mk lean-deb 2.0 all /srv/debian
MAINT='Debian Team <d@example.org>' mk lean-dmo 2.0 all /srv/debian
flat /srv/vendor 'Example Vendor'
flat /srv/debian Debian
apt-get update -qq >/dev/null 2>&1 || bad "apt-get update of the local sources"
# Refresh hooks in container images may empty APT’s cache; seed the control afterwards.
# lean-arch's twin of the other architecture, with other files, in APT's cache: never read for amd64
mk lean-arch 1.0 i386 "$CACHE" other
DECOY=$(sha256sum <"$CACHE/lean-arch_1.0_i386.deb")
mk lean-vendor 1.0 all "$W/wrong" other
mkdir -p "$W/other-version" && cp /srv/vendor/lean-vendor_2.0_all.deb "$W/other-version/"

ds --project lean-snap lean-epoch lean-arch lean-gone lean-net lean-net2 lean-sha lean-ver lean-file lean-vendor lean-deb lean-dmo \
	>"$W/project.log" 2>&1 || bad "projection: $(tail -3 "$W/project.log")"
lean() { ! grep -q 'commentary' "$1"; }
orig() { mkdir -p "$W/x/$1" && dpkg-deb -x "$W/debs/$1_${2:-1.0}_${3:-all}.deb" "$W/x/$1" && cmp -s "/usr/bin/$1" "$W/x/$1/usr/bin/$1" &&
	cmp -s "/usr/lib/python3/dist-packages/${1//-/_}.py" "$W/x/$1/usr/lib/python3/dist-packages/${1//-/_}.py"; }
both_lean() { lean "/usr/bin/$1" && lean "/usr/lib/python3/dist-packages/${1//-/_}.py"; }
recorded() { [ -s "/var/lib/dpkg-stereo/records/$1.tsv" ]; }
no_leftovers() { ! ls "$CACHE/partial" | grep -q '^dpkg-stereo\.'; }
said() { grep -q -- "$1" "$W/out"; }
kept_item() { python3 "$BIN" --problems >"$W/problems" 2>&1; grep -q -- "$1" "$W/problems"; }
for p in lean-snap lean-epoch lean-arch lean-gone lean-net lean-sha lean-ver lean-file lean-vendor; do
	both_lean $p && recorded $p || bad "control: $p projected and recorded"
done
check "control-nothing-in-the-cache" sh -c "! ls $CACHE | grep -E '^lean-(snap|epoch|gone|net|sha|ver|file|vendor)_'"
check "control-apt-offers-none-of-them" sh -c "[ -z \"\$(apt-cache madison lean-snap lean-epoch lean-arch lean-gone lean-net lean-sha lean-ver lean-file 2>/dev/null)\" ]"

echo "== the exact versions fetched: every original back, each .deb kept in APT's cache by APT's own name"
ds --restore lean-snap lean-epoch lean-arch >"$W/out" 2>&1; rc=$?
check "fetched-exit-0" [ $rc = 0 ]
check "fetched-originals-back" bash -c "$(declare -f orig); W='$W'; orig lean-snap && orig lean-epoch 1.0-1 && orig lean-arch 1.0 amd64"
check "fetched-records-dropped" sh -c "! [ -e /var/lib/dpkg-stereo/records/lean-snap.tsv ] && ! [ -e /var/lib/dpkg-stereo/records/lean-epoch.tsv ] && ! [ -e /var/lib/dpkg-stereo/records/lean-arch.tsv ]"
check "fetched-in-apt-cache-by-apt-name" sh -c "cmp -s $CACHE/lean-snap_1.0_all.deb '$W/debs/lean-snap_1.0_all.deb' && cmp -s '$CACHE/lean-epoch_2%3a1.0-1_all.deb' '$W/debs/lean-epoch_1.0-1_all.deb' && cmp -s $CACHE/lean-arch_1.0_amd64.deb '$W/debs/lean-arch_1.0_amd64.deb'"
check "fetched-epoch-asked-encoded" grep -qx '/mr/binary/lean-epoch/2%3A1.0-1/binfiles?fileinfo=1' "$W/requests.log"
check "fetched-other-arch-twin-untouched" sh -c "[ \"\$(sha256sum <$CACHE/lean-arch_1.0_i386.deb)\" = '$DECOY' ]"
check "fetched-said" said 'fetched from snapshot.debian.org'
check "fetched-no-leftovers-in-partial" no_leftovers
check "fetched-no-problem-kept" sh -c "! [ -e /var/lib/sparky-stereo-problems/dpkg-stereo_restore.json ]"
ds --verify lean-snap >"$W/verify" 2>&1
check "fetched-verify-has-nothing-of-it" sh -c "! grep -qE '^(MISSING|RESTORED|STALE|MISMATCH|CHANGED) .*lean-snap' '$W/verify'"

echo "== a file whose SHA-1 is not the one the interface gives: refused and said"
ds --restore lean-sha >"$W/out" 2>&1; rc=$?
check "sha1-exit-1" [ $rc = 1 ]
check "sha1-files-stay-lean" both_lean lean-sha
check "sha1-said-refused" said "lean-sha 1.0: 2 files stay lean: the .deb fetched from snapshot.debian.org was not this version's, so it was refused"
check "sha1-said-which-sha1" said "has SHA-1 $(sha1sum <"$W/wrong/lean-sha_1.0_all.deb" | cut -d' ' -f1), not"
check "sha1-said-what-to-do" said 'Run it again: sudo dpkg-stereo --repair'
check "sha1-not-in-apt-cache" sh -c "! [ -e $CACHE/lean-sha_1.0_all.deb ]"
check "sha1-no-leftovers-in-partial" no_leftovers
check "sha1-kept" kept_item 'lean-sha 1.0: 2 files stay lean'

echo "== a .deb of another version: refused and said"
ds --restore lean-ver >"$W/out" 2>&1; rc=$?
check "version-exit-1" [ $rc = 1 ]
check "version-files-stay-lean" both_lean lean-ver
check "version-said" said "is lean-ver 1.1 all"
check "version-said-refused" said "lean-ver 1.0: 2 files stay lean: the .deb fetched from snapshot.debian.org was not this version's"
check "version-not-in-apt-cache" sh -c "! [ -e $CACHE/lean-ver_1.0_all.deb ]"
check "version-no-leftovers-in-partial" no_leftovers

echo "== a .deb of this version with another file inside: that file refused and said, the .deb not kept"
ds --restore lean-file >"$W/out" 2>&1; rc=$?
check "file-exit-1" [ $rc = 1 ]
check "file-other-file-stays-lean" lean /usr/lib/python3/dist-packages/lean_file.py
check "file-said" said "lean-file 1.0: 1 files stay lean: its .deb holds other bytes than the files that were installed (/usr/lib/python3/dist-packages/lean_file.py: its .deb from snapshot.debian.org holds other bytes"
check "file-said-deb-way" said 'sudo dpkg-stereo --restore --deb /path/to/lean-file_1.0_all.deb'
check "file-not-in-apt-cache" sh -c "! [ -e $CACHE/lean-file_1.0_all.deb ]"
check "file-no-leftovers-in-partial" no_leftovers

echo "== a version snapshot does not hold (404): said, with the --deb way, never apt-get's reinstall"
ds --restore lean-gone >"$W/out" 2>&1; rc=$?
check "404-exit-1" [ $rc = 1 ]
check "404-files-stay-lean" both_lean lean-gone
check "404-said-why" said "lean-gone 1.0: 2 files stay lean: no configured source offers this version, and snapshot.debian.org, which keeps every version Debian has published, does not hold it ($DPKG_STEREO_SNAPSHOT/mr/binary/lean-gone/1.0/binfiles"
check "404-said-404" said '404'
check "404-said-deb-way" said 'Get lean-gone_1.0_all.deb, the .deb of exactly this version, and run: sudo dpkg-stereo --restore --deb /path/to/lean-gone_1.0_all.deb'
check "404-never-reinstall" sh -c "! grep -q 'install --reinstall' '$W/out'"

echo "== a package of another archive: said with its archive and the --deb way, snapshot not asked"
ds --restore lean-vendor >"$W/out" 2>&1; rc=$?
check "vendor-exit-1" [ $rc = 1 ]
check "vendor-files-stay-lean" both_lean lean-vendor
check "vendor-said-why" said "lean-vendor 1.0: 2 files stay lean: it comes from an archive other than Debian's, and no configured source offers this version any more (Example Vendor"
check "vendor-said-deb-way" said 'sudo dpkg-stereo --restore --deb /path/to/lean-vendor_1.0_all.deb'
check "vendor-snapshot-not-asked" sh -c "! grep -q lean-vendor '$W/requests.log'"
check "vendor-never-reinstall" sh -c "! grep -q 'install --reinstall' '$W/out'"

echo "== APT's data decide: an older version of the package from Debian's archive asks snapshot; the installed version's Maintainer picks another archive"
ds --restore lean-deb lean-dmo >"$W/out" 2>&1; rc=$?
check "origin-exit-1" [ $rc = 1 ]
check "origin-debian-fetched" bash -c "$(declare -f orig); W='$W'; orig lean-deb"
check "origin-debian-asked" grep -qx '/mr/binary/lean-deb/1.0/binfiles?fileinfo=1' "$W/requests.log"
check "origin-maintainer-picks-the-other-archive" said "lean-dmo 1.0: 2 files stay lean: it comes from an archive other than Debian's, and no configured source offers this version any more (Example Vendor;"
check "origin-maintainer-snapshot-not-asked" sh -c "! grep -q lean-dmo '$W/requests.log'"

echo "== the kept problem: every package version that stays lean, in English and in the person's language"
python3 "$BIN" --problems >"$W/problems" 2>&1; rc=$?
check "kept-problems-exit-1" [ $rc = 1 ]
for p in lean-sha lean-ver lean-file lean-gone lean-vendor; do
	check "kept-names-$p" grep -q "  $p 1.0: .* files stay lean" "$W/problems"
done
check "kept-summary" sh -c "sparky-stereo-problems list --json | grep -q 'package versions stay lean; the first is'"
LANG=pt_BR.UTF-8 python3 "$BIN" --problems >"$W/problems-pt" 2>&1
check "kept-pt-br" grep -q 'lean-gone 1.0: 2 arquivos ficam na forma lean: nenhuma fonte configurada oferece esta versão' "$W/problems-pt"
check "kept-pt-br-english-beside" grep -q '(en) lean-gone 1.0: 2 files stay lean' "$W/problems-pt"

echo "== --deb: the person's .deb of exactly the installed version"
ds --restore --deb "$W/debs/lean-gone_1.0_all.deb" >"$W/out" 2>&1; rc=$?
check "deb-right-exit-0" [ $rc = 0 ]
check "deb-right-originals-back" bash -c "$(declare -f orig); W='$W'; orig lean-gone"
check "deb-right-said" said "2 files of lean-gone 1.0 restored from $W/debs/lean-gone_1.0_all.deb"
check "deb-right-snapshot-not-asked-again" test "$(grep -c '/mr/binary/lean-gone/' "$W/requests.log")" = 1
python3 "$BIN" --problems >"$W/problems" 2>&1
check "deb-right-item-cleared" sh -c "grep -q 'lean-vendor 1.0' '$W/problems' && ! grep -q 'lean-gone 1.0' '$W/problems'"
ds --restore --deb "$W/wrong/lean-vendor_1.0_all.deb" >"$W/out" 2>&1; rc=$?
check "deb-wrong-file-exit-1" [ $rc = 1 ]
check "deb-wrong-file-nothing-taken" both_lean lean-vendor
check "deb-wrong-file-said" said "is lean-vendor 1.0 all, but 1 of its files are not the originals that were installed (the first: /usr/lib/python3/dist-packages/lean_vendor.py): nothing was taken from it"
ds --restore --deb "$W/other-version/lean-vendor_2.0_all.deb" >"$W/out" 2>&1; rc=$?
check "deb-other-version-exit-1" [ $rc = 1 ]
check "deb-other-version-nothing-taken" both_lean lean-vendor
check "deb-other-version-said" said "is lean-vendor 2.0 all, and no lean files of exactly that version are recorded (lean files are recorded for lean-vendor 1.0)"
ds --restore --deb "$W/server.py" >"$W/out" 2>&1; rc=$?
check "deb-not-a-deb-exit-1" sh -c "[ $rc = 1 ] && grep -q 'cannot be read as a .deb' '$W/out'"

echo "== snapshot.debian.org unreachable: said once, with what to do when the network works; then repaired"
DPKG_STEREO_SNAPSHOT=http://127.0.0.1:9 ds --restore lean-net lean-net2 >"$W/out" 2>&1; rc=$?
check "net-exit-1" [ $rc = 1 ]
check "net-files-stay-lean" bash -c "$(declare -f lean both_lean); both_lean lean-net && both_lean lean-net2"
check "net-said-why" said 'lean-net 1.0: 2 files stay lean: snapshot.debian.org could not be reached (http://127.0.0.1:9/mr/binary/lean-net/1.0/binfiles?fileinfo=1: '
check "net-said-what-to-do" said 'When the network works, run: sudo dpkg-stereo --repair'
check "net-asked-once" said 'snapshot.debian.org was not asked again after:'
check "net-kept" kept_item 'lean-net 1.0: 2 files stay lean: snapshot.debian.org could not be reached'
ds --repair >"$W/out" 2>&1; rc=$?
check "net-repair-originals-back" bash -c "$(declare -f orig); W='$W'; orig lean-net && orig lean-net2"
python3 "$BIN" --problems >"$W/problems" 2>&1
check "net-repair-items-cleared" sh -c "! grep -q 'lean-net' '$W/problems'"
check "net-repair-others-still-kept" sh -c "[ $rc = 1 ] && grep -q 'lean-sha 1.0' '$W/problems'"
check "net-repair-no-leftovers-in-partial" no_leftovers

echo "SUMMARY: $passed passed, $failed failed"
exit $fail
