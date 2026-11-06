#!/bin/bash
# Runs inside the container started by e2e.sh.
set -u
BIN=/usr/bin/sparky-stereo-skills
F=/product/data/fixtures
G=/product/data/golden
pass=0; failn=0
ok() { pass=$((pass + 1)); echo "PASS $1"; }
bad() { failn=$((failn + 1)); echo "FAIL $1"; }
check() { # name, command that must succeed
	local n=$1; shift
	if "$@" >/dev/null 2>&1; then ok "$n"; else bad "$n"; fi
}

if [ "${AS_ROOT:-}" = 1 ]; then
	out=$($BIN serve </dev/null 2>&1); code=$?
	[ "$code" = 2 ] && grep -q 'never as root' <<<"$out" && ok "serve refuses root" || bad "serve refuses root ($code)"
	export SPARKY_STEREO_PACKAGES=x HOME=/tmp/rh XDG_DATA_DIRS=/tmp/rxdg; mkdir -p $HOME /tmp/rxdg/agent-skills/user/net-fix
	printf -- '---\nname: net-fix\ndescription: d\n---\n' > /tmp/rxdg/agent-skills/user/net-fix/SKILL.md
	echo '[{"id":"say","argv":["/bin/echo","hi"],"slots":{},"run":"assistant"}]' > /tmp/rxdg/agent-skills/user/net-fix/commands.json
	out=$(echo y | $BIN run net-fix say 2>&1); grep -q 'never run as root' <<<"$out" && ! grep -q '^hi$' <<<"$out" && ok "a command from a skill is never run as root" || bad "a command from a skill is never run as root"
	echo "files passing: $pass, files failing: $failn"; [ "$failn" = 0 ]; exit
fi

export SPARKY_STEREO_PACKAGES="demoprog"
export HOME=/tmp/home; mkdir -p $HOME
R="$BIN --root $F/ref-tree"

# 1. the command line equals the Python tool's recorded output
$R context demo | cmp -s - $G/context-demo.txt && ok "cli context demo equals the Python text" || bad "cli context demo equals the Python text"
$R context --section "demo:Second heading" | cmp -s - $G/context-section.txt && ok "cli section" || bad "cli section"
$R context --section "demo:First heading" --reference docs/guide.md | cmp -s - $G/context-section-ref.txt && ok "cli section with reference" || bad "cli section with reference"
$R sections demo | cmp -s - $G/sections-demo.txt && ok "cli sections" || bad "cli sections"
$R find "widgets broken" --limit 2 | grep -q '^1. demo (score ' && ok "cli find ranks demo first" || bad "cli find ranks demo first"
$R context demo --max-chars 300 2>&1 >/dev/null | grep -q 'Nothing was truncated' && ok "cli over budget says so" || bad "cli over budget says so"
$R list | grep -q '^demo	' && ! $R list | grep -q '^audio	' && $R list --all | grep -q '^audio	' && ok "cli list: only installed, --all shows the rest" || bad "cli list: only installed, --all shows the rest"
$R context nosuchskill 2>&1 | grep -q "No skill is called" && ok "cli unknown skill is said" || bad "cli unknown skill is said"

# 2. the MCP server, legacy era
M='"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28"}'
export SPARKY_STEREO_REF=$F/ref-tree
mkdir -p /tmp/xdg/agent-skills/developer /tmp/xdg/agent-skills/user
cp -r $F/ref-tree/skills/demo $F/ref-tree/skills/audio /tmp/xdg/agent-skills/developer/
cp -r $F/pdf-processing /tmp/xdg/agent-skills/user/
export XDG_DATA_DIRS=/tmp/xdg XDG_DATA_HOME=/tmp/nohome
legacy=$(printf '%s\n' \
 '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}' \
 '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
 '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
 '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"skills_find","arguments":{"query":"widgets broken"}}}' \
 '{"jsonrpc":"2.0","id":4,"method":"ping"}' | timeout 5 $BIN serve 2>/tmp/stderr.log)
