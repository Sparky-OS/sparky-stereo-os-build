#!/bin/sh
# Pauses a test VM (QMP stop) when /K3D's free space falls under 6 GB (the floor is 5), and logs it.
#   space-guard.sh QMP_SOCKET LOG
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
Q=$1; LOG=$2
while [ -S "$Q" ]; do
	free=$(df -BG --output=avail /K3D | tail -1 | tr -dc 0-9)
	if [ "$free" -lt 6 ]; then
		python3 ${SPARKY_WORKSPACES:?}/beta-iso-lutz/boot-matrix/vmctl.py "$Q" hmp stop >/dev/null 2>&1
		echo "$(date -u +%T) /K3D at ${free} GB: VM paused" >> "$LOG"; exit 1
	fi
	sleep 30
done
