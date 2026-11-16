#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/16
# Copyright 2026 under the GNU GPL3 License
# The package's life on a system, with apt: install, a file of the person with the package's name, remove, purge, install again.
# Run as root in a throwaway container with the staged package as a flat apt repository at /stage and the fake devices at
# /opt/sa631/proc-asound (the lane's rig). Each check can fail; the exit status is the number of failures.
export SPARKY_STEREO_AUDIO_PROC=${SPARKY_STEREO_AUDIO_PROC:-/opt/sa631/proc-asound}
export DEBIAN_FRONTEND=noninteractive
FAILS=0
ok() { echo "PASS $1"; }
bad() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
PW=/etc/pipewire/pipewire.conf.d/00-sparky-stereo-audio.conf
WP=/etc/wireplumber/wireplumber.conf.d/00-sparky-stereo-audio.conf
echo "deb [trusted=yes] file:///stage ./" > /etc/apt/sources.list.d/sparky-stage.list
apt-get update >/dev/null 2>&1
check "before: no drop-in" "[ ! -e $PW ]"
apt-get -y install sparky-stereo-audio >/tmp/install.log 2>&1
check "install: exit status 0" "dpkg -s sparky-stereo-audio | grep -q 'Status: install ok installed'"
for f in $PW /etc/pipewire/client.conf.d/00-sparky-stereo-audio.conf /etc/pipewire/jack.conf.d/00-sparky-stereo-audio.conf \
	/etc/pipewire/pipewire-pulse.conf.d/00-sparky-stereo-audio.conf $WP; do
	check "install wrote $f with the package's mark" "head -n 1 $f | grep -q '^# sparky-stereo-audio:'"
done
check "the rates come from the devices of the rig" "grep -q 'allowed-rates = \[ 32000 44100 48000 88200 96000 176400 192000 \]' $PW"
check "show names the devices" "LANG=C sparky-stereo-audio show | grep -q 'RIG TV'"
check "dpkg --verify finds the package's files unchanged" "[ -z \"\$(dpkg --verify sparky-stereo-audio 2>&1)\" ]"
check "systemd: the system service verifies (exit status 0)" "systemd-analyze verify /usr/lib/systemd/system/sparky-stereo-audio.service"
check "systemd: the user units verify (exit status 0)" "(cd /usr/lib/systemd/user && systemd-analyze --root=/ verify sparky-stereo-audio-apply.service sparky-stereo-audio-apply.path)"
printf '[Unit]\n[Service]\nExecStart=/nonexistent\n' > /tmp/bad.service
check "systemd: the control, a unit that must fail, fails" "! systemd-analyze verify /tmp/bad.service"
apt-get -y install udev >/dev/null 2>&1
check "udev: the rule verifies" "udevadm verify /usr/lib/udev/rules.d/71-sparky-stereo-audio.rules"
before=$(stat -c %Y $PW)
sleep 1.1
sparky-stereo-audio detect --write >/dev/null 2>&1
check "a second detect changes nothing (mtime)" "[ $(stat -c %Y $PW) = $before ]"
# a file of the person with the package's name
printf 'context.properties = { default.clock.rate = 96000 }\n' > $PW
out=$(sparky-stereo-audio detect --write 2>&1 >/dev/null)
check "a file of the person is left as it is" "[ \"\$(cat $PW)\" = 'context.properties = { default.clock.rate = 96000 }' ]"
check "and said" "echo \"\$out\" | grep -q 'is not the file this package wrote'"
check "the engine kept it" "sparky-stereo-problems list 2>/dev/null | grep -q sparky-stereo-audio"
apt-get -y remove sparky-stereo-audio >/tmp/remove.log 2>&1
check "remove: the package's files go" "[ ! -e $WP ] && [ ! -e /etc/pipewire/client.conf.d/00-sparky-stereo-audio.conf ]"
check "remove: the person's file stays" "[ \"\$(cat $PW)\" = 'context.properties = { default.clock.rate = 96000 }' ]"
check "remove: the problems of the package are cleared" "! sparky-stereo-problems list 2>/dev/null | grep -q sparky-stereo-audio"
rm -f $PW
apt-get -y install sparky-stereo-audio >/dev/null 2>&1
check "install again: the files are back" "head -n 1 $PW | grep -q '^# sparky-stereo-audio:'"
apt-get -y purge sparky-stereo-audio >/dev/null 2>&1
check "purge: files and state go" "[ ! -e $PW ] && [ ! -d /var/lib/sparky-stereo-audio ]"
echo "$FAILS failing"
exit $FAILS
