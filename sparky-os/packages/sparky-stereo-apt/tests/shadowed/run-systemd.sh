#!/bin/bash
# ORDER 458b: the shadowed-by-dmo proofs of run.sh with systemd as PID 1, so the unit that the dpkg post-invoke hook starts really runs:
# run-systemd.sh MODE   (red | green | manual | needed | fresh)
# The container is an amd64 forky image with systemd, systemd-sysv and dbus (SYSTEMD_IMAGE), booted unprivileged: --cgroupns=private and
# --security-opt writable-cgroups=true give PID 1 a writable cgroup tree of its own, with no --privileged and no added capability. Docker's
# --ulimit core=0 stays (HOUSE-RULES: a crash must not reach the host's coredump handler); systemd 262 refuses to start with a read-only
# cgroup tree and a core limit it cannot raise, so the image carries /etc/systemd/system.conf.d/core.conf (DefaultLimitCORE=0:0).
# Paths come from the environment as in run.sh: NEW, CACHE, EVID, SYSTEMD_IMAGE; REPO (default /K3D/sparky-repo-r1107a), HELPER, PREFIX (the
# container's name prefix, default shadowed-458b).
set -u
MODE=$1
T=$(cd "$(dirname "$0")" && pwd)
: "${NEW:?folder with the new package}" "${CACHE:?folder for the .deb cache}" "${EVID:?evidence folder}" "${SYSTEMD_IMAGE:?an amd64 forky image with systemd, systemd-sysv, dbus and ca-certificates}"
REPO=${REPO:-/K3D/sparky-repo-r1107a}
HELPER=${HELPER:-/K3D/partners/https-only-apt.sh}
NAME=${PREFIX:-shadowed-458b}-$MODE
mkdir -p "$EVID" "$CACHE/partial"
docker rm -f "$NAME" >/dev/null 2>&1
docker run -d --name "$NAME" --cpus 2 --ulimit core=0 --platform linux/amd64 --cgroupns=private --security-opt writable-cgroups=true \
	--tmpfs /run --tmpfs /run/lock --tmpfs /tmp --stop-signal SIGRTMIN+3 \
	-v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v "$HELPER":/run/https-only-apt.sh:ro \
	-v "$REPO":/repo:ro -v "$NEW":/new:ro -v "$T":/t:ro -v "$CACHE":/var/cache/apt/archives "$SYSTEMD_IMAGE" /sbin/init >/dev/null || exit 2
trap 'docker rm -f "$NAME" >/dev/null 2>&1' EXIT
for i in $(seq 60); do
	s=$(docker exec "$NAME" systemctl is-system-running 2>/dev/null)
	case $s in running | degraded) break ;; esac
	sleep 1
done
echo "systemd in $NAME: $s after ${i}s ($(docker exec "$NAME" systemctl --version | head -1))" | tee "$EVID/$MODE.log"
docker exec -e SYSTEMD=1 "$NAME" bash /t/inside.sh "$MODE" 2>&1 | tee -a "$EVID/$MODE.log"
exit "${PIPESTATUS[0]}"
