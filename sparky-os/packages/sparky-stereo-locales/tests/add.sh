#!/bin/bash
# sparky-stereo-locales 0.3.0 (ORDER 252c, J8): --add, and the manual pages and Tesseract files as language packages.
# Runs in a throwaway container (root, no network) that has dpkg-dev: the edition's package list (languages.list) is
# turned into empty stand-in packages of the same names in a local apt repository, so apt installs and purges for real.
# Usage: DEB=/path/sparky-stereo-locales.deb LIST=/path/lists/languages.list add.sh   (/srv/standin/repo is built when absent)
set -u
FAILS=0
ok() { echo "  ok:   $1"; }
bad() { echo "  FAIL: $1"; FAILS=$((FAILS + 1)); }
check() { local label="$1"; shift; if "$@"; then ok "$label"; else bad "$label"; fi; }
installed() { [ "$(dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null)" = "ii " ]; }
not() { ! "$@"; }
export DEBIAN_FRONTEND=noninteractive
TOOL=sparky-stereo-locales
R=$(mktemp -d)
trap 'rm -rf "$R"' EXIT

# stand-in packages for every name of the edition's list, and for the tool's own dependencies, as a flat repository
# (built once: a container image that already holds /srv/standin/repo skips this)
REPO=/srv/standin/repo
if [ ! -f "$REPO/Packages" ]; then
	mkdir -p "$REPO" "$R/pk"
	{ grep -v '^#' "$LIST"; echo yad; echo sparky-remsu; } | while read -r name; do
		[ -n "$name" ] || continue
		d=$R/pk/$name
		mkdir -p "$d/DEBIAN"
		printf 'Package: %s\nVersion: 1\nArchitecture: all\nMaintainer: t <t@example.org>\nDescription: stand-in\n' "$name" > "$d/DEBIAN/control"
		dpkg-deb --root-owner-group -b "$d" "$REPO/${name}_1_all.deb" >/dev/null
	done
	(cd "$REPO" && dpkg-scanpackages . 2>/dev/null > Packages)
