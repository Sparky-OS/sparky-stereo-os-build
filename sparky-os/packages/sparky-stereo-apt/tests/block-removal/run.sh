#!/bin/bash
# ORDER 413: starts one proof container: run.sh MODE   (MODE: red | green | modified; container r413-MODE, removed at the end)
#   red       the published 20261104.3 as the "new" package: every check of the removal must fail (exit 1)
#   green     the new package over 20261104.3, block file unmodified: exit 0
#   modified  the new package over 20261104.3, block file edited by a person: exit 0
# Paths come from the environment: OLD (folder with the published 20261104.3 and the two keyring debs), NEW (folder with the built
# package), EVID (where the log goes). Needs the https-only helper of /K3D/partners (ORDER 400): every container with apt starts with it.
set -u
MODE=$1
T=$(cd "$(dirname "$0")" && pwd)
: "${OLD:?folder with sparky-stereo-apt 20261104.3 and the keyring debs}" "${NEW:?folder with the new package}" "${EVID:?evidence folder}"
HELPER=${HELPER:-/K3D/partners/https-only-apt.sh}
mkdir -p "$EVID"
docker run --rm --name "r413-$MODE" --cpus 2 --ulimit core=0 --platform linux/amd64 --network bridge --add-host repo.sparkyos.org:192.168.0.60 \
	-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HELPER":/run/https-only-apt.sh:ro \
	-v "$OLD":/old:ro -v "$NEW":/new:ro -v "$T":/t:ro debian:testing \
	sh -c "sh /run/https-only-apt.sh && bash /t/inside.sh $MODE" 2>&1 | tee "$EVID/$MODE.log"
exit "${PIPESTATUS[0]}"
