#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/06
# Copyright 2026 under the GNU GPL3 License
# The split packages under dpkg, in a throwaway container as root (dpkg needs it; the checks of the skills themselves run as
# an ordinary user): install, the helper's verbs through the engine, a second package that adds a skill and then loses it,
# dpkg refusing a third package that ships the same path, the dependency, and the upgrade from the published helper.
# Inputs (mounted by run-dpkg-tests.sh): /debs holds the new .deb files, /published the published sparky-stereo-skills .deb.
# yad is a dialog toolkit this container does not have; it is ignored for dependency purposes (the dialog is tested with a stub).
# no pipefail: grep -q ends a pipe early and the program writing into it can then die of SIGPIPE, which pipefail turns into a
# failed check at random (seen once in three runs of the same debs, ORDER 447); the grep decides what each check says
set -u
NEW_HELPER=$(ls /debs/sparky-stereo-skills_*_all.deb)
NEW_ENGINE=$(ls /debs/sparky-stereo-skills-engine_*_amd64.deb)
OLD_HELPER=$(ls /published/sparky-stereo-skills_*_all.deb)
fail=0
ok() { echo "ok   $*"; }
bad() { echo "FAIL $*"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
DPKG="dpkg --ignore-depends=yad"
useradd -m tester 2>/dev/null
as_user() { runuser -u tester -- env HOME=/home/tester SPARKY_STEREO_PACKAGES= "$@"; }

# 1. the published helper alone, then the new pair over it
$DPKG -i "$OLD_HELPER" >/dev/null 2>&1
check "the published helper installs" 'dpkg -s sparky-stereo-skills | grep -q "^Status: install ok installed"'
old_version=$(dpkg-query -W -f='${Version}' sparky-stereo-skills)
check "the published helper has no engine and no skills place" '[ ! -e /usr/libexec/sparky-stereo-skills/engine ] && [ ! -e /usr/share/agent-skills ]'
out=$($DPKG -i "$NEW_HELPER" 2>&1); code=$?
check "the new helper alone is not configured: its engine is a Depends" '[ $code -ne 0 ] || grep -q "dependency problems\|not configured" <<<"$out"'
check "...dpkg says which package it waits for" 'grep -q "sparky-stereo-skills-engine" <<<"$out"'
$DPKG -i "$NEW_ENGINE" "$NEW_HELPER" >/dev/null 2>&1
check "engine and helper install together over the published helper" 'dpkg -s sparky-stereo-skills sparky-stereo-skills-engine | grep -c "^Status: install ok installed" | grep -qx 2'
new_version=$(dpkg-query -W -f='${Version}' sparky-stereo-skills)
check "the helper is newer than the published one ($old_version to $new_version)" 'dpkg --compare-versions "$new_version" gt "$old_version"'
check "the helper depends on the engine at its own version" 'dpkg-query -W -f="\${Depends}" sparky-stereo-skills | grep -q "sparky-stereo-skills-engine (>= $new_version)"'
check "the engine is one static amd64 program and nothing else needs it" 'file /usr/libexec/sparky-stereo-skills/engine | grep -q "statically linked" && [ "$(dpkg-query -W -f="\${Architecture}" sparky-stereo-skills-engine)" = amd64 ] && [ -z "$(dpkg-query -W -f="\${Depends}" sparky-stereo-skills-engine)" ]'
check "the package names the edition's skills tree for the engine" 'grep -qx "developer /usr/share/sparky-stereo-os/skills" /usr/share/agent-skills/paths.d/sparky-stereo-skills.conf'
check "dpkg --verify finds nothing changed in the engine package" '[ -z "$(dpkg --verify sparky-stereo-skills-engine 2>&1)" ]'

# 2. the helper's verbs through the engine, as an ordinary user
total=$(find /usr/share/sparky-stereo-os/skills -mindepth 1 -maxdepth 1 -type d | wc -l)
out=$(as_user sparky-stereo-skills list); n_list=$(wc -l <<<"$out")
check "list serves only skills whose packages are installed ($n_list of $total)" '[ "$n_list" -gt 0 ] && [ "$n_list" -le "$total" ] && grep -q "^[a-z0-9-]*: " <<<"$out"'
as_user sparky-stereo-skills link >/dev/null 2>&1
n_linked=$(find /home/tester/.agents/skills -maxdepth 1 -type l 2>/dev/null | wc -l)
diff <(find /home/tester/.agents/skills -maxdepth 1 -type l -printf "%f\n" | sort) <(as_user sparky-stereo-skills list | cut -d: -f1 | sort) | sed 's/^/     list vs link: /'
check "list and link agree ($n_list and $n_linked)" '[ "$n_list" -eq "$n_linked" ]'
check "find ranks the skill for a symptom first" 'out=$(as_user sparky-stereo-skills find --limit 1 an apt pin that ignores i386); grep -q "^1\. edition-packaging " <<<"$out" && grep -q "Next: sparky-stereo-skills context edition-packaging" <<<"$out"'
check "context prints the skill with its hash and the common guidance" 'out=$(as_user sparky-stereo-skills context edition-packaging --max-chars 400000); grep -q "^Source: skills/edition-packaging/SKILL.md" <<<"$out" && grep -q "^Full-file SHA256: [0-9a-f]\{64\}$" <<<"$out" && grep -q "^Source: AGENTS.md" <<<"$out"'
check "the old spellings still work: context --list-sections, --list and --find" 'as_user sparky-stereo-skills context --list-sections edition-packaging | grep -q . && as_user sparky-stereo-skills context --list | grep -qx edition-packaging && as_user sparky-stereo-skills context --find an apt pin that ignores i386 | grep -q "^1\. "'
check "sections names the headings" 'as_user sparky-stereo-skills sections edition-packaging | grep -q .'
check "context --output writes a new file and refuses to overwrite one" 'f=/home/tester/ctx.txt; as_user sparky-stereo-skills context edition-packaging --max-chars 400000 --output $f >/dev/null 2>&1 && [ -s $f ] && ! as_user sparky-stereo-skills context edition-packaging --max-chars 400000 --output $f >/dev/null 2>&1'
check "bundle makes a ZIP of the public tree and will not overwrite it" 'z=/home/tester/b.zip; as_user sparky-stereo-skills bundle $z >/dev/null 2>&1 && python3 -c "import zipfile,sys; n=zipfile.ZipFile(sys.argv[1]).namelist(); sys.exit(0 if \"AGENTS.md\" in n and any(x.endswith(\"edition-packaging/SKILL.md\") for x in n) else 1)" $z && ! as_user sparky-stereo-skills bundle $z >/dev/null 2>&1'
check "export still makes the Open WebUI archive" 'as_user sparky-stereo-skills export /home/tester/e.zip >/dev/null 2>&1 && [ -s /home/tester/e.zip ]'
check "serve answers a ping over stdio and exits when stdin closes" 'out=$(printf "%s\n" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}" "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"ping\"}" | timeout 5 runuser -u tester -- env HOME=/home/tester sparky-stereo-skills serve 2>/dev/null); grep -q "\"id\":2,\"result\":{}" <<<"$out"'
check "serve refuses root" 'out=$(sparky-stereo-skills serve </dev/null 2>&1); code=$?; [ $code -ne 0 ] && [ -n "$out" ]'
check "mcp commands shows the policy and saves a change" 'as_user sparky-stereo-skills mcp commands | grep -q "policy: auto" && as_user sparky-stereo-skills mcp commands ask >/dev/null && as_user sparky-stereo-skills mcp commands | grep -q "policy: ask" && as_user sparky-stereo-skills mcp commands auto >/dev/null'

# 3. a second package adds a skill, then loses it
mk() { # name, skill-name  (a package shipping /usr/share/agent-skills/user/<skill>/SKILL.md)
	local d=/tmp/pkg-$1; rm -rf "$d"; mkdir -p "$d/DEBIAN" "$d/usr/share/agent-skills/user/$2"
	printf 'Package: %s\nVersion: 1\nArchitecture: all\nMaintainer: t <t@t>\nDescription: test\n' "$1" >"$d/DEBIAN/control"
	printf -- '---\nname: %s\ndescription: A skill shipped by the package %s.\n---\n\n# %s\n\nBody from %s.\n' "$2" "$1" "$2" "$1" >"$d/usr/share/agent-skills/user/$2/SKILL.md"
	dpkg-deb --build "$d" "/tmp/$1.deb" >/dev/null
}
mk zz-skill-pkg zz-test; mk zz-skill-clash zz-test; mk zz-skill-gated zz-gated
sed -i 's/^description: .*/description: Needs a program.\nmetadata:\n  requires-packages: zz-absent-program/' /tmp/pkg-zz-skill-gated/usr/share/agent-skills/user/zz-gated/SKILL.md
sed -i '1,3{/^name:/!b};' /tmp/pkg-zz-skill-gated/usr/share/agent-skills/user/zz-gated/SKILL.md
dpkg-deb --build /tmp/pkg-zz-skill-gated /tmp/zz-skill-gated.deb >/dev/null
check "before: the skill is not served" '! as_user sparky-stereo-skills list | grep -q "^zz-test: "'
dpkg -i /tmp/zz-skill-pkg.deb >/dev/null 2>&1
check "a package that ships a skill adds it, with no help from this package" 'as_user sparky-stereo-skills list | grep -q "^zz-test: A skill shipped by the package zz-skill-pkg"'
check "...and it can be read through the helper's context" 'as_user sparky-stereo-skills context zz-test --max-chars 400000 | grep -q "Body from zz-skill-pkg"'
check "...and it is served over MCP as skill://system/user/zz-test/SKILL.md" 'out=$(printf "%s\n" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"resources/read\",\"params\":{\"_meta\":{\"io.modelcontextprotocol/protocolVersion\":\"2026-07-28\"},\"uri\":\"skill://system/user/zz-test/SKILL.md\"}}" | timeout 5 runuser -u tester -- env HOME=/home/tester sparky-stereo-skills serve 2>/dev/null); grep -q "Body from zz-skill-pkg" <<<"$out"'
out=$(dpkg -i /tmp/zz-skill-clash.deb 2>&1); code=$?
check "dpkg refuses a third package that ships the same path" '[ $code -ne 0 ] && grep -q "trying to overwrite .*zz-test/SKILL.md.*also in package zz-skill-pkg" <<<"$out"'
check "...and the first package's skill is untouched" 'as_user sparky-stereo-skills context zz-test --max-chars 400000 | grep -q "Body from zz-skill-pkg" && ! dpkg -s zz-skill-clash 2>/dev/null | grep -q "^Status: install ok installed"'
dpkg --purge zz-skill-clash >/dev/null 2>&1
dpkg -i /tmp/zz-skill-gated.deb >/dev/null 2>&1
check "a skill whose program is absent is not served, and --all still shows it" '! as_user sparky-stereo-skills list | grep -q "^zz-gated: " && as_user sparky-stereo-skills list --all | grep -q "^zz-gated: "'
dpkg -r zz-skill-gated >/dev/null 2>&1; dpkg -r zz-skill-pkg >/dev/null 2>&1
check "removing the package removes the skill" '! as_user sparky-stereo-skills list | grep -q "^zz-test: "'
check "...and every other skill is still served" '[ "$(as_user sparky-stereo-skills list | wc -l)" -eq "$n_list" ]'

# 4. the dialog, with a stub yad (the engine and the assistants' folders are real)
mkdir -p /tmp/stubs
cat >/tmp/stubs/yad <<'YAD'
#!/bin/sh
for a in "$@"; do [ "$a" = --form ] && { printf 'TRUE|%s|\n' "$YAD_POLICY"; exit 0; }; done
echo agents; exit 0
YAD
chmod +x /tmp/stubs/yad
mkdir -p /home/tester/.claude; chown tester /home/tester/.claude
cat >/tmp/stubs/claude <<'CL'
#!/bin/sh
echo "$@" >> /home/tester/claude.args
CL
chmod +x /tmp/stubs/claude
rm -rf /home/tester/.agents /home/tester/.config
ask=$(. /usr/share/sparky/sparky-stereo-skills/en; printf '%s' "$LOCAL31")
runuser -u tester -- env HOME=/home/tester PATH=/tmp/stubs:/usr/bin:/bin DISPLAY=:0 LANG=en_US.UTF-8 YAD_POLICY="$ask" sparky-stereo-skills --gui >/dev/null 2>&1
check "the dialog's second question registers the assistants found when checked" 'grep -q "mcp add --scope user sparky-stereo-skills" /home/tester/claude.args'
check "...and saves the command policy the person chose" 'as_user sparky-stereo-skills mcp commands | grep -q "policy: ask"'
check "...and the first question still links the skills" '[ -L /home/tester/.agents/skills/edition-packaging ]'

# 5. the package's own tests of the helper, against the installed pair, as an ordinary user
if [ -r /tests/helper.sh ]; then
	out=$(runuser -u tester -- env HOME=/home/tester HELPER=/usr/bin/sparky-stereo-skills bash /tests/helper.sh 2>&1); code=$?
	echo "$out" | sed 's/^/     helper.sh: /' | tail -8
	check "tests/helper.sh passes against the installed pair" '[ $code -eq 0 ]'
fi

# 6. removal and purge
dpkg -r sparky-stereo-skills >/dev/null 2>&1
check "removing the helper keeps the engine and the engine does not need the helper" 'dpkg -s sparky-stereo-skills-engine | grep -q "^Status: install ok installed"'
dpkg -r sparky-stereo-skills-engine >/dev/null 2>&1
check "the engine's files are gone after removal" '[ ! -e /usr/libexec/sparky-stereo-skills/engine ]'
exit $fail