grep -q '"id":1,"result":{"protocolVersion":"2025-11-25"' <<<"$legacy" && ok "legacy initialize" || bad "legacy initialize"
[ "$(grep -c '"id"' <<<"$legacy")" = 4 ] && ok "legacy: one reply per request, none for the notification" || bad "legacy: one reply per request"
for t in skills_find skills_list skills_sections skills_context skills_read skills_commands skills_run; do grep -q "\"name\":\"$t\"" <<<"$legacy" || { bad "tool $t listed"; }; done; ok "legacy tools/list names the seven tools"
grep -q '"id":3,"result":{"content":\[{"type":"text","text":"ranker: offline' <<<"$legacy" && ok "legacy skills_find answers" || bad "legacy skills_find answers"
! grep -q resultType <<<"$legacy" && ok "legacy replies carry no resultType" || bad "legacy replies carry no resultType"
grep -q 'widgets' /tmp/stderr.log && bad "the log never holds the query" || ok "the log never holds the query"
grep -q ' tools/call skills_find ' /tmp/stderr.log && ok "stderr logs method and tool" || bad "stderr logs method and tool"
# every stdout line parses as an object (starts and ends with braces)
! grep -qv '^{.*}$' <<<"$legacy" && ok "stdout holds only JSON lines" || bad "stdout holds only JSON lines"

# 3. stateless era
modern=$(printf '%s\n' \
 "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"server/discover\",\"params\":{$M}}" \
 "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\",\"params\":{$M}}" \
 "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/list\",\"params\":{}}" \
 '{"jsonrpc":"2.0","id":4,"method":"server/discover"}' \
 "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"nope/never\",\"params\":{$M}}" \
 'this is not json' \
 '[1,2]' \
 "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"tools/call\",\"params\":{$M,\"name\":\"skills_nothing\",\"arguments\":{}}}" \
 "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"skills/list\",\"params\":{$M}}" \
 "{\"jsonrpc\":\"2.0\",\"id\":10,\"method\":\"skills/get\",\"params\":{$M,\"uri\":\"skill://system/user/pdf-processing/SKILL.md\"}}" \
 "{\"jsonrpc\":\"2.0\",\"id\":11,\"method\":\"skills/get\",\"params\":{$M,\"uri\":\"skill://system/user/missing/SKILL.md\"}}" \
 "{\"jsonrpc\":\"2.0\",\"id\":12,\"method\":\"resources/read\",\"params\":{$M,\"uri\":\"skill://system/user/pdf-processing/templates/invoice.md\"}}" \
 "{\"jsonrpc\":\"2.0\",\"id\":13,\"method\":\"resources/read\",\"params\":{$M,\"uri\":\"skill://system/user/pdf-processing/..%2e/x\"}}" \
 "{\"jsonrpc\":\"2.0\",\"id\":14,\"method\":\"resources/list\",\"params\":{$M}}" \
 | timeout 5 $BIN serve 2>/dev/null)
line() { grep "\"id\":$1[,}]" <<<"$modern"; }
line 1 | grep -q '"resultType":"complete","supportedVersions":\["2026-07-28"\]' && line 1 | grep -q '"extensions":{"io.modelcontextprotocol/skills":{}}' && ok "modern server/discover declares the Skills extension" || bad "modern server/discover declares the Skills extension"
line 2 | grep -q '"resultType":"complete","ttlMs":5000' && ok "modern tools/list is cacheable" || bad "modern tools/list is cacheable"
line 3 | grep -q '"code":-32602' && ok "no _meta and no initialize is -32602" || bad "no _meta and no initialize is -32602"
line 4 | grep -q '"code":-32602' && ok "server/discover without _meta is -32602" || bad "server/discover without _meta is -32602"
line 5 | grep -q '"code":-32601' && ok "unknown method is -32601" || bad "unknown method is -32601"
grep -q '"id":null,"error":{"code":-32700' <<<"$modern" && ok "bad JSON is -32700" || bad "bad JSON is -32700"
grep -q '"id":null,"error":{"code":-32600' <<<"$modern" && ok "a batch is -32600" || bad "a batch is -32600"
line 8 | grep -q '"code":-32602' && ok "unknown tool is -32602" || bad "unknown tool is -32602"
line 9 | grep -q '"uri":"skill://system/user/pdf-processing/SKILL.md","frontmatter":{"name":"pdf-processing","description":"Extract, fill, and assemble PDF documents"},"resources":\[{"uri":"skill://system/user/pdf-processing/SKILL.md","digest":"sha256:99b737495721155ece826d57521e2d66141ebdc1344a400487481ea2642ab19e","size":151}' && ok "skills/list entry equals the extension's example (frontmatter, digest, size)" || bad "skills/list entry equals the extension's example"
line 9 | grep -q 'sha256:61f4ea6d2c75fde1b4977219e7e3107d491c3c26aefb6686e84d6281c088d9ee","size":29' && line 9 | grep -q 'sha256:f2ff774b1737ff3dec81c47946f9976f18a1a9f69dda0a81f22eabd95173c158","size":35' && ok "skills/list carries the two supporting files' digests" || bad "skills/list carries the two supporting files' digests"
line 9 | grep -q '"name":"demo"' && ! line 9 | grep -q '"name":"audio"' && ok "skills/list serves only installed skills" || bad "skills/list serves only installed skills"
line 10 | grep -q '"skill":{"uri":"skill://system/user/pdf-processing/SKILL.md"' && ok "skills/get" || bad "skills/get"
line 11 | grep -q '"code":-32602' && ok "skills/get of an unknown skill is -32602" || bad "skills/get of an unknown skill is -32602"
line 12 | grep -q '"text":"# Invoice\\n\\nCustomer:\\nAmount:\\n"' && ok "resources/read returns the file" || bad "resources/read returns the file"
line 13 | grep -q '"error"' && ok "resources/read refuses a traversal" || bad "resources/read refuses a traversal"
line 14 | grep -q 'skill://system/user/pdf-processing/templates/invoice.md' && ok "resources/list lists supporting files" || bad "resources/list lists supporting files"

