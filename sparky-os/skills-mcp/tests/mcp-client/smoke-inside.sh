#!/bin/bash
set -u
F=/product/data/fixtures
mkdir -p /tmp/home /tmp/xdg/agent-skills/developer /tmp/xdg/agent-skills/user
cp -r $F/ref-tree/skills/demo $F/ref-tree/skills/audio /tmp/xdg/agent-skills/developer/
cp -r $F/pdf-processing /tmp/xdg/agent-skills/user/
export XDG_DATA_DIRS=/tmp/xdg XDG_DATA_HOME=/tmp/nohome SPARKY_STEREO_PACKAGES=demoprog SPARKY_STEREO_REF=$F/ref-tree
pass=0; failn=0
ok() { pass=$((pass + 1)); echo "PASS $1"; }
bad() { failn=$((failn + 1)); echo "FAIL $1"; }
echo "SDK: $(/opt/mcp/bin/pip show mcp | sed -n 2p)"
for mode in legacy auto 2026-07-28; do
	out=$(/opt/mcp/bin/python /product/tests/mcp-client/smoke.py "$mode" 2>/tmp/err.$mode); code=$?
	echo "--- mode $mode (exit $code)"; echo "$out" | sed 's/^/    /'; head -5 /tmp/err.$mode | sed 's/^/    ERR /'
	[ $code = 0 ] && ok "mode $mode: the whole session runs to the end" || { bad "mode $mode: the whole session runs to the end"; continue; }
	g() { grep -q -- "$1" <<<"$out" && ok "mode $mode: $2" || bad "mode $mode: $2"; }
	case $mode in
		legacy) g '^PROTOCOL=2025-11-25' "the legacy handshake negotiated 2025-11-25" ;;
		auto) g '^PROTOCOL=2026-07-28' "auto mode: server/discover was understood, so the stateless era was chosen" ;;
		2026-07-28) g '^PROTOCOL=2026-07-28' "pinned to the stateless era" ;;
	esac
	# a client pinned to a version adopts it without asking the server, so it has no server name or capabilities to show
	if [ "$mode" != 2026-07-28 ]; then g '^SERVER=sparky-stereo-skills 0.1.0' "the server names itself"; fi
	g '^TOOLS=skills_commands,skills_context,skills_find,skills_list,skills_read,skills_run,skills_sections' "seven tools"
	g '^SCHEMAS_OBJECT=True' "every input schema is an object schema the SDK accepts"
	g 'skills_find:True' "skills_find is read only"
	g 'skills_run:False' "skills_run is not marked read only"
	g '^FIND_ERROR=False' "skills_find answers"
	g '^FIND_FIRST=demo' "and ranks demo first for 'widgets broken'"
	g '^CONTEXT_HAS_SHA=True' "skills_context returns the text with file hashes"
	g '^OVERBUDGET_ERROR=True SAYS=True' "over budget is a tool error that says nothing was truncated"
	g '^EMPTYQUERY_ERROR=True' "an empty query is a tool error, not a crash"
	g '^UNKNOWN_TOOL=' "an unknown tool is answered (as a protocol error, not accepted)"
	! grep -q 'UNKNOWN_TOOL=accepted' <<<"$out" && ok "mode $mode: an unknown tool is refused" || bad "mode $mode: an unknown tool is refused"
	g '^RESOURCE_PDF=skill://system/user/pdf-processing/SKILL.md' "resources/list lists the skill files"
	g '^READ_PDF_LEN=151' "resources/read returns the 151 byte file of the extension's example"
	g '^TEMPLATES=skill://' "the resource template is listed"
	! grep -q 'TRAVERSAL=accepted' <<<"$out" && ok "mode $mode: a traversal in a resource address is refused" || bad "mode $mode: a traversal is refused"
	if [ "$mode" = legacy ]; then g '^PING=ok' "ping"; fi
	if [ "$mode" = auto ]; then g 'CAP_EXT=\["io.modelcontextprotocol/skills"\]' "the Skills extension is declared in the capabilities"; fi
done
echo "files passing: $pass, files failing: $failn"
[ "$failn" = 0 ]
