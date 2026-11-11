#!/bin/bash
# Red and green test of sync-supply-chain.sh and of the served-files check of verify-online-repository.py (ORDER 394b).
# Needs rsync, gpg and gpgv; makes its own throwaway key in WORKDIR and sends only to a folder in WORKDIR.
# Usage: bash test-publish.sh WORKDIR
set -euo pipefail
W=$(realpath -m "${1:?work directory}")
R=$(cd "$(dirname "$0")/../../release" && pwd)
rm -rf "$W"; mkdir -p "$W/gnupg" "$W/publish" "$W/target/sbom/r0001" "$W/target/pool" "$W/target/dists"
chmod 700 "$W/gnupg"
export GNUPGHOME=$W/gnupg
fail=0
expect() {
	local want=$1 label=$2; shift 2
	if "$@" > "$W/last.out" 2>&1; then got=green; else got=red; fi
	if [ "$got" = "$want" ]; then echo "ok   $want  $label"; else echo "FAIL want $want, got $got: $label"; sed 's/^/     /' "$W/last.out" | head -12; fail=1; fi
}
gpg --batch --quiet --passphrase '' --quick-gen-key 'test <test@example.invalid>' ed25519 sign never 2>/dev/null
gpg --batch --armor --export test > "$W/key.asc"
gpg --batch --export test > "$W/kr.gpg"
(
	GNUPGHOME=$W/gnupg2; mkdir -m 700 "$GNUPGHOME"
	gpg --batch --quiet --passphrase '' --quick-gen-key 'other <other@example.invalid>' ed25519 sign never 2>/dev/null
	gpg --batch --armor --export other > "$W/other.asc"
)
printf 'bill\n' > "$W/publish/a.spdx.json"; printf '{}\n' > "$W/publish/p.intoto.jsonl"
(cd "$W/publish" && sha256sum a.spdx.json p.intoto.jsonl > SHA256SUMS)
echo old > "$W/target/sbom/r0001/old.txt"; echo marker > "$W/target/pool/keep.deb"; echo marker > "$W/target/dists/keep"
export SPARKY_SYNC_TARGET=$W/target
expect green "dry run without signature"            bash "$R/sync-supply-chain.sh" "$W/publish" r0002 "$W/key.asc"
expect green "dry run sent nothing"                 test ! -e "$W/target/sbom/r0002"
expect red   "--go refuses unsigned documents"      bash "$R/sync-supply-chain.sh" "$W/publish" r0002 "$W/key.asc" --go
expect green "nothing sent by the refused --go"     test ! -e "$W/target/sbom/r0002"
gpg --batch --armor --detach-sign --local-user test --output "$W/publish/SHA256SUMS.asc" "$W/publish/SHA256SUMS"
expect red   "--go refuses a signature of another key" bash "$R/sync-supply-chain.sh" "$W/publish" r0002 "$W/other.asc" --go
echo tampered >> "$W/publish/a.spdx.json"
expect red   "--go refuses a file that differs from SHA256SUMS" bash "$R/sync-supply-chain.sh" "$W/publish" r0002 "$W/key.asc" --go
printf 'bill\n' > "$W/publish/a.spdx.json"
expect red   "--go refuses a signature that does not cover SHA256SUMS" bash -c "echo x >> '$W/publish/SHA256SUMS'; sed -i '\$d' '$W/publish/SHA256SUMS'; printf '%s\n' '0 x' >> '$W/publish/SHA256SUMS'; bash '$R/sync-supply-chain.sh' '$W/publish' r0002 '$W/key.asc' --go"
(cd "$W/publish" && sha256sum a.spdx.json p.intoto.jsonl > SHA256SUMS)
expect green "--go sends a signed round"            bash "$R/sync-supply-chain.sh" "$W/publish" r0002 "$W/key.asc" --go
expect green "the round and its signature are there" bash -c "cd '$W/target/sbom/r0002' && sha256sum --check --quiet SHA256SUMS && test -f SHA256SUMS.asc && gpgv --keyring '$W/kr.gpg' SHA256SUMS.asc SHA256SUMS"
expect green "sbom/latest points at the round"       test "$(readlink "$W/target/sbom/latest")" = r0002
expect green "an earlier round, pool and dists are untouched" bash -c "test \"\$(cat '$W/target/sbom/r0001/old.txt')\" = old && test \"\$(cat '$W/target/pool/keep.deb')\" = marker && test \"\$(cat '$W/target/dists/keep')\" = marker"

# the served-files check (what verify-online-repository.py runs against the web root), with the target folder as the server
chk() {  # chk SERVED_ROOT
	python3 -I - "$R" "$W/publish" "$W/kr.gpg" "$1" <<'P'
import sys
sys.path.insert(0, sys.argv[1])
import supply_chain as sc
from pathlib import Path
root = Path(sys.argv[4])
sc.verify_served(sys.argv[2], 'r0002', lambda rel: (root / rel).read_bytes(), sys.argv[3])
P
}
expect green "served files are the signed ones"          chk "$W/target"
cp -a "$W/target" "$W/served-bad"
echo extra >> "$W/served-bad/sbom/r0002/a.spdx.json"
expect red   "a served document differs"                 chk "$W/served-bad"
cp -a "$W/target" "$W/served-sig"
printf 'junk\n' > "$W/served-sig/sbom/r0002/SHA256SUMS.asc"
expect red   "the served signature differs"              chk "$W/served-sig"
cp -a "$W/target" "$W/served-old"
rm "$W/served-old/sbom/latest"; ln -s r0001 "$W/served-old/sbom/latest"
expect red   "sbom/latest does not hold this round"      chk "$W/served-old"
GNUPGHOME=$W/gnupg2 gpg --batch --export other > "$W/other.gpg"
expect red   "the signature does not verify with another key" python3 -I -c "
import sys; sys.path.insert(0, '$R'); import supply_chain as sc
from pathlib import Path
sc.verify_served('$W/publish', 'r0002', lambda rel: (Path('$W/target')/rel).read_bytes(), '$W/other.gpg')"
[ $fail = 0 ] && echo "ALL PASS" || { echo "FAILED"; exit 1; }