# 4. the 51st call in ten seconds is refused
calls=$(for i in $(seq 1 60); do echo "{\"jsonrpc\":\"2.0\",\"id\":$i,\"method\":\"tools/call\",\"params\":{$M,\"name\":\"skills_list\",\"arguments\":{}}}"; done | timeout 10 $BIN serve 2>/dev/null)
[ "$(grep -c '"code":-32000' <<<"$calls")" = 10 ] && ok "60 calls: the last 10 are rate limited" || bad "60 calls: the last 10 are rate limited ($(grep -c '"code":-32000' <<<"$calls"))"

# 5. stdin closed: the server exits at once
start=$(date +%s%N); $BIN serve </dev/null >/dev/null 2>&1; end=$(date +%s%N)
[ $(( (end - start) / 1000000 )) -lt 1000 ] && ok "serve exits within a second of stdin closing" || bad "serve exits within a second of stdin closing"

# 6. registration goes through each assistant's own command, only when asked
mkdir -p /tmp/stubs; for p in claude codex gemini; do printf '#!/bin/sh\necho "$0 $@" >> /tmp/home/argv.log\n[ -n "${STUB_FAIL:-}" ] && exit 1\nexit 0\n' > /tmp/stubs/$p; chmod +x /tmp/stubs/$p; done
export PATH=/tmp/stubs:/usr/bin:/bin
[ ! -e $HOME/.config/sparky-stereo-skills/state ] && [ ! -e $HOME/argv.log ] && ok "nothing is written or run before the person asks" || bad "nothing is written or run before the person asks"
$BIN mcp register claude_code codex gemini_cli >/tmp/reg.out 2>&1
grep -q '/tmp/stubs/claude mcp add --scope user sparky-stereo-skills -- /usr/bin/sparky-stereo-skills serve' $HOME/argv.log && grep -q '/tmp/stubs/codex mcp add sparky-stereo-skills -- /usr/bin/sparky-stereo-skills serve' $HOME/argv.log && grep -q '/tmp/stubs/gemini mcp add -s user sparky-stereo-skills /usr/bin/sparky-stereo-skills serve' $HOME/argv.log && ok "register calls each assistant exactly as its table row" || bad "register calls each assistant exactly as its table row"
grep -q '^MCP=claude_code codex gemini_cli$' $HOME/.config/sparky-stereo-skills/state && ok "the registered assistants are remembered" || bad "the registered assistants are remembered"
$BIN mcp unregister claude_code >/dev/null 2>&1
grep -q 'claude mcp remove sparky-stereo-skills --scope user' $HOME/argv.log && grep -q '^MCP=codex gemini_cli$' $HOME/.config/sparky-stereo-skills/state && ok "unregister removes only that assistant" || bad "unregister removes only that assistant"
rm -f $HOME/.config/sparky-stereo-skills/state; STUB_FAIL=1 $BIN mcp register claude_code >/tmp/reg2.out 2>&1; code=$?
[ $code -ne 0 ] && grep -q 'refused' /tmp/reg2.out && [ ! -e $HOME/.config/sparky-stereo-skills/state ] && ok "an assistant that refuses is said, exits nonzero, and nothing is recorded" || bad "an assistant that refuses is said, exits nonzero, and nothing is recorded"
$BIN mcp register opencode >/tmp/reg3.out 2>&1; grep -q 'not installed\|could not run' /tmp/reg3.out && ok "an absent assistant program is said, not skipped" || bad "an absent assistant program is said, not skipped"
$BIN mcp unregister codex 2>&1 | grep -q 'there is no command' && ok "an assistant without a documented remove command tells the person what to delete" || bad "assistant without remove command"

