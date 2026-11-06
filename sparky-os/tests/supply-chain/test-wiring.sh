#!/bin/bash
# Static test of the build scripts that pass the host's provenance facts into their container (ORDER 394b): each one that
# calls sparky_provenance_init must source build-provenance.sh, call it before its docker run, and give that docker run
# "${SPARKY_PROV_ARGS[@]}". Red on broken copies. Also prints the scripts that end in check-debs without being wired.
# Usage: bash test-wiring.sh
set -euo pipefail
OS=$(cd "$(dirname "$0")/../.." && pwd)
fail=0
wired_ok() {  # wired_ok FILE
	local f=$1
	bash -n "$f" || return 1
	grep -q 'build-provenance.sh"$' "$f" || { echo "$f: does not source build-provenance.sh"; return 1; }
	local init run
	init=$(grep -n '^[[:space:]]*sparky_provenance_init ' "$f" | head -1 | cut -d: -f1)
	run=$(grep -n 'docker run' "$f" | grep -v '^[0-9]*:#' | head -1 | cut -d: -f1)
	[ -n "$init" ] && [ -n "$run" ] && [ "$init" -lt "$run" ] || { echo "$f: sparky_provenance_init is not before docker run"; return 1; }
	sed -n "${run},\$p" "$f" | grep -q '"${SPARKY_PROV_ARGS\[@\]}"' || { echo "$f: docker run lacks \"\${SPARKY_PROV_ARGS[@]}\""; return 1; }
}
n=0
while IFS= read -r f; do
	n=$((n + 1))
	if wired_ok "$f"; then :; else fail=1; fi
done < <(grep -rlE '^[[:space:]]*sparky_provenance_init ' "$OS/packages" "$OS/release" "$OS/upstream" --include=*.sh)
echo "$n wired build scripts checked"
[ "$n" -ge 19 ] || { echo "FAIL: fewer wired scripts than expected ($n)"; fail=1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cp "$OS/packages/kwin/build.sh" "$T/ok.sh"; wired_ok "$T/ok.sh" && echo "ok   green  kwin/build.sh" || { echo "FAIL green kwin"; fail=1; }
sed 's/"${SPARKY_PROV_ARGS\[@\]}" //' "$T/ok.sh" > "$T/noargs.sh"
sed '/^sparky_provenance_init /d' "$T/ok.sh" > "$T/noinit.sh"
sed '/build-provenance.sh"$/d' "$T/ok.sh" > "$T/nosource.sh"
for c in noargs noinit nosource; do
	if wired_ok "$T/$c.sh" >/dev/null 2>&1; then echo "FAIL red $c: accepted"; fail=1; else echo "ok   red  $c"; fi
done
# ORDER 412: a host driver (a docker run in packages/ or release/) whose container reaches the Lean Code gate must pass the
# host facts or say why it cannot: sparky_provenance_init / provenance_args(), or SPARKY_PROVENANCE_OPTOUT with its reason
# (calling release/build-dh-lean.sh counts: that script calls sparky_provenance_init itself).
# Otherwise lean.release check-debs now stops the build with a message; this finds it before a build is wasted.
audit_driver() {  # audit_driver FILE
	grep -qE 'docker (run|exec)|"docker", ?"run"|'"'docker', 'run'" "$1" || return 0
	grep -qE 'check-debs|build-in-container|build-lc|build-dh-lean|build-entry' "$1" || return 0
	grep -qE '^[[:space:]]*sparky_provenance_init |provenance_args\(|SPARKY_PROVENANCE_OPTOUT|release/build-dh-lean\.sh' "$1"
}
m=0
while IFS= read -r f; do
	m=$((m + 1))
	audit_driver "$f" || { echo "FAIL: ${f#$OS/} runs a container that reaches the gate and neither calls sparky_provenance_init nor sets SPARKY_PROVENANCE_OPTOUT"; fail=1; }
done < <(grep -rlE 'check-debs|build-in-container|build-lc|build-dh-lean|build-entry' "$OS/packages" "$OS/release" "$OS/upstream" --include=*.sh --include=*.py | grep -v '/tests/')
echo "$m files that reach the gate audited for a provenance call or opt-out"
printf '%s\n' '#!/bin/bash' 'docker run --rm img bash /tools/build-in-container.sh' > "$T/driver-bad.sh"
cp "$T/driver-bad.sh" "$T/driver-ok.sh"; sed -i '2i sparky_provenance_init img' "$T/driver-ok.sh"
audit_driver "$T/driver-bad.sh" && { echo "FAIL red driver-bad: accepted"; fail=1; } || echo "ok   red  driver without the call"
audit_driver "$T/driver-ok.sh" && echo "ok   green driver with the call" || { echo "FAIL green driver-ok"; fail=1; }
echo "-- scripts that run lean.release check-debs from a folder with no wired script (they record the finish time and files only):"
for d in $(grep -rl 'lean.release check-debs' "$OS/packages" "$OS/upstream" "$OS/release" --include=*.sh --include=*.py | xargs -n1 dirname | sort -u); do
	grep -lqE '^[[:space:]]*sparky_provenance_init ' "$d"/*.sh 2>/dev/null || echo "   ${d#$OS/}"
done
# ORDER 421b: the same call gives every build its source date; no script that writes a source may read the clock or pack an
# unnormalized tree (tests/reproducible-sources/test.sh, in a container, proves the bytes; this is its static half)
if git -C "$OS/.." rev-parse --git-dir >/dev/null 2>&1; then
	python3 "$OS/tests/reproducible-sources/check_producers.py" "$OS/.." || fail=1
fi
[ $fail = 0 ] && echo "ALL PASS" || { echo "FAILED"; exit 1; }
