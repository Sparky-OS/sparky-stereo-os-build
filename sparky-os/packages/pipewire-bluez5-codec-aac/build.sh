#!/bin/bash
# Build the AAC plugin from verified upstream source with native Lean Code.
# Usage: build.sh [PipeWire upstream version] [matching Debian version]
# SPARKY_BUILD_CONTAINER names the build container (a lane gives its own prefix).
# SPARKY_LC_ARCHIVE_DIR (required) is the link gate's folder, mounted at /archive: sources.json naming Debian forky's main
# and non-free and deb-multimedia's forky main and non-free, with the public keyrings it names (sparky-os/lean/archive.md),
# among them deb-multimedia-keyring.pgp: the plugin links the edition's FDK AAC, deb-multimedia's libfdk-aac2, as the
# published 1.6.9-2+aac2+lc1 did (Depends libfdk-aac2 (>= 1:3.0.0)), never Debian's libfdk-aac2t64 beside it. SPARKY_LC_PREVIOUS_DIR
# (optional) holds the predecessor .deb, so the gate checks that the new plugin resolves its libraries as that one did.
# When Debian has moved PipeWire, the predecessor's exact libspa version is gone from the live archive and the gate
# cannot solve it here: leave SPARKY_LC_PREVIOUS_DIR unset and compare afterwards with lean.release check-link's dated view
# (--previous-archive-config, --previous-published-at; sparky-os/lean/archive.md, "A dated view for an archive transition").
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../../repo/build-provenance.sh"
PWV=${1:-1.6.11}
DEBV=${2:-1.6.11-2}
OUT=${OUT:-${SPARKY_SCRATCH:?}/bt-aac}
: "${SPARKY_LC_ARCHIVE_DIR:?the folder of the link gate (sources.json and its keyrings); see sparky-os/lean/archive.md}"
ARCHIVE=$(cd "$SPARKY_LC_ARCHIVE_DIR" && pwd)
for need in sources.json deb-multimedia-keyring.pgp; do
    [ -f "$ARCHIVE/$need" ] || { echo "$ARCHIVE has no $need" >&2; exit 2; }
done
PREV_ARGS=()
if [ -n "${SPARKY_LC_PREVIOUS_DIR:-}" ]; then
    PREV_ARGS=(-v "$(cd "$SPARKY_LC_PREVIOUS_DIR" && pwd)":/prev:ro -e SPARKY_LC_PREVIOUS_DIR=/prev)
fi
[[ $PWV =~ ^[0-9][0-9.]+$ && $DEBV == "$PWV"-* && $DEBV =~ ^[0-9A-Za-z.+~:-]+$ ]] ||
    { echo "Expected matching upstream and Debian versions" >&2; exit 2; }
mkdir -p "$OUT"
OUT=$(realpath "$OUT")
[ ! -e "$OUT/pipewire-bluez5-codec-aac_${DEBV}+aac2+lc1_amd64.deb" ] ||
    { echo "Use a fresh output directory; this version already exists" >&2; exit 2; }
sparky_provenance_init debian:testing
NAME_ARGS=()
[ -z "${SPARKY_BUILD_CONTAINER:-}" ] || NAME_ARGS=(--name "$SPARKY_BUILD_CONTAINER")
docker run --ulimit core=1 --rm --cpus "${CPUS:-4}" "${NAME_ARGS[@]}" \
    --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined \
    "${SPARKY_PROV_ARGS[@]}" "${PREV_ARGS[@]}" \
    -e SPARKY_LC_ARCHIVE_CONFIG=/archive/sources.json -e SPARKY_LC_SCRATCH=/work/link-scratch -v "$ARCHIVE":/archive:ro \
    -v "$OUT:/out" -v "$HERE:/recipe:ro" -v "$HERE/../..:/toolkit:ro" \
    -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HERE/../../../tools/https-only-apt.sh":/run/https-only-apt.sh:ro \
    -e PWV="$PWV" -e DEBV="$DEBV" -e HOSTID="$(id -u):$(id -g)" \
    debian:testing bash -c 'sh /run/https-only-apt.sh && bash /recipe/build-in-container.sh'
