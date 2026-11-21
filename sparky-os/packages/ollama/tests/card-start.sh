#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/21
# Copyright 2026 under the GNU GPL3 License
# The service as a person starts it: systemctl --user start ollama.service in a real user manager (systemd as PID 1 in a
# container, root running this script for the account USER), once for each Partners choice; the engine's own journal lines
# say which cards it computes on. A card that cannot be used: the service fails once with status 4 and is not restarted, the
# problem is kept, and nothing listens. No model is pulled, loaded or run.
# Usage: card-start.sh USER CHOICE=EXPECTED...   CHOICE: auto, cpu or a card (pci-0000:01:00.0); EXPECTED: as gpu-discovery.sh,
# comma-separated (CUDA@0000:01:00.0, Vulkan@0000:0b:00.0, cpu), or "fails" for a choice that cannot be used.
set -u
user=$1
shift
uid=$(id -u "$user")
home=$(getent passwd "$user" | cut -d: -f6)
fail=0
check() { if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: got '$2', expected '$3'"; fail=1; fi; }
systemctl start "user@$uid.service" || { echo "FAIL the user manager did not start"; exit 1; }
as_user() { runuser -u "$user" -- env XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus "$@"; }
config=$home/.config/sparky-stereo-graphicsrc
record=$home/.local/state/sparky-stereo-problems/sparky-stereo-graphics_partners.json
for pair in "$@"; do
	choice=${pair%%=*}
	want=${pair#*=}
	echo "== Partners card: $choice"
	as_user mkdir -p "$home/.config"
	if [ "$choice" = auto ]; then as_user rm -f "$config"; else as_user sh -c "printf '[Render]\nPartners=%s\n' '$choice' > '$config'"; fi
	as_user systemctl --user reset-failed ollama.service 2>/dev/null
	since=$(date '+%Y-%m-%d %H:%M:%S')
	as_user systemctl --user start ollama.service
	for _ in $(seq 1 120); do
		journalctl -q --since "$since" _SYSTEMD_USER_UNIT=ollama.service | grep -q 'inference compute\|no compatible GPUs' && break
		[ "$(as_user systemctl --user show -p ActiveState --value ollama.service)" = failed ] && break
		sleep 0.5
	done
	sleep 1
	journalctl -q --since "$since" _SYSTEMD_USER_UNIT=ollama.service | grep -E 'msg="inference compute"|not in this computer|cannot run|was not started' | sed -E 's/^.*\]: //; s/^time=[^ ]+ //; s/GPU-([0-9a-f]{4})[0-9a-f-]{32}/GPU-\1.../g' | cut -c1-260 | head -8
	if [ "$want" = fails ]; then
		check "$choice: the service failed" "$(as_user systemctl --user show -p ActiveState --value ollama.service)" failed
		check "$choice: with status 4" "$(as_user systemctl --user show -p ExecMainStatus --value ollama.service)" 4
		check "$choice: not started again" "$(as_user systemctl --user show -p NRestarts --value ollama.service)" 0
		check "$choice: the problem is kept" "$(test -e "$record"; echo $?)" 0
		check "$choice: nothing listens" "$(ss -Htln | grep -c ':11434 ')" 0
	else
		got=$(journalctl -q --since "$since" _SYSTEMD_USER_UNIT=ollama.service | grep 'inference compute' | sed -E 's/.* library=([^ ]+) .* pci_id=("[^"]*"|[^ ]*) .*/\1@\2/; s/"//g; s/^cpu@$/cpu/' | sort | tr '\n' ' ')
		echo "   the engine reports: $got"
		check "$choice: the journal names the engine" "$(journalctl -q --since "$since" _SYSTEMD_USER_UNIT=ollama.service -o cat --output-fields=SYSLOG_IDENTIFIER | sort -u | tr '\n' ' ')" "ollama "
		check "$choice: the engine computes on exactly" "$got" "$(printf '%s\n' "${want//,/ }" | tr ' ' '\n' | sort | tr '\n' ' ')"
		check "$choice: the service is running" "$(as_user systemctl --user show -p ActiveState --value ollama.service)" active
		check "$choice: it listens on 127.0.0.1:11434" "$(ss -Htln | awk '{print $4}' | grep -cx '127.0.0.1:11434')" 1
		check "$choice: no problem kept" "$(test -e "$record"; echo $?)" 1
		as_user systemctl --user stop ollama.service
		check "$choice: stopped" "$(as_user systemctl --user show -p ActiveState --value ollama.service)" inactive
	fi
done
exit $fail