fi
rm -f /etc/apt/sources.list /etc/apt/sources.list.d/*
printf 'deb [trusted=yes] file:%s ./\n' "$REPO" > /etc/apt/sources.list.d/standin.list
apt-get update -qq >/dev/null 2>&1
cp "$DEB" "$R/tool.deb"
apt-get install -y -qq --no-install-recommends "$R/tool.deb" >/dev/null 2>&1 || { echo "cannot install $DEB"; exit 99; }
echo 'LANG=en_US.UTF-8' > /etc/default/locale
export LANG=C.UTF-8
inst() { apt-get install -y -qq --no-install-recommends "$@" >/dev/null 2>&1; }

echo "== the manual pages and the Tesseract files are language packages"
inst manpages-pl manpages-de manpages-ja tesseract-ocr-eng tesseract-ocr-pol tesseract-ocr-deu tesseract-ocr-jpn tesseract-ocr-jpn-vert tesseract-ocr-chi-sim hunspell-pl hunspell-de-de
out=$($TOOL --keep pl --dry-run 2>&1)
for p in manpages-de manpages-ja tesseract-ocr-deu tesseract-ocr-jpn tesseract-ocr-jpn-vert tesseract-ocr-chi-sim hunspell-de-de; do
	check "--keep pl would remove $p" grep -qx "  $p" <<<"$out"
done
for p in manpages-pl tesseract-ocr-pol tesseract-ocr-eng hunspell-pl; do
	check "--keep pl keeps $p" sh -c "! printf '%s\n' \"\$1\" | grep -qx '  $p'" _ "$out"
done
$TOOL --keep pl >/dev/null 2>&1; rc=$?
check "--keep pl: exit 0" [ $rc = 0 ]
check "manpages-ja is gone" not installed manpages-ja
check "tesseract-ocr-jpn-vert is gone" not installed tesseract-ocr-jpn-vert
check "manpages-pl stays" installed manpages-pl
check "tesseract-ocr-eng stays (English is always kept)" installed tesseract-ocr-eng
$TOOL --restore >/dev/null 2>&1
check "--restore brings the manual pages of ja back" installed manpages-ja
check "--restore brings the Tesseract files of ja back" installed tesseract-ocr-jpn

echo "== --add: nothing is removed"
# the person pruned every language but Polish and German with this tool earlier: ja, fr and pt are entirely gone
$TOOL --keep pl,de >/dev/null 2>&1
check "ja is entirely gone" sh -c "! dpkg-query -W -f='\${Package}\n' | grep -q 'ja\\b\|jpn'"
before=$(dpkg-query -W -f='${Package}\n' | sort)
out=$($TOOL --add ja --dry-run 2>&1)
check "--add ja --dry-run: would install the manual pages" grep -qx '  manpages-ja' <<<"$out"
check "--add ja --dry-run: would install Tesseract's Japanese files" grep -qx '  tesseract-ocr-jpn' <<<"$out"
check "--add ja --dry-run: would install the input method engine" grep -qx '  fcitx5-mozc' <<<"$out"
check "--add ja --dry-run: removes nothing" sh -c "! printf '%s\n' \"\$1\" | grep -q 'apt-get purge'" _ "$out"
check "--add ja --dry-run: changes nothing" [ "$(dpkg-query -W -f='${Package}\n' | sort)" = "$before" ]
$TOOL --add ja > "$R/add.out" 2>&1; rc=$?
check "--add ja: exit 0" [ $rc = 0 ]
for p in manpages-ja tesseract-ocr-jpn tesseract-ocr-jpn-vert fcitx5-mozc; do check "--add ja installs $p" installed "$p"; done
check "--add ja removes none of the packages that were there" bash -c "[ -z \"\$(comm -23 <(printf '%s\n' \"\$1\") <(dpkg-query -W -f='\${Package}\n' | sort))\" ]" _ "$before"
check "--add ja lets the language back into dpkg's configuration" sh -c "! grep -q 'man/ja\$' /etc/dpkg/dpkg.cfg.d/sparky-stereo-locales"
check "the German files are untouched" installed hunspell-de-de
$TOOL --add ja > "$R/add2.out" 2>&1; rc=$?
check "--add ja again: exit 0, nothing to add" sh -c "[ $rc = 0 ] && grep -q 'Nothing to add' '$R/add2.out'"

echo "== --add system follows /etc/default/locale"
echo 'LANG=pt_BR.UTF-8' > /etc/default/locale
$TOOL --add system >/dev/null 2>&1; rc=$?
check "pt_BR: exit 0" [ $rc = 0 ]
for p in manpages-pt-br tesseract-ocr-por hunspell-pt-br libreoffice-l10n-pt-br; do check "pt_BR: $p" installed "$p"; done
echo 'LANG=en_US.UTF-8' > /etc/default/locale
out=$($TOOL --add system 2>&1); rc=$?
check "English: nothing to add, exit 0" sh -c "[ $rc = 0 ] && printf '%s' \"\$1\" | grep -q 'Nothing to add'" _ "$out"

echo "== a language this tool excluded before is let back in"
apt-get purge -y -qq manpages-pl tesseract-ocr-pol hunspell-pl >/dev/null 2>&1
printf 'path-exclude=/usr/share/man/pl\npath-exclude=/usr/share/man/pl/*\npath-exclude=/usr/share/locale/pl_*\npath-exclude=/usr/share/man/de\n' > /etc/dpkg/dpkg.cfg.d/sparky-stereo-locales
rm -f /var/lib/sparky-stereo-locales/removed
$TOOL --add pl >/dev/null 2>&1
check "the pl exclusions are gone" sh -c "! grep -q 'man/pl\|locale/pl_' /etc/dpkg/dpkg.cfg.d/sparky-stereo-locales"
check "another language's exclusion stays" grep -qx 'path-exclude=/usr/share/man/de' /etc/dpkg/dpkg.cfg.d/sparky-stereo-locales

echo "== failures are said"
$TOOL --add xx > "$R/xx.out" 2>&1; rc=$?
check "unknown code: exit 2" [ $rc = 2 ]
$TOOL --add > "$R/none.out" 2>&1; rc=$?
check "no code: exit 1" [ $rc = 1 ]
apt-get purge -y -qq manpages-fr tesseract-ocr-fra hunspell-fr hyphen-fr >/dev/null 2>&1
rm -f /etc/apt/sources.list.d/standin.list; apt-get update -qq >/dev/null 2>&1
echo 'LANG=de_DE.UTF-8' > /etc/default/locale
$TOOL --add fr > "$R/off.out" 2>&1; rc=$?
check "the repository is gone: exit 4" [ $rc = 4 ]
check "said in German with the command to try again" grep -q 'konnten nicht installiert werden.*sparky-stereo-locales --add fr' "$R/off.out"
check "nothing of fr was installed" not installed manpages-fr

[ "$FAILS" -eq 0 ] || { echo "$FAILS check(s) failed"; exit 1; }
echo "all checks passed"
