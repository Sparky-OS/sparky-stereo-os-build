#!/bin/bash
# Sparky Stereo OS: stages the Craft suite's packages. Each app is staged by its own upstream packaging script
# (desktop file, icons, MIME types, AppStream data, documents and font licences as upstream ships them); the programs
# then move behind a small launcher that names the version choices file, and the libraries go in under their names.
# Usage: suite-stage.sh SOURCE WORKSPACE LIBPKG APP...
set -euo pipefail
src=$(cd "$1" && pwd); ws=$(cd "$2" && pwd); libpkg=$3; shift 3
json=$src/debian/suite.json
libdir=usr/lib/x86_64-linux-gnu
rel=$ws/built
: "${SOURCE_DATE_EPOCH:?}"
date=$(date -u -d "@$SOURCE_DATE_EPOCH" +%Y-%m-%d)
field() { python3 -c 'import json,sys; v=json.load(open(sys.argv[1]))["apps"][sys.argv[2]][sys.argv[3]]; print("" if v is None else (" ".join(v) if isinstance(v, list) else v))' "$json" "$1" "$2"; }
# the libraries under the names the programs ask for, so upstream's smoke test (PROGRAM --version) can load them
named=$src/debian/stage/lib; rm -rf "$src/debian/stage"; mkdir -p "$named"
install -m644 "$rel/libcraft_suite_shared.so" "$named/$(cat "$ws/shared/soname.txt")"
install -D -m644 "$named/$(cat "$ws/shared/soname.txt")" "$src/debian/$libpkg/$libdir/$(cat "$ws/shared/soname.txt")"
for a in "$@"; do
	so=$(cat "$ws/$a-shared/soname.txt")
	install -m644 "$rel/$a/lib${a}_shared.so" "$named/$so"
	fonts=$src/fonts/craft-fonts-$(field "$a" fonts | cut -c1-8)
	work=$src/debian/stage/$a; mkdir -p "$work/target/release" "$work/dist"
	for b in $(field "$a" bins); do cp "$rel/$a/$b" "$work/target/release/$b"; done
	# upstream's script reads the version from the app's root manifest, which the generated workspace keeps aside
	appdir=$ws/$a
	cp "$appdir/Cargo.toml.upstream-root" "$work/Cargo.toml.root"
	( cd "$appdir"
	  [ -f Cargo.toml ] && mv Cargo.toml "$work/Cargo.toml.generated" || true
	  cp "$work/Cargo.toml.root" Cargo.toml
	  trap 'rm -f Cargo.toml; [ ! -f "$work/Cargo.toml.generated" ] || mv "$work/Cargo.toml.generated" Cargo.toml' EXIT
	  env LD_LIBRARY_PATH="$named" CARGO_TARGET_DIR="$work/target" DIST="$work/dist" CRAFT_FONTS_DIR="$fonts" \
	      "${a^^}_BUILD_SHA=$(field "$a" rev)" "${a^^}_BUILD_DATE=$date" \
	      bash packaging/linux/package.sh --skip-build --formats tar >"$work/package.log" 2>&1 \
	      || { tail -30 "$work/package.log" >&2; echo "$a: upstream's packaging script failed" >&2; exit 1; } )
	stage=$work/target/linux-package/root
	[ -d "$stage/usr/share/applications" ] || { echo "$a: upstream's stage has no desktop file" >&2; exit 1; }
	pkg=$src/debian/$a; rm -rf "$pkg"; mkdir -p "$pkg"
	cp -a "$stage/usr" "$pkg/"
	install -D -m644 "$named/$so" "$pkg/$libdir/$so"
	mkdir -p "$pkg/usr/lib/craft-suite"
	for b in $(field "$a" bins); do
		mv "$pkg/usr/bin/$b" "$pkg/usr/lib/craft-suite/$b"
		sed "s/@PROGRAM@/$b/g" "$src/debian/craft-suite-launcher.in" >"$pkg/usr/bin/$b"
		chmod 755 "$pkg/usr/bin/$b"
	done
	doc=$pkg/usr/share/doc/$a
	install -m644 "$src/debian/authors/$a.txt" "$doc/AUTHORS"
	# every crate linked into the app's programs and libraries, with its licence expression
	python3 - "$ws" "$a" "$doc/THIRD-PARTY-LICENSES.txt" <<'PY'
import json, sys
from pathlib import Path
ws, app, out = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
meta = {(p['name'], p['version']): p for p in json.loads((ws / 'metadata.json').read_text())['packages']}
rows = set()
for listing in (ws / 'shared/crates.txt', ws / f'{app}-shared/crates.txt'):
    for line in listing.read_text().split('\n'):
        if line:
            n, v = line.split(' ')
            p = meta[(n, v)]
            if p['source']:
                rows.add(f"{n} {v}: {p['license'] or 'see the crate'}")
Path(out).write_text(f"Third-party Rust crates in the libraries {app}'s programs load (name version: SPDX licence expression),\n"
                     "from each vendored crate's Cargo.toml. Each crate's licence text is in the source package.\n\n" + '\n'.join(sorted(rows)) + '\n')
PY
done
