#!/bin/bash
# Sparky Stereo OS: fetches the Craft suite's pinned sources and vendors every crate, for build.sh.
# Created by Daniel Ramos (Capitain Jack) 2026/11/13
# Copyright 2026 under the GNU GPL3 License
# Usage: fetch.sh OUT   (FETCH_IMAGE: an image with the edition's cargo and python3; the only step with the network)
#   OUT/apps/APP: `git archive` of each app at the revision suite.json pins, from the edition's forks;
#   OUT/fonts/craft-fonts-REV and OUT/i18n/craft-i18n-REV: the font and catalogue revisions each app was gated with;
#   OUT/authors/APP.txt: every author name the app's commits carry (no addresses);
#   OUT/vendor: every crate of every app's lock, one folder per source (the registry, each git revision);
#   OUT/SOURCES.sha256: one digest per top folder, to compare two fetches.
# Last update 2026/11/13
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(mkdir -p "$1" && cd "$1" && pwd)
: "${FETCH_IMAGE:?an image with the cargo of the edition}" "${SPARKY_CONTAINER_PREFIX:=craft-suite}"
[ -z "$(ls -A "$OUT")" ] || { echo "$OUT is not empty" >&2; exit 1; }
j() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1]));
for k in sys.argv[2:]: d=d[k]
print("" if d is None else d)' "$HERE/suite.json" "$@"; }
mkdir -p "$OUT/git" "$OUT/apps" "$OUT/fonts" "$OUT/i18n" "$OUT/authors" "$OUT/work"
fetch() {    # fetch NAME URL REV DEST: the tree of one revision, checked against the revision asked for
	local name=$1 url=$2 rev=$3 dest=$4
	[ -d "$OUT/git/$name" ] || git clone -q --filter=blob:none --no-checkout "$url" "$OUT/git/$name"
	git -C "$OUT/git/$name" fetch -q origin "$rev"
	[ "$(git -C "$OUT/git/$name" rev-parse "$rev^{commit}")" = "$rev" ] || { echo "$name: $rev is not a commit of $url" >&2; exit 1; }
	mkdir -p "$dest" && git -C "$OUT/git/$name" archive "$rev" | tar -x -C "$dest"
}
fork=$(j fork)
for a in $(python3 -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1]))["apps"]))' "$HERE/suite.json"); do
	rev=$(j apps "$a" rev)
	fetch "$a" "$fork/$a.git" "$rev" "$OUT/apps/$a"
	git -C "$OUT/git/$a" log --format=%an "$rev" | LC_ALL=C sort -u >"$OUT/authors/$a.txt"
	f=$(j apps "$a" fonts); [ -d "$OUT/fonts/craft-fonts-${f:0:8}" ] || fetch craft-fonts "$(j fonts_repository).git" "$f" "$OUT/fonts/craft-fonts-${f:0:8}"
	i=$(j apps "$a" i18n); [ -z "$i" ] || [ -d "$OUT/i18n/craft-i18n-${i:0:8}" ] || fetch craft-i18n "$(j i18n_repository).git" "$i" "$OUT/i18n/craft-i18n-${i:0:8}"
done
docker run --rm --name "$SPARKY_CONTAINER_PREFIX-fetch" --ulimit core=0 --cpus 4 --user "$(id -u):$(id -g)" --platform linux/amd64 \
	--mount "type=bind,src=$OUT,dst=/out" --mount "type=bind,src=$HERE,dst=/tools,readonly" \
	-e HOME=/out/work/home -e CARGO_HOME=/out/work/cargo-home -e PATH=/usr/bin:/bin "$FETCH_IMAGE" bash -c '
set -euo pipefail
case "$(dpkg-query -W -f "\${Version}" cargo)" in *+stereo3d*) ;; *) echo "cargo is not the edition build" >&2; exit 1 ;; esac
fork=$(python3 -c "import json;print(json.load(open(\"/tools/suite.json\"))[\"fork\"])")
args=()
for a in $(ls /out/apps); do
	mkdir -p /out/work/$a && cp -a /out/apps/$a /out/work/$a/src && cd /out/work/$a/src
	pins=$(python3 -c "import json,sys;print(\" \".join(f\"{k}={v}\" for k,v in json.load(open(\"/tools/suite.json\"))[\"apps\"][sys.argv[1]][\"libs\"].items()))" $a)
	python3 /tools/suite-source.py rewrite . $fork $pins >/dev/null
	python3 /tools/suite-source.py lock . $fork $pins
	cp Cargo.lock ../Cargo.lock.rewritten
	cargo vendor --locked --versioned-dirs ../vendor >/dev/null 2>../vendor.err || { tail -20 ../vendor.err >&2; exit 1; }
	cmp Cargo.lock ../Cargo.lock.rewritten || { echo "$a: cargo changed the rewritten lock" >&2; exit 1; }
	args+=("$a=/out/work/$a/vendor=/out/work/$a/Cargo.lock.rewritten")
done
python3 /tools/suite-source.py merge /out/vendor "${args[@]}"'
rm -rf "$OUT/work" "$OUT/git"
(cd "$OUT" && for d in apps fonts i18n authors vendor; do
	echo "$(find "$d" \( -type f -o -type l \) -print0 | LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)  $d"
done >SOURCES.sha256)
cat "$OUT/SOURCES.sha256"