# 7. the command switch, both ways, and the gate through the command line
$BIN mcp commands | grep -q 'commands policy: auto' && ok "default policy is auto" || bad "default policy is auto"
$BIN mcp commands ask >/dev/null && $BIN mcp commands | grep -q 'policy: ask' && grep -q '^COMMANDS=ask$' $HOME/.config/sparky-stereo-skills/state && ok "switch to ask is saved" || bad "switch to ask is saved"
$BIN mcp commands assistant >/dev/null && $BIN mcp commands | grep -q 'policy: assistant' && ok "switch to assistant is saved" || bad "switch to assistant is saved"
$BIN mcp commands bogus >/dev/null 2>&1; [ $? -ne 0 ] && ok "an unknown policy is refused" || bad "an unknown policy is refused"
mkdir -p /tmp/xdg/agent-skills/user/net-fix && cp $F/pdf-processing/SKILL.md /tmp/xdg/agent-skills/user/net-fix/SKILL.md && sed -i 's/pdf-processing/net-fix/' /tmp/xdg/agent-skills/user/net-fix/SKILL.md
echo '[{"id":"say","argv":["/bin/echo","{w}"],"slots":{"w":"word"},"expect":{"exit":0,"stdout_contains":"hi"},"run":"assistant"}]' > /tmp/xdg/agent-skills/user/net-fix/commands.json
$BIN mcp commands auto >/dev/null
echo n | $BIN run net-fix say w=hi >/tmp/run1.out 2>&1; ! grep -q '^hi$' /tmp/run1.out && ok "the command line asks and a no runs nothing" || bad "the command line asks and a no runs nothing"
echo y | $BIN run net-fix say w=hi >/tmp/run2.out 2>&1; grep -q '^hi$' /tmp/run2.out && grep -q 'expected result matched' /tmp/run2.out && ok "a yes runs it and reports the expected result" || bad "a yes runs it and reports the expected result"
echo y | $BIN run net-fix say w='$(id)' >/tmp/run3.out 2>&1; [ $? -ne 0 ] && ! grep -q uid /tmp/run3.out && ok "a slot value that does not fit is refused" || bad "a slot value that does not fit is refused"
echo y | $BIN run net-fix notlisted >/tmp/run4.out 2>&1; grep -q 'not listed' /tmp/run4.out && ok "an unlisted command is refused" || bad "an unlisted command is refused"
# through MCP: auto with no AI tool found asks the person, so the call is refused with the line to run by hand
mcpcall=$(printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{$M,\"name\":\"skills_run\",\"arguments\":{\"skill\":\"net-fix\",\"id\":\"say\",\"values\":{\"w\":\"hi\"}}}}" | PATH=/usr/bin:/bin $BIN serve 2>/dev/null)
grep -q '"isError":true' <<<"$mcpcall" && grep -q 'needs the person' <<<"$mcpcall" && ok "mcp skills_run with no AI tool found asks the person (refused, with the line to run)" || bad "mcp skills_run with no AI tool found asks the person"
mkdir -p $HOME/.claude
mcpcall=$(printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{$M,\"name\":\"skills_run\",\"arguments\":{\"skill\":\"net-fix\",\"id\":\"say\",\"values\":{\"w\":\"hi\"}}}}" | PATH=/usr/bin:/bin $BIN serve 2>/dev/null)
grep -q '"isError":false' <<<"$mcpcall" && grep -q 'expected result: matched' <<<"$mcpcall" && ok "mcp skills_run with an AI tool found runs at the assistant's approval" || bad "mcp skills_run with an AI tool found runs"
$BIN mcp commands ask >/dev/null
mcpcall=$(printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{$M,\"name\":\"skills_run\",\"arguments\":{\"skill\":\"net-fix\",\"id\":\"say\",\"values\":{\"w\":\"hi\"}}}}" | PATH=/usr/bin:/bin $BIN serve 2>/dev/null)
grep -q '"isError":true' <<<"$mcpcall" && ok "policy ask refuses the mcp call even with an AI tool found" || bad "policy ask refuses the mcp call even with an AI tool found"

echo "files passing: $pass, files failing: $failn"
[ "$failn" = 0 ]
