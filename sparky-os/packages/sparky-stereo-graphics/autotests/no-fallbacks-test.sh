#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
#
# ORDER 346a: every way a GPU choice or a step of the package can fail is said and kept, never replaced by another
# GPU (Daniel, 2026-11-01: "either it works or not and the user must know"). Black box: the command line, the wrapper,
# the session script, the maintainer scripts and the notifier, so the same checks run against an older build (red)
# and this one (green).
# BIN: folder with sparky-stereo-gpu-env, sparky-stereo-gpu-record and makefixture. SRC: the package source (its
# scripts). DEBIAN: the folder of the maintainer scripts (default SRC/share/debian). U22, U23, U24, U26, U52 are the
# rows of ORDER 343's audit.
set -u
BIN=${BIN:?}
SRC=${SRC:?}
DEBIAN=${DEBIAN:-$SRC/share/debian}
T=$(mktemp -d)
trap 'kill $BUS 2>/dev/null; rm -rf "$T"' EXIT
pass=0 fail=0
check() { # name got expected
	if [ "$2" = "$3" ]; then pass=$((pass + 1)); echo "PASS $1"; else fail=$((fail + 1)); echo "FAIL $1: got '$2', expected '$3'"; fi
}
has() { # name file text: the file holds the text
	if grep -qF -- "$3" "$2"; then pass=$((pass + 1)); echo "PASS $1"; else fail=$((fail + 1)); echo "FAIL $1: '$3' not in: $(head -c 600 "$2")"; fi
}
for m in one host bmc; do "$BIN/makefixture" $m "$T/$m" || { echo "makefixture $m failed"; exit 1; }; done
# the workstation with its NVIDIA card on the PCI bus but no DRM device: its driver gave it none (nvidia bound, no
# nvidia-drm), and the same with no driver bound at all
for v in nodrm nodriver; do
	cp -a "$T/host" "$T/host-$v"
	rm -rf "$T/host-$v"/sys/class/drm/card1 "$T/host-$v"/sys/class/drm/card1-*
	# the copied links point into the original tree: point them at this copy
	for l in "$T/host-$v"/sys/class/drm/card0/device "$T/host-$v"/sys/bus/pci/devices/*; do
		t=$(readlink "$l"); ln -sfn "$T/host-$v${t#"$T/host"}" "$l"
	done
done
rm -f "$T/host-nodriver"/sys/devices/pci0000:00/0000:00:01.1/0000:01:00.0/driver
# the workstation where the account may not open the NVIDIA card's render node
cp -a "$T/host" "$T/host-denied"
for l in "$T/host-denied"/sys/class/drm/card*/device "$T/host-denied"/sys/bus/pci/devices/*; do
	t=$(readlink "$l"); ln -sfn "$T/host-denied${t#"$T/host"}" "$l"
done
chmod 000 "$T/host-denied/dev/dri/renderD129"
export XDG_CONFIG_HOME=$T/config XDG_CONFIG_DIRS=$T/none XDG_DATA_HOME=$T/data XDG_DATA_DIRS=$T/usr XDG_STATE_HOME=$T/state
# no system bus: the power profile cannot be read unless it is given
export DBUS_SYSTEM_BUS_ADDRESS=unix:path=$T/no-system-bus LANG=C.UTF-8
unset LANGUAGE LC_ALL LC_MESSAGES WAYLAND_DISPLAY DISPLAY DRI_PRIME MESA_VK_DEVICE_SELECT VK_LOADER_DRIVERS_SELECT __NV_PRIME_RENDER_OFFLOAD
mkdir -p "$XDG_CONFIG_HOME" "$T/none"
CFG=$XDG_CONFIG_HOME/sparky-stereo-graphicsrc
PROBLEMS=$XDG_STATE_HOME/sparky-stereo-graphics/problems
save() { printf '%b' "$1" >"$CFG"; }
env_for() { SPARKY_STEREO_GRAPHICS_ROOT=$T/$1 "$BIN/sparky-stereo-gpu-env" "${@:2}"; }
rc_of() { "$@" >"$T/out" 2>"$T/err"; echo $?; }

echo "== U52: a chosen GPU that cannot be used is said, never replaced"
check "an address that is not here: exit 4" "$(rc_of env_for host --choice pci-0000:09:00.0 --profile balanced)" 4
check "an address that is not here: no variables for another GPU" "$(cat "$T/out")" ""
has "an address that is not here: said" "$T/err" "at PCI address 0000:09:00.0, is not in this computer now"
has "an address that is not here: the GPUs that can draw are offered" "$T/err" "pci-0000:01:00.0  NVIDIA GeForce RTX 3060 Lite Hash Rate"
has "an address that is not here: how to start on one" "$T/err" "sparky-stereo-gpu-run --choice ID COMMAND"
save '[Render]\nGames=pci-0000:09:00.0\n'
check "a saved choice for games that is not here: exit 4" "$(rc_of env_for host --category games --profile balanced)" 4
check "a saved choice for games that is not here: kept" "$(python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["kind"], d["requested"])' "$PROBLEMS/games.json" 2>&1)" "gpu-missing pci-0000:09:00.0"
save '[Render]\nGames=discrete\n'
check "the choice works again: exit 0" "$(rc_of env_for host --category games --profile balanced)" 0
check "the choice works again: its record goes" "$(test -e "$PROBLEMS/games.json"; echo $?)" 1
save '[Render]\nPlayers=pci-0000:01:00.0\n'
check "one GPU left, the chosen one gone: exit 4, not \"the only GPU\"" "$(rc_of env_for one --category players --profile balanced --print reason)" 4
save '[Render]\nGames=discrete\n'
check "one GPU left, Discrete chosen: exit 4" "$(rc_of env_for one --category games --profile balanced)" 4
has "one GPU left, Discrete chosen: said" "$T/err" "You chose the discrete GPU for games, and this computer has none that can draw now."
check "a display chip that cannot draw: exit 4" "$(rc_of env_for bmc --choice pci-0000:04:00.0 --profile balanced)" 4
has "a display chip that cannot draw: said" "$T/err" "cannot draw now: its driver, ast, gives it no render node."
check "the NVIDIA card with no graphics device: exit 4" "$(rc_of env_for host-nodrm --choice pci-0000:01:00.0 --profile balanced)" 4
has "the NVIDIA card with no graphics device: said" "$T/err" "is in this computer, but its driver, nvidia, gives it no graphics device."
check "the NVIDIA card with no driver: exit 4" "$(rc_of env_for host-nodriver --choice pci-0000:01:00.0 --profile balanced)" 4
has "the NVIDIA card with no driver: said" "$T/err" "is in this computer, but no graphics driver is loaded for it."
# in the person's language (the German catalogue, as installed)
mkdir -p "$T/usr/locale/de/LC_MESSAGES"
msgfmt -o "$T/usr/locale/de/LC_MESSAGES/kcm_sparkystereo_graphics.mo" "$SRC/po/de/kcm_sparkystereo_graphics.po"
check "said in German" "$(LANG=de_DE.UTF-8 env_for host --choice pci-0000:09:00.0 --profile balanced 2>&1 >/dev/null | grep -c 'an der PCI-Adresse 0000:09:00.0, ist jetzt nicht in diesem Computer.')" 1
# another kind of device at the chosen address (a disk controller took the slot): the GPU is not in the computer
cp -a "$T/host-nodriver" "$T/host-other"
for l in "$T/host-other"/sys/class/drm/card0/device "$T/host-other"/sys/bus/pci/devices/*; do
	t=$(readlink "$l"); ln -sfn "$T/host-other${t#"$T/host-nodriver"}" "$l"
done
echo 0x010601 >"$T/host-other/sys/devices/pci0000:00/0000:00:01.1/0000:01:00.0/class"
check "another kind of device at that address: exit 4" "$(rc_of env_for host-other --choice pci-0000:01:00.0 --profile balanced)" 4
has "another kind of device at that address: the GPU is not here" "$T/err" "at PCI address 0000:01:00.0, is not in this computer now."
check "a render node the account may not open: exit 4" "$(rc_of env_for host-denied --choice discrete --profile balanced)" 4
has "a render node the account may not open: said" "$T/err" "cannot be used by your account: /dev/dri/renderD129 cannot be opened."
rm -f "$CFG"

echo "== U24: a power profile that cannot be read is said, never Balanced"
# Automatic is a rule, not the person's choice (ORDER 346g): it cannot place browsers then, said and kept, exit status 5, so
# Plasma's launcher never refuses a program the person placed nowhere
check "browsers on Automatic without a readable profile: exit 5" "$(rc_of env_for host --category browsers --print gpu)" 5
has "browsers on Automatic without a readable profile: said" "$T/err" "follows the power profile, and the power profile could not be read: the system bus cannot be reached."
check "browsers on Automatic without a readable profile: kept" "$(python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["kind"], d["requested"])' "$PROBLEMS/browsers.json" 2>&1)" "profile-unreadable auto"
# as Plasma's launcher asks for an entry outside the menu: by its desktop file
printf '[Desktop Entry]\nType=Application\nName=Browser\nExec=true\nCategories=Network;WebBrowser;\n' >"$T/browser.desktop"
check "a browser's entry on Automatic without a readable profile: exit 5" "$(rc_of env_for host --app "$T/browser.desktop")" 5
save '[Render]\nBrowsers=profile\n'
check "browsers the person set to follow the power profile, unreadable: exit 4" "$(rc_of env_for host --category browsers --print gpu)" 4
has "browsers the person set to follow the power profile, unreadable: said" "$T/err" "follows the power profile, and the power profile could not be read: the system bus cannot be reached."
rm -f "$CFG"
check "an explicit profile is honoured" "$(env_for host --category browsers --profile performance --print gpu 2>&1)" "NVIDIA GeForce RTX 3060 Lite Hash Rate"
check "a profile name that is none: a wrong argument" "$(rc_of env_for host --category browsers --profile turbo)" 2
check "SPARKY_STEREO_POWER_PROFILE that is none, browsers on Automatic: exit 5" "$(rc_of env SPARKY_STEREO_POWER_PROFILE=turbo SPARKY_STEREO_GRAPHICS_ROOT=$T/host "$BIN/sparky-stereo-gpu-env" --category browsers)" 5
has "SPARKY_STEREO_POWER_PROFILE that is none: said" "$T/err" "SPARKY_STEREO_POWER_PROFILE is turbo, which is not a power profile"
check "other programs need no profile" "$(env_for host --category other --print reason 2>&1)" desktop

echo "== U22: the wrapper starts nothing on another GPU"
RUN=$SRC/share/sparky-stereo-gpu-run
wrapped() { (export PATH=$BIN:$PATH SPARKY_STEREO_GRAPHICS_ROOT=$T/host SPARKY_STEREO_POWER_PROFILE=balanced; sh "$RUN" "$@"); }
save '[Render]\nGames=pci-0000:09:00.0\n'
check "a saved GPU that is not here: the program does not start" "$(wrapped --category games printf ran 2>"$T/err"; echo " rc=$?")" " rc=4"
has "a saved GPU that is not here: said" "$T/err" "at PCI address 0000:09:00.0, is not in this computer now"
has "a saved GPU that is not here: the program was not started" "$T/err" "The program was not started."
check "the program was not started, in German" "$( (export LANG=de_DE.UTF-8; wrapped --category games printf ran 2>&1 >/dev/null) | grep -c 'Das Programm wurde nicht gestartet.')" 1
mkdir -p "$T/failing" "$T/ask"
printf '#!/bin/sh\necho "the resolver broke" >&2\nexit 3\n' >"$T/failing/sparky-stereo-gpu-env"
chmod +x "$T/failing/sparky-stereo-gpu-env"
check "a resolver that fails: the program does not start" "$( (export PATH=$T/failing:/usr/bin:/bin; sh "$RUN" --category games printf ran 2>"$T/err"; echo " rc=$?") )" " rc=3"
has "a resolver that fails: said" "$T/err" "sparky-stereo-gpu-env failed (exit status 3)"
has "a resolver that fails: its own words too" "$T/err" "the resolver broke"
check "Automatic cannot place a browser: the wrapper starts nothing either" "$( (export PATH=$BIN:$PATH SPARKY_STEREO_GRAPHICS_ROOT=$T/host; unset SPARKY_STEREO_POWER_PROFILE; sh "$RUN" --category browsers printf ran 2>"$T/err"; echo " rc=$?") )" " rc=4"
has "Automatic cannot place a browser: the wrapper says it was not started" "$T/err" "The program was not started."
check "no resolver: the program does not start" "$( (export PATH=/usr/bin:/bin; sh "$RUN" --category games printf ran 2>"$T/err"; echo " rc=$?") )" " rc=127"
has "no resolver: said" "$T/err" "sparky-stereo-gpu-env is missing"
check "--choice: a GPU the person names, this start" "$(wrapped --choice pci-0000:01:00.0 env 2>&1 | grep -c '^__NV_PRIME_RENDER_OFFLOAD=1$')" 1
# with a display, the person is asked which GPU that can draw the program starts on, this time
printf '#!/bin/sh\nprintf "%%s\\n" "$@" >"%s/kdialog-args"\necho pci-0000:01:00.0\n' "$T" >"$T/ask/kdialog"
chmod +x "$T/ask/kdialog"
check "asked: the person's answer starts it there" "$( (export PATH=$T/ask:$BIN:$PATH WAYLAND_DISPLAY=wayland-test SPARKY_STEREO_GRAPHICS_ROOT=$T/host SPARKY_STEREO_POWER_PROFILE=balanced; sh "$RUN" --category games env 2>/dev/null | grep -c '^__NV_PRIME_RENDER_OFFLOAD=1$') )" 1
has "asked: a choice among the GPUs that can draw" "$T/kdialog-args" "--radiolist"
has "asked: the NVIDIA card offered" "$T/kdialog-args" "pci-0000:01:00.0"
has "asked: the AMD GPU offered" "$T/kdialog-args" "pci-0000:0b:00.0"
check "asked: the saved choice stays as it was" "$(grep -c '^Games=pci-0000:09:00.0$' "$CFG")" 1
printf '#!/bin/sh\nexit 1\n' >"$T/ask/kdialog"
check "asked and not answered: the program does not start" "$( (export PATH=$T/ask:$BIN:$PATH WAYLAND_DISPLAY=wayland-test SPARKY_STEREO_GRAPHICS_ROOT=$T/host SPARKY_STEREO_POWER_PROFILE=balanced; sh "$RUN" --category games printf ran 2>/dev/null; echo " rc=$?") )" " rc=4"
rm -f "$CFG"

echo "== U23: the session says and keeps a main GPU that cannot draw"
SESSION=$SRC/share/plasma-env/sparky-stereo-graphics.sh
session() { # root savedmain
	(
		unset KWIN_DRM_DEVICES
		export PATH=$BIN:$PATH SPARKY_STEREO_GRAPHICS_ROOT=$T/$1
		save "[General]\nMainGpu=$2\n"
		. "$SESSION"
		echo "${KWIN_DRM_DEVICES:-unset}"
	)
}
check "a main GPU that is not here: KWin's own order draws this login" "$(session host pci-0000:09:00.0 2>"$T/err")" unset
has "a main GPU that is not here: said in the session's log" "$T/err" "The GPU you chose to draw the desktop, at PCI address 0000:09:00.0, is not in this computer now."
check "a main GPU that is not here: kept for the notification" "$(python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["kind"], [a["id"] for a in d["alternatives"]])' "$PROBLEMS/main-gpu.json" 2>&1)" "gpu-missing ['pci-0000:0b:00.0', 'pci-0000:01:00.0']"
check "a main GPU that is here: applied" "$(session host pci-0000:01:00.0 2>/dev/null)" "/dev/dri/card1:/dev/dri/card0"
check "a main GPU that is here: its record goes" "$(test -e "$PROBLEMS/main-gpu.json"; echo $?)" 1
mkdir -p "$T/pkg"
printf '#!/bin/sh\necho installed\n' >"$T/pkg/dpkg-query"
chmod +x "$T/pkg/dpkg-query"
check "the package installed and its command gone: nothing set" "$( (unset KWIN_DRM_DEVICES; export PATH=$T/pkg:/usr/bin:/bin; . "$SESSION" 2>"$T/err"; echo "${KWIN_DRM_DEVICES:-unset}") )" unset
has "the package installed and its command gone: said" "$T/err" "sparky-stereo-gpu-env is missing"
check "the package installed and its command gone, in German" "$( (unset KWIN_DRM_DEVICES; export PATH=$T/pkg:/usr/bin:/bin LANG=de_DE.UTF-8; . "$SESSION" 2>&1 >/dev/null) | grep -c 'sparky-stereo-gpu-env fehlt')" 1
rm -f "$CFG"

echo "== U26: the maintainer scripts fail or keep what fails"
mkdir -p "$T/stub" "$T/dpkgroot/run/systemd/system"
cat >"$T/stub/sparky-stereo-gpu-record" <<STUB
#!/bin/sh
echo "\$*" >>"$T/record-calls"
case "\$*" in *--apply-known*) [ -z "\${RECORD_FAILS:-}" ] || { echo "sparky-stereo-gpu-record: the record cannot be written" >&2; exit 3; } ;; esac
exit 0
STUB
printf '#!/bin/sh\necho "Failed to reload daemon: Access denied" >&2\nexit 1\n' >"$T/stub/systemctl"
chmod +x "$T/stub/sparky-stereo-gpu-record" "$T/stub/systemctl"
maint() { (export PATH=$T/stub:/usr/bin:/bin DPKG_ROOT=$T/dpkgroot; sh "$DEBIAN/$1" "${@:2}"); }
check "postinst: a record that cannot be written fails the configuration" "$(RECORD_FAILS=1 maint postinst configure 0.2.2 2>"$T/err"; echo $?)" 3
has "postinst: the record's failure is said" "$T/err" "the record cannot be written"
rm -f "$T/record-calls"
check "postinst: a failed systemd reload lets the package configure" "$(maint postinst configure 0.2.2 2>"$T/err"; echo $?)" 0
has "postinst: systemd's own words are shown" "$T/err" "Failed to reload daemon: Access denied"
has "postinst: the failed reload is kept" "$T/record-calls" "--keep systemd-reload --status 1"
check "prerm: a record that cannot be removed fails the removal" "$(RECORD_FAILS=1 maint prerm remove 2>"$T/err"; echo $?)" 3
has "prerm: said" "$T/err" "the record cannot be written"
mkdir -p "$T/dpkgroot/var/lib/sparky-stereo-graphics/problems"
check "postrm purge: the machine's kept problems go" "$(maint postrm purge 2>/dev/null; test -e "$T/dpkgroot/var/lib/sparky-stereo-graphics"; echo $?)" 1
# the real record tool on the A10's identity and controllers, whose shipped record must be written: a folder it cannot
# write is said and kept
"$BIN/makefixture" a10 "$T/a10" || exit 1
mkdir -p "$T/a10/etc" && chmod 555 "$T/a10/etc"
check "gpu-record: the A10's record it cannot write exits 3" "$("$BIN/sparky-stereo-gpu-record" --root "$T/a10" --machines "$SRC/share/machines" --apply-known >/dev/null 2>"$T/err"; echo $?)" 3
has "gpu-record: said" "$T/err" "could not be written. Until it is, Automatic treats this computer as not measured."
check "gpu-record: kept for the sessions and the page" "$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["kind"])' "$T/a10/var/lib/sparky-stereo-graphics/problems/machine-record.json" 2>&1)" record-write
chmod 755 "$T/a10/etc"
check "gpu-record: written at last, the problem goes" "$("$BIN/sparky-stereo-gpu-record" --root "$T/a10" --machines "$SRC/share/machines" --apply-known; test -e "$T/a10/var/lib/sparky-stereo-graphics/problems/machine-record.json"; echo $?)" "written
1"

echo "== the notification at login offers the GPUs that can draw, as the person's choice"
cat >"$T/bus.conf" <<CONF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN" "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig><type>session</type><listen>unix:path=$T/session-bus</listen><auth>EXTERNAL</auth>
<policy context="default"><allow send_destination="*" eavesdrop="true"/><allow eavesdrop="true"/><allow own="*"/></policy></busconfig>
CONF
dbus-daemon --config-file="$T/bus.conf" --nofork >"$T/bus.log" 2>&1 &
BUS=$!
for i in $(seq 1 50); do [ -S "$T/session-bus" ] && break; sleep 0.1; done
export DBUS_SESSION_BUS_ADDRESS=unix:path=$T/session-bus XDG_RUNTIME_DIR=$T/runtime
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
rm -rf "$PROBLEMS"
save '[General]\nMainGpu=pci-0000:09:00.0\n'
env_for host --session >/dev/null 2>&1
python3 -I "$SRC/autotests/fake-notifications.py" "$T/notified.json" "use:pci-0000:01:00.0" >"$T/fake.log" 2>&1 &
FAKE=$!
for i in $(seq 1 50); do grep -q ready "$T/fake.log" && break; sleep 0.1; done
check "notify: exit 0 once the person chose" "$(SPARKY_STEREO_GRAPHICS_ROOT=$T/host timeout 20 "$BIN/sparky-stereo-gpu-env" --notify >/dev/null 2>"$T/err"; echo $?)" 0
kill $FAKE 2>/dev/null; wait $FAKE 2>/dev/null
check "notify: shown once, critical" "$(python3 -I -c 'import json,sys; n=json.load(open(sys.argv[1])); print(len(n), n[0]["urgency"])' "$T/notified.json" 2>&1)" "1 2"
check "notify: the title" "$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))[0]["summary"])' "$T/notified.json" 2>&1)" "A graphics choice cannot be used"
has "notify: what failed" "$T/notified.json" "is not in this computer now"
check "notify: each GPU that can draw is an action" "$(python3 -I -c 'import json,sys; a=json.load(open(sys.argv[1]))[0]["actions"]; print(a[0::2])' "$T/notified.json" 2>&1)" "['default', 'use:pci-0000:0b:00.0', 'use:pci-0000:01:00.0', 'open']"
check "notify: the person's answer is their new choice" "$(grep -c '^MainGpu=pci-0000:01:00.0$' "$CFG")" 1
check "notify: the problem it answered goes" "$(test -e "$PROBLEMS/main-gpu.json"; echo $?)" 1
check "notify: nothing new, nothing shown again" "$(SPARKY_STEREO_GRAPHICS_ROOT=$T/host timeout 20 "$BIN/sparky-stereo-gpu-env" --notify; echo $?)" 0
rm -f "$CFG"

echo "no-fallbacks: $pass passed, $fail failed"
[ "$fail" = 0 ]
