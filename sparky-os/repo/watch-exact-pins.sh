#!/bin/bash
# The same-day watch for an edition package pinned to a Debian version (row 944; the daily watch of row 806 runs it):
# apt in a container reads Debian testing's and unstable's signed indexes, and check-exact-pins.py compares every exact
# pin of the edition's indexes with them. testing is the verdict (exit 1 names the package to rebuild), unstable is the
# warning of the next move. Run it daily on the published tree, and before a round with the candidate pool's index after it.
# BASE is the image apt runs in: debian:testing reads Debian only; an image of an installed edition also reads every other
# repository the edition does (NVIDIA's CUDA repository, deb-multimedia, SparkyLinux), so their pins are judged as a person's apt
# judges them. The edition's own source (sparky-stereo.sources) is removed there: its index is the EDITION_PACKAGES given.
# Usage: watch-exact-pins.sh OUT EDITION_PACKAGES [EDITION_PACKAGES ...]   (published tree first, then a pool)
# Environment: DOCKER_HOST, NAME (the container's name, default exact-pins-watch), BASE (default debian:testing),
#   CONTAINER_IDS (a file the container's id is appended to before it is removed), FAIL_ON_WARN=1 (exit 1 on a warning),
#   PULL (docker run's pull policy, default missing), EXTRA_ROOT (a folder copied over the container's root before apt reads its sources: the sources an installed edition
#   has only on some machines, such as NVIDIA's from sparky-stereo-cuda-repo, with the keyring they name).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
tree=$(cd "$here/../.." && pwd)
OUT=${1:?usage: watch-exact-pins.sh OUT EDITION_PACKAGES...}
shift
[ "$#" -gt 0 ] || { echo "name at least one edition Packages index" >&2; exit 2; }
for index in "$@"; do [ -f "$index" ] || { echo "no such index: $index" >&2; exit 2; }; done
NAME=${NAME:-exact-pins-watch}
mkdir -p "$OUT"
[ -z "$(ls -A "$OUT")" ] || { echo "$OUT is not empty" >&2; exit 2; }
OUT=$(realpath "$OUT")
EXTRA=()
[ -z "${EXTRA_ROOT:-}" ] || EXTRA=(-v "$(cd "$EXTRA_ROOT" && pwd)":/extra:ro)
rc=0
docker run --name "$NAME" --pull "${PULL:-missing}" --ulimit core=1 --platform linux/amd64 -e HOSTID="$(id -u):$(id -g)" -v "$OUT":/out \
	--add-host repo.sparkyos.org:127.0.0.1 --add-host d2server:127.0.0.1 "${EXTRA[@]}" \
	-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$tree/tools/https-only-apt.sh":/run/https-only-apt.sh:ro \
	"${BASE:-debian:testing}" sh -c '
set -e
trap "chown -R \"$HOSTID\" /out" EXIT
rm -f /etc/apt/sources.list.d/sparky-stereo.sources
[ ! -d /extra ] || cp -a /extra/. /
sh /run/https-only-apt.sh
keyring=$(grep -l -r "deb.debian.org" /etc/apt/sources.list.d | xargs sed -n "s/^Signed-By: *//p" | head -1)
printf "Types: deb\nURIs: https://deb.debian.org/debian\nSuites: unstable\nComponents: main contrib non-free non-free-firmware\nSigned-By: %s\n" \
	"${keyring:-/usr/share/keyrings/debian-archive-keyring.pgp}" >/etc/apt/sources.list.d/zz-unstable.sources
sed -i "s/^Components: main$/Components: main contrib non-free non-free-firmware/" /etc/apt/sources.list.d/*.sources
apt-get -q -o APT::Update::Error-Mode=any update >/out/update.log 2>&1
cat /etc/apt/sources.list.d/*.sources >/out/sources-read.txt
for list in /var/lib/apt/lists/*_Packages*; do
	name=$(basename "$list"); name=${name%.lz4}; name=${name%.gz}; name=${name%.xz}; name=${name%.zst}
	case $name in
	*binary-i386_* | *binary-arm64_* | *binary-armhf_*) continue ;;
	deb.debian.org_debian_dists_testing_*) kind=testing ;;
	deb.debian.org_debian_dists_unstable_*) kind=unstable ;;
	*) kind=also ;;
	esac
	/usr/lib/apt/apt-helper cat-file "$list" >"/out/$kind-$name"
done
for suite in testing unstable; do grep -h -E "^(Date|Valid-Until):" /var/lib/apt/lists/*_dists_${suite}_InRelease >/out/$suite-index.txt; done
' >"$OUT/console.log" 2>&1 || rc=$?
[ -z "${CONTAINER_IDS:-}" ] || docker inspect -f '{{.Id}}' "$NAME" >>"$CONTAINER_IDS"
docker rm "$NAME" >/dev/null
[ "$rc" = 0 ] || { echo "reading Debian's indexes failed (exit $rc): $OUT/console.log" >&2; exit 2; }
args=()
for index in "$@"; do args+=(--edition "$index"); done
for suite in testing unstable; do
	for list in "$OUT/$suite-"*_Packages; do args+=(--debian "$suite=$list"); done
done
for list in "$OUT/also-"*_Packages; do [ -e "$list" ] && args+=(--also "$(basename "$list" | sed 's/^also-//; s/_Packages$//')=$list"); done
[ "${FAIL_ON_WARN:-}" != 1 ] || args+=(--fail-on-warn)
echo "Debian testing index: $(sed -n 's/^Date: //p' "$OUT/testing-index.txt"); unstable: $(sed -n 's/^Date: //p' "$OUT/unstable-index.txt")" | tee "$OUT/result.txt"
rc=0
python3 -I "$here/check-exact-pins.py" "${args[@]}" | tee -a "$OUT/result.txt" || rc=${PIPESTATUS[0]}
exit "$rc"
