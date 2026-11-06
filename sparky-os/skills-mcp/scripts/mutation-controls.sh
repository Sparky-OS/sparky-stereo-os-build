#!/bin/bash
# Negative controls for the engine's rules: each mutation removes one check from a copy of the tree, rebuilds the
# tests and requires the named test binary to go RED (in a container). A rule whose removal changes no test is untested.
# Usage: OUT=/scratch scripts/mutation-controls.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:?Set OUT to the scratch directory}
IMAGE=${IMAGE:-skills-mcp-430-base:1}
W=$OUT/mutation
trap 'rm -rf "$W"' EXIT
fails=0
mutate() { # name, file, python replace expression old, new, test binary
	local name=$1 file=$2 old=$3 new=$4 bin=$5
	rm -rf "$W"; mkdir -p "$W"
	cp -r "$HERE" "$W/p"
	python3 - "$W/p/$file" "$old" "$new" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p).read()
if old not in s:
    sys.exit('mutation target not found: ' + old)
open(p, 'w').write(s.replace(old, new, 1))
PY
	(cd "$W/p" && ZIG_GLOBAL_CACHE_DIR=$OUT/zig-global ZIG_LOCAL_CACHE_DIR=$W/cache zig build test-bins --prefix "$W/out" >"$W/build.log" 2>&1) || true
	if [ ! -x "$W/out/tests/$bin" ]; then
		echo "BUILD BROKE (the mutation must compile): $name"; fails=$((fails + 1)); rm -rf "$W/cache" "$W/out"; return
	fi
	if docker run --rm --network none --ulimit core=0 --user "$(id -u):$(id -g)" --tmpfs /tmp:mode=1777 -v "$W/p:/product:ro" -v "$W/out/tests:/t:ro" -w /product "$IMAGE" "/t/$bin" >/dev/null 2>&1; then
		echo "NOT RED: $name ($bin still passes without the rule)"; fails=$((fails + 1))
	else
		echo "RED as expected: $name"
	fi
	rm -rf "$W/cache" "$W/out"
}
mutate "eligibility filter removed from find" compiled/L5_executable/op_find.zig 'if (!all and !r.eligible) continue;' '_ = all;' L1_domain_engine_test
mutate "path check accepts everything" compiled/L4_atomic/pathsafe/atom.zig 'if (rel.len == 0 or rel[0] == '"'"'/'"'"') return error.Refused;' 'if (rel.len == 0) return error.Refused; if (rel.len > 0) return rel;' L4_atomic_pathsafe_test
mutate "resolved path containment removed" compiled/L5_executable/op_read.zig 'pathsafe.checkResolved(root, real) catch return error.Refused;' '_ = root;' L1_domain_engine_test
mutate "gate ignores the skill's list" compiled/L4_atomic/command_gate/atom.zig 'if (!listed) return' 'if (!listed and false) return' L4_atomic_command_gate_test
mutate "ambiguous names resolved silently" compiled/L1_domain/skills/engine.zig 'if (count == 1) return hit.?;' 'if (count >= 1) return hit.?;' L1_domain_engine_test
mutate "slot class check removed" compiled/L5_executable/op_run.zig 'if (!slot_class.matches(c, v)) return error.BadSlot;' '_ = slot_class.matches(c, v);' L1_domain_gate_run_test
mutate "environment not reduced" compiled/L5_executable/op_run.zig 'if (std.mem.eql(u8, k, "LANG") or std.mem.eql(u8, k, "HOME") or std.mem.startsWith(u8, k, "XDG_")) try env.put' 'if (true) try env.put' L1_domain_gate_run_test
echo "mutations not caught: $fails"
[ "$fails" = 0 ]
