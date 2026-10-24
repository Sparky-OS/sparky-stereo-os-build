#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/16
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/16
# Checks sparky-stereo-skills as installed (or the one named by HELPER), in a throwaway home: what it links, what it
# leaves alone, what it skips, how it follows an upgrade, what it removes, its archive, its languages and its refusal
# to run as root. Run as an ordinary user inside a container; prints ok or FAIL per check and exits 1 on any FAIL.
set -uo pipefail
HELPER=${HELPER:-/usr/bin/sparky-stereo-skills}
SYSTEM=${SPARKY_STEREO_SKILLS:-/usr/share/sparky-stereo-os/skills}
T=$(mktemp -d "${TMPDIR:-/var/tmp}/skills-test.XXXXXX")
trap 'rm -rf "$T"' EXIT
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
# the whole output first: grep -q closes the pipe early, and pipefail would count that as a failure
# shellcheck disable=SC2329 # called through check's eval
says() { local out; out=$(env "$1" "$HELPER" status 2>&1); grep -q "$2" <<<"$out"; }

# A copy of the installed skills, so skills can be added, broken and removed as an upgrade would
F=$T/skills
cp -a "$SYSTEM" "$F"
export SPARKY_STEREO_SKILLS=$F
valid=$(for d in "$F"/*/; do head -n 1 "$d/SKILL.md" | grep -qx -- --- && echo x; done | wc -l)
total=$(find "$F" -mindepth 1 -maxdepth 1 -type d | wc -l)
export HOME=$T/home XDG_CONFIG_HOME=$T/home/.config LANG=C.UTF-8 LC_ALL='' LC_MESSAGES=''
unset DISPLAY WAYLAND_DISPLAY
mkdir -p "$HOME/.claude" "$HOME/.codex" "$HOME/.claude/skills/audio"
echo 'my own skill' >"$HOME/.claude/skills/audio/SKILL.md"
mkdir "$F/zz-single" "$F/zz-alternative" "$F/zz-absent"
printf -- '---\nname: zz-single\ndescription: A skill gated by one package.\n  requires-packages: zz-single-package\n---\n\n# Single\n' >"$F/zz-single/SKILL.md"
printf -- '---\nname: zz-alternative\ndescription: A skill gated by package alternatives.\n  requires-packages: zz-alternative-absent | zz-alternative-present\n---\n\n# Alternative\n' >"$F/zz-alternative/SKILL.md"
printf -- '---\nname: zz-absent\ndescription: A skill whose package is absent.\n  requires-packages: zz-absent-package\n---\n\n# Absent\n' >"$F/zz-absent/SKILL.md"
valid=$(for d in "$F"/*/; do head -n 1 "$d/SKILL.md" | grep -qx -- --- && echo x; done | wc -l)
total=$(find "$F" -mindepth 1 -maxdepth 1 -type d | wc -l)
echo "skills in the copy: $total, with a header: $valid"
real_packages=$(for d in "$F"/*/; do
	awk 'NR > 1 && /^---[ \t]*$/ {exit}
		/^  requires-packages:/ {sub(/^  requires-packages:[ \t]*/, ""); print; exit}' "$d/SKILL.md"
done | sed 's/|/ /g' | xargs)
packages='zz-single-package zz-alternative-present'" $real_packages"
export SPARKY_STEREO_PACKAGES="$packages"

out=$("$HELPER" link 2>&1); echo "$out" | sed 's/^/     /'
n_agents=$(find "$HOME/.agents/skills" -maxdepth 1 -type l | wc -l)
n_claude=$(find "$HOME/.claude/skills" -maxdepth 1 -type l | wc -l)
check "the skill whose only package is present is linked into ~/.agents/s and ~/.claude" '[ -L "$HOME/.agents/skills/zz-single" ] && [ -L "$HOME/.claude/skills/zz-single" ]'
check "a package alternative is accepted ($n_agents agents, $valid skills, 2 gated)" '[ -L "$HOME/.agents/skills/zz-alternative" ] && [ -L "$HOME/.claude/skills/zz-alternative" ] && [ "$n_agents" -eq $((valid - 1)) ]'
check "the same into ~/.claude, except the person's own audio ($n_claude of $((valid - 1)))" '[ "$n_claude" -eq $((valid - 1)) ]'
check "the skill whose package is absent is not linked" '[ ! -e "$HOME/.agents/skills/zz-absent" ] && [ ! -e "$HOME/.claude/skills/zz-absent" ]'
check "and the helper says none of its packages are installed" 'grep -q "zz-absent" <<<"$out"'
remaining=$(tr ' ' '\n' <<<"$packages" | grep -vx zz-single-package | xargs)
SPARKY_STEREO_PACKAGES="$remaining" "$HELPER" link >/dev/null
check "a package that has gone away removes the stale link" '[ ! -e "$HOME/.agents/skills/zz-single" ] && [ ! -e "$HOME/.claude/skills/zz-single" ] && [ -e "$HOME/.agents/skills/zz-alternative" ] && [ -e "$HOME/.claude/skills/zz-alternative" ]'
env SPARKY_STEREO_PACKAGES="$packages" "$HELPER" --first-login >/dev/null
check "login relinks the same still-installed packages" '[ -L "$HOME/.agents/skills/zz-single" ] && [ -L "$HOME/.claude/skills/zz-single" ]'
remaining=$(tr ' ' '\n' <<<"$remaining" | grep -vx zz-alternative-present)
if [ -z "$remaining" ]; then remaining='zz-none-package'; fi
SPARKY_STEREO_PACKAGES="$remaining" "$HELPER" link >/dev/null
check "when every alternative has gone away the stale link goes too" '[ ! -e "$HOME/.agents/skills/zz-alternative" ] && [ ! -e "$HOME/.claude/skills/zz-alternative" ]'
check "the person's own ~/.claude/skills/audio is untouched" '[ ! -L "$HOME/.claude/skills/audio" ] && grep -qx "my own skill" "$HOME/.claude/skills/audio/SKILL.md"'
check "every link reads its SKILL.md" '! for l in "$HOME"/.agents/skills/* "$HOME"/.claude/skills/*; do [ -r "$l/SKILL.md" ] || echo missing; done | grep -q missing'
check "Cline is not linked when it is not installed" '[ ! -e "$HOME/.cline" ]'
check "status says Codex's and Claude Code's folders are found, in 20 runs of 20" 'n=0; for i in $(seq 20); do out=$("$HELPER" status 2>&1); grep -qE "^agents .* found " <<<"$out" && grep -qE "^claude .* found " <<<"$out" && n=$((n + 1)); done; [ "$n" -eq 20 ]'
check "the state names the folders linked" 'grep -qx "LINKED=agents claude" "$XDG_CONFIG_HOME/sparky-stereo-skills/state"'

