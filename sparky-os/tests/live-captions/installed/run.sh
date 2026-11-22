#!/bin/bash
# Installed Partners/adapter proof in a private, network-disabled systemd rig.
set -euo pipefail
: "${DOCKER_HOST:?set your lane Docker socket}"
proof=$(cd -- "$(dirname -- "$0")" && pwd)
: "${LC73_RIG_IMAGE:?installed proof image}"
: "${LC73_FIXTURES:?fixture folder with stereo.mkv}"
gpu=${1:?amd or nvidia}; scale=${2:?1 or 1.25}; language=${3:?en or pt_BR}; out=$(realpath -m "${4:?new output directory}")
[ ! -e "$out" ];mkdir -p "$out"
case "$gpu" in amd) device=/dev/dri/renderD128;; nvidia) device=nvidia.com/gpu=0;; *) exit 2;; esac
name=lc73-installed-${gpu}-${scale//./-}
cleanup() { docker logs "$name" > "$out/boot.log" 2>&1 || true; docker stop -t 15 "$name" >/dev/null || true; docker rm "$name" >/dev/null || true; }
docker create --name "$name" --pull=never --platform linux/amd64 --cpus 4 --ulimit core=1 --network none \
 --cgroupns=private --security-opt writable-cgroups=true --tmpfs /run --tmpfs /tmp --cap-add SYS_RESOURCE --cap-add SYS_NICE --device "$device" --group-add 125 \
 --mount type=bind,src="$proof",dst=/proof,readonly \
 --mount type=bind,src="$LC73_FIXTURES",dst=/fixtures,readonly \
 --mount type=bind,src="$out",dst=/out \
 -e LC73_KIT_FIXTURE="${LC73_KIT_FIXTURE:-0}" -e QT_LOGGING_RULES='kwin_*.debug=true' "$LC73_RIG_IMAGE" /sbin/init > "$out/container-id.txt"
cat "$out/container-id.txt" >> "$out/.container-ids"
if [ -n "${LC73_CONTAINER_LEDGER:-}" ]; then cat "$out/container-id.txt" >> "$LC73_CONTAINER_LEDGER"; fi
trap cleanup EXIT
docker start "$name" >/dev/null
docker exec "$name" bash -c 'set -e; for i in {1..240}; do [ -S /run/dbus/system_bus_socket ] && break; sleep .5; done; [ -S /run/dbus/system_bus_socket ]; getent group 125 >/dev/null || groupadd -g 125 lc73-render; group=$(getent group 125 | cut -d: -f1); usermod -a -G "$group" builder; loginctl enable-linger builder; systemctl restart user@1000' > "$out/setup.log" 2>&1
docker exec -e LC73_CASE=session "$name" python3 /proof/installed-setup.py >> "$out/setup.log" 2>&1
docker exec "$name" runuser -u builder -- env XDG_RUNTIME_DIR=/run/user/1000 sparky-stereo-partners card cpu >> "$out/setup.log" 2>&1
docker exec "$name" runuser -u builder -- env XDG_RUNTIME_DIR=/run/user/1000 sparky-stereo-partners live-captions select tiny >> "$out/setup.log" 2>&1
set +e
timeout 900 docker exec "$name" runuser -u builder -- python3 /proof/installed-session.py /out/session "$scale" "$language" > "$out/session.log" 2>&1
rc=$?
set -e
docker exec "$name" journalctl --no-pager -o short-monotonic > "$out/journal.log" 2>&1 || true
printf '%s\n' "$rc" > "$out/exit.txt"
exit "$rc"
