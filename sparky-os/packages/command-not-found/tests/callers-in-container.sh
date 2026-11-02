#!/bin/bash
# Sparky Stereo OS: command-not-found's renamed commands in every caller, red on today's packages and green on the candidates.
# Created by Daniel Ramos (Capitain Jack) 2026/11/03
# Copyright 2026 under the GNU GPL3 License
# Runs as root in a fresh Debian testing container; test-callers.sh starts it. /repo is the published edition tree,
# /cand the candidate .deb files, /tests this folder, /out the results. The probes run as the user tester (uid 1000, in
# the sudo group, as a desktop user is): bash, zsh and fish typing the command (with -i, and in a pty session), the real
# KRunner library (KRunner::RunnerManager with the default krunnerrc, krunner-query/), the runner's own D-Bus Match
# (activated by the session bus from its service file), and a Dolphin pack whose program is the command, with a
# stand-in kdialog that records the offer. Nothing reaches a display: no socket is mounted, Qt runs offscreen.
# fish sets up command-not-found only in an interactive shell, as a person's terminal is (fish -i). Every probe runs with
# PYTHONHASHSEED=0: command-not-found's spelling suggestions come from a set, whose order follows Python's string hash.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8
probe_commands="fd bat cmatrix docker ts wakeonlan python"
# apt reads an armored key named .asc (sources.list(5), Signed-By)
cp /repo/sparky-stereo-repo.asc /usr/share/keyrings/sparky-stereo-test.asc
printf 'deb [signed-by=/usr/share/keyrings/sparky-stereo-test.asc] file:/repo mashtabba main\n' >/etc/apt/sources.list.d/edition.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' >/etc/apt/preferences.d/edition
# the edition's media stack sits on deb-multimedia (skill edition-packaging); plain HTTP, as the image has no CA store and apt checks the signature
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] http://www.deb-multimedia.org forky main non-free\n' >/etc/apt/sources.list.d/multimedia.list
apt-get -y update >/out/apt-update-1.log 2>&1
apt-get -y install --no-install-recommends command-not-found sparky-stereo-console sparky-stereo-integration zsh fish dbus \
	python3-dbus python3-gi cmake g++ make libkf6runner-dev qt6-base-dev >/out/apt-install.log 2>&1
cmake -S /tests/krunner-query -B /tmp/krunner-query >/out/krunner-query-build.log 2>&1
cmake --build /tmp/krunner-query >>/out/krunner-query-build.log 2>&1
# command-not-found's own apt hook fills its database from the Contents indexes apt-file enabled
apt-get -y update >/out/apt-update-2.log 2>&1
[ -s /var/lib/command-not-found/commands.db ]
useradd --create-home --uid 1000 --groups sudo tester
mkdir -p /usr/local/lib/stand-in /usr/share/sparky-stereo/integrations.d
cat >/usr/local/lib/stand-in/kdialog <<'X'
#!/bin/sh
# records each call; answers No, so nothing is installed and the hide option is declined
printf '%s\n' "$*" >>"$HOME/kdialog.log"
exit 1
X
chmod 755 /usr/local/lib/stand-in/kdialog
for c in $probe_commands; do
	printf 'program=%s\nworker=/bin/true\nmenus=\n' "$c" >/usr/share/sparky-stereo/integrations.d/j15-$c.conf
