#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/04
# Copyright 2026 under the GNU GPL3 License
# ORDER 346f-3b: stereo-display-info's person-readable output ships in the nine languages (memory required-languages), and what the
# KInfoCenter page parses does not change. The golden files are the output of the published script (sparky-stereo-info 20261104,
# commit 805609a) on the fixture of fixture.sh, in English: text, --keys and --sections.
# Usage: translation-proof.sh STEREO_DISPLAY_INFO LANGDIR      exit 0 only when every case matches
set -u
S=${1:?the stereo-display-info script}
LD=${2:?the lang folder}
H=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
bash "$H/fixture.sh" "$T/fix"
fails=0
ok() { if [ "$1" = 0 ]; then echo "PASS $2"; else echo "FAIL $2"; fails=$((fails + 1)); fi; }
# run LANGENV... -- MODE: the script on the fixture, the host's own edition line dropped
run() {
	local envs=() mode=
	while [ $# -gt 0 ] && [ "$1" != -- ]; do envs+=("$1"); shift; done
	shift; mode=${1:-}
	env -i PATH="$T/fix/bin:$(dirname "$(command -v sh)"):/usr/bin:/bin" WAYLAND_DISPLAY=w0 SPARKY_STEREO_INFO_DRM="$T/fix/drm" SPARKY_STEREO_INFO_PNP_IDS="$T/fix/pnp.ids" \
		SPARKY_STEREO_INFO_LANGDIR="$LD" "${envs[@]}" sh "$S" $mode 2>&1 | sed '/^Sparky Stereo OS 9 /d;/^Debian GNU/d'
}
# the KInfoCenter page's parser (kcms/stereo3d/main.cpp of the kinfocenter patch), the same logic in Python: sections by "@@ kind name",
# displays by tab-separated --keys lines with at least five fields. Prints the structure the page would hold.
parse() { # parse FILE_SECTIONS FILE_KEYS
	python3 -I - "$1" "$2" <<'PY'
import sys
sections, cur, body = [], None, []
def flush():
    global cur, body
    if cur is not None:
        cur["text"] = "\n".join(body).strip(); sections.append(cur)
    body = []
for line in open(sys.argv[1], encoding="utf-8").read().split("\n"):
    if line.startswith("@@ "):
        flush(); m = line.split(" "); cur = {"kind": m[1], "name": m[2] if len(m) > 2 else ""}
    else:
        body.append(line)
flush()
displays = []
for line in open(sys.argv[2], encoding="utf-8").read().split("\n"):
    if not line: continue
    f = line.split("\t")
    if len(f) < 5: continue
    displays.append(f[:5])
assert sections and displays
for s in sections:
    assert s["text"], s
print([(s["kind"], s["name"]) for s in sections]); print(displays)
PY
}
LANGS="pt_BR pl fr de ja ko zh_CN zh_TW"
echo "== English is what it was"
run LANGUAGE= LC_ALL=C LANG=C -- >"$T/en.txt";  cmp -s "$T/en.txt" "$H/golden/text.txt"; ok $? "English text: byte for byte the published script's"
run LANGUAGE= LC_ALL=C LANG=C -- --sections >"$T/en.sec"; cmp -s "$T/en.sec" "$H/golden/sections.txt"; ok $? "English --sections: identical"
run LANGUAGE= LC_ALL=C LANG=C -- --keys >"$T/en.keys"; cmp -s "$T/en.keys" "$H/golden/keys.txt"; ok $? "--keys: identical"
echo "== the nine languages, LANGUAGE and LANG matching"
for l in $LANGS; do
	run LANGUAGE=$l LANG=$l.UTF-8 -- >"$T/$l.txt"
	run LANGUAGE=$l LANG=$l.UTF-8 -- --sections >"$T/$l.sec"
	run LANGUAGE=$l LANG=$l.UTF-8 -- --keys >"$T/$l.keys"
	cmp -s "$T/$l.keys" "$H/golden/keys.txt"; ok $? "$l: --keys byte-identical to English"
	diff <(grep '^@@' "$T/$l.sec") <(grep '^@@' "$H/golden/sections.txt") >/dev/null; ok $? "$l: the @@ lines of --sections identical"
	! cmp -s "$T/$l.txt" "$T/en.txt"; ok $? "$l: the text differs from English"
	[ "$(wc -l <"$T/$l.txt")" = "$(wc -l <"$T/en.txt")" ]; ok $? "$l: same number of lines as English"
	! grep -qE '%[1-4]' "$T/$l.txt"; ok $? "$l: no placeholder left"
	# every text line of the report, but the lines that are data (modes, tags, names), differs from English somewhere: count the lines kept
	same=$(diff <(cat "$T/en.txt") <(cat "$T/$l.txt") | grep -c '^>' ); total=$(wc -l <"$T/en.txt")
	[ "$same" -ge $((total / 2)) ]; ok $? "$l: $same of $total lines translated"
	parse "$T/$l.sec" "$T/$l.keys" >"$T/$l.parsed" 2>"$T/$l.perr"; parse "$H/golden/sections.txt" "$H/golden/keys.txt" >"$T/en.parsed"
	cmp -s "$T/$l.parsed" "$T/en.parsed"; ok $? "$l: the KInfoCenter page's parser gets the same sections and displays as in English"
done
echo "== which language is chosen"
chk() { local want=$1; shift; run "$@" -- >"$T/c.txt"; cmp -s "$T/c.txt" "$T/$want.txt"; }
chk ja LANGUAGE=ja LANG=C; ok $? "LANGUAGE alone chooses (ja with LANG=C)"
chk ja LANGUAGE= LC_ALL=ja_JP.UTF-8 LANG=pt_BR.UTF-8; ok $? "LC_ALL before LANG, whole code to the bare language (ja_JP gives ja)"
chk pt_BR LANGUAGE=xx:pt_BR:fr LANG=C; ok $? "LANGUAGE is a list: the first language with a file (xx has none)"
chk en LANGUAGE=en_US:pt_BR LANG=pt_BR.UTF-8; ok $? "a list that starts with English is English"
chk en LANGUAGE= LC_ALL= LANG=xx_YY.UTF-8; ok $? "a language with no file: English, not an empty text"
chk zh_TW LANGUAGE=zh_HK LANG=C; ok $? "zh_HK reads the Traditional file"
chk zh_CN LANGUAGE=zh LANG=C; ok $? "bare zh reads the Simplified file"
chk fr LANGUAGE= LC_ALL=fr_CA.UTF-8@euro LANG=C; ok $? "fr_CA.UTF-8@euro gives fr"
echo "== a string a language lacks is English"
mkdir -p "$T/part"; cp "$LD/en" "$T/part/en"; { head -n 6 "$LD/de"; grep '^LOCAL22=' "$LD/de"; } >"$T/part/de"
run LANGUAGE=de LANG=de.UTF-8 SPARKY_STEREO_INFO_LANGDIR="$T/part" -- >"$T/part.txt"
grep -q '^    Jetzt:$' "$T/part.txt" && grep -qF 'Graphics card card0' "$T/part.txt"; ok $? "a German file with one string: that one German, the rest English"
echo "== values with a % or a & stay as they are"
sed -i "s|DELL S2721DGF|DELL 100% \&amp; more|" "$T/fix/bin/edid-decode"
run LANGUAGE=pt_BR LANG=pt_BR.UTF-8 -- | grep -qF "DP-1: DELL 100% &amp; more"; ok $? "a display name with % and & is printed whole"
echo "failures: $fails"
[ "$fails" = 0 ]