# A skill without a valid header is never linked; an upgrade adds one skill and removes another
first=$(find "$F" -mindepth 1 -maxdepth 1 -type d -printf "%f\n" | sort | head -n 1)
mkdir "$F/zz-broken"; printf -- '--- name: zz-broken description: its header on one line ---\n\n# Broken\n' >"$F/zz-broken/SKILL.md"
mkdir "$F/zz-new"; printf -- '---\nname: zz-new\ndescription: A skill added by an upgrade.\n---\n\n# New\n' >"$F/zz-new/SKILL.md"
rm -rf "${F:?}/$first"
out=$("$HELPER" --first-login 2>&1); echo "$out" | sed 's/^/     /'
check "after the upgrade, the new skill is linked at login" '[ -L "$HOME/.agents/skills/zz-new" ] && [ -L "$HOME/.claude/skills/zz-new" ]'
check "after the upgrade, the removed skill's links are gone ($first)" '[ ! -e "$HOME/.agents/skills/$first" ] && [ ! -L "$HOME/.agents/skills/$first" ]'
check "a skill whose header is one line is not linked" '[ ! -e "$HOME/.agents/skills/zz-broken" ]'
out=$("$HELPER" link 2>&1)
check "and the helper says why it skipped it" 'grep -q "zz-broken" <<<"$out"'

check "list gives each skill with its description" 'out=$("$HELPER" list 2>/dev/null); grep -q "^zz-new: A skill added by an upgrade.$" <<<"$out"'
"$HELPER" export "$T/skills.zip" >/dev/null
zipn=$(python3 -c 'import sys, zipfile; print(sum(1 for n in zipfile.ZipFile(sys.argv[1]).namelist() if n.count("/") == 1 and n.endswith("/SKILL.md")))' "$T/skills.zip")
check "the Open WebUI archive holds one folder with a SKILL.md per valid skill ($zipn)" '[ "$zipn" -eq "$valid" ]'

mkdir -p "$T/project"
"$HELPER" --project "$T/project" link >/dev/null
check "--project links into the project's .agents/skills and .claude/skills" '[ -L "$T/project/.agents/skills/zz-new" ] && [ -L "$T/project/.claude/skills/zz-new" ]'
check "--project leaves the state of the home alone" 'grep -qx "LINKED=agents claude" "$XDG_CONFIG_HOME/sparky-stereo-skills/state"'

"$HELPER" unlink claude >/dev/null
check "unlink claude removes only our links there" '[ -z "$(find "$HOME/.claude/skills" -maxdepth 1 -type l)" ] && [ -d "$HOME/.claude/skills/audio" ]'
check "and keeps the other folder linked" '[ -L "$HOME/.agents/skills/zz-new" ]'
check "and the state forgets claude" 'grep -qx "LINKED=agents" "$XDG_CONFIG_HOME/sparky-stereo-skills/state"'
"$HELPER" unlink >/dev/null
check "unlink with no name removes every link of ours" '[ -z "$(find "$HOME" -type l)" ]'
check "the person's own skill is still there" '[ -f "$HOME/.claude/skills/audio/SKILL.md" ]'

check "Polish for pl_PL" 'says LANG=pl_PL.UTF-8 "Dowiązane:"'
check "French for fr_CA (the bare language)" 'says LANG=fr_CA.UTF-8 "compétences liées sur"'
check "Brazilian Portuguese for pt_BR" 'says LANG=pt_BR.UTF-8 "habilidades vinculadas"'
check "German for de_AT" 'says LANG=de_AT.UTF-8 "Skills verknüpft"'
check "Japanese for ja_JP" 'says LANG=ja_JP.UTF-8 "リンク済み"'
check "Korean for ko_KR" 'says LANG=ko_KR.UTF-8 "링크됨"'
check "Simplified Chinese for zh_CN" 'says LANG=zh_CN.UTF-8 "已链接"'
check "Traditional Chinese for zh_TW" 'says LANG=zh_TW.UTF-8 "已連結"'
check "English for zh_HK (Chinese keeps its territory)" 'says LANG=zh_HK.UTF-8 "skills linked"'
check "LC_ALL wins over LANG" 'out=$(LANG=pl_PL.UTF-8 LC_ALL=fr_FR.UTF-8 "$HELPER" status 2>/dev/null); grep -q "compétences liées sur" <<<"$out"'
check "an unknown folder name is refused" '! "$HELPER" link nowhere 2>/dev/null'
exit $fail