done
cp /tests/krunner-match.py /tmp/krunner-query/krunner-query /usr/local/lib/stand-in/
sample() { # the commands of the database not on this system, in a fixed sample, and words that are no command
	python3 - <<'PY'
import random, shutil, sqlite3
c = sqlite3.connect('/var/lib/command-not-found/commands.db')
names = sorted({r[0] for r in c.execute('select command from commands')})
random.seed(252)
pick = [n for n in random.sample(names, 400) if not shutil.which(n) and n.isprintable() and ' ' not in n][:300]
print('\n'.join(pick + ['j15nosuch%d' % i for i in range(20)] + ['fdx', 'batt', 'pyhton3']))
PY
}
probe() { # phase
	local phase=$1 d=/out/$1 c
	mkdir -p "$d"
	dpkg-query -W -f '${Package} ${Version}\n' command-not-found sparky-stereo-integration sparky-stereo-console bash zsh fish >"$d/versions.txt"
	for c in $probe_commands; do
		runuser -u tester -- env -i PYTHONHASHSEED=0 HOME=/home/tester PATH=/usr/local/bin:/usr/bin:/bin TERM=dumb LANG=C.UTF-8 bash -i -c "$c" >"$d/bash-$c.txt" 2>&1 </dev/null || true
		runuser -u tester -- env -i PYTHONHASHSEED=0 HOME=/home/tester PATH=/usr/local/bin:/usr/bin:/bin TERM=dumb LANG=C.UTF-8 zsh -i -c "$c" >"$d/zsh-$c.txt" 2>&1 </dev/null || true
		runuser -u tester -- env -i PYTHONHASHSEED=0 HOME=/home/tester PATH=/usr/local/bin:/usr/bin:/bin TERM=dumb LANG=C.UTF-8 fish -i -c "$c" >"$d/fish-$c.txt" 2>&1 </dev/null || true
		rm -f /home/tester/kdialog.log
		runuser -u tester -- env -i PYTHONHASHSEED=0 HOME=/home/tester PATH=/usr/local/lib/stand-in:/usr/bin:/bin LANG=C.UTF-8 \
			WAYLAND_DISPLAY=j15-stand-in-no-display sparky-stereo-integration run "j15-$c" -- /tmp/x >"$d/dolphin-$c.out" 2>&1 || true
		cp /home/tester/kdialog.log "$d/dolphin-$c.txt" 2>/dev/null || : >"$d/dolphin-$c.txt"
	done
	runuser -u tester -- env -i PYTHONHASHSEED=0 HOME=/home/tester PATH=/usr/bin:/bin LANG=C.UTF-8 \
		dbus-run-session -- python3 /usr/local/lib/stand-in/krunner-match.py $probe_commands >"$d/krunner.json" 2>"$d/krunner.err"
	runuser -u tester -- env -i PYTHONHASHSEED=0 HOME=/home/tester PATH=/usr/bin:/bin LANG=C.UTF-8 QT_QPA_PLATFORM=offscreen \
		dbus-run-session -- /usr/local/lib/stand-in/krunner-query $probe_commands >"$d/krunner-real.json" 2>"$d/krunner-real.err"
	for sh in bash zsh fish; do
		for c in fd bat cmatrix; do
			# a pty session, as Konsole gives: the command typed, then exit
			printf '%s\nexit\n' "$c" | runuser -u tester -- env -i PYTHONHASHSEED=0 HOME=/home/tester PATH=/usr/local/bin:/usr/bin:/bin \
				TERM=dumb LANG=C.UTF-8 timeout 60 script -qec "$sh -i" /dev/null >"$d/pty-$sh-$c.txt" 2>&1 || true
		done
	done
	for l in en pl pt_BR fr de ja ko zh_CN zh_TW; do
		runuser -u tester -- env -i PYTHONHASHSEED=0 HOME=/home/tester PATH=/usr/bin:/bin LANG=C.UTF-8 LANGUAGE=$l /usr/lib/command-not-found -- fd >"$d/lang-$l.txt" 2>&1 || true
	done
	while read -r c; do
		printf '=== %s\n' "$c"
		runuser -u tester -- env -i PYTHONHASHSEED=0 HOME=/home/tester PATH=/usr/bin:/bin LANG=C.UTF-8 /usr/lib/command-not-found -- "$c" 2>&1 || true
	done <"$d/../sample.txt" >"$d/sample-out.txt"
}
sample >/out/sample.txt
probe red
apt-get -y install --no-install-recommends /cand/*.deb >/out/apt-install-candidates.log 2>&1
probe green
python3 /tests/check-callers.py /out /cand
