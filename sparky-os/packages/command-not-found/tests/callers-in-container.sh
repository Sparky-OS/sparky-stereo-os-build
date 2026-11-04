#!/bin/bash
# Sparky Stereo OS: command-not-found's renamed commands in every caller, red on today's packages and green on the candidates.
# Created by Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# Runs as root in a fresh Debian testing container; test-callers.sh starts it. /repo is the published edition tree,
# /cand the candidate .deb files, /tests this folder, /out the results. The probes run as the user tester (uid 1000, in
# the sudo group, as a desktop user is): bash, zsh and fish typing the command (with -i, and in a pty session), the real
# KRunner library (KRunner::RunnerManager with the default krunnerrc, krunner-query/), the runner's own D-Bus Match
# (activated by the session bus from its service file), and a Dolphin pack whose program is the command, with a
# stand-in kdialog that records the offer and a stand-in konsole that records what it is asked to run. Nothing reaches a
# display: no socket is mounted, Qt runs offscreen.
# fish sets up command-not-found only in an interactive shell, as a person's terminal is (fish -i). Every probe runs with
# PYTHONHASHSEED=0: command-not-found's spelling suggestions come from a set, whose order follows Python's string hash.
# The phases: red (today's packages), green (the candidates), installed (fd-find and task-spooler installed), missing
# (the table removed) and unreadable (the table at mode 000).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8
probe_commands="fd bat ts cal cmatrix docker wakeonlan python"
languages="en_US pl_PL pt_BR fr_FR de_DE ja_JP ko_KR zh_CN zh_TW"
TABLE=/usr/share/command-not-found/renamed-commands
# apt reads an armored key named .asc (sources.list(5), Signed-By)
cp /repo/sparky-stereo-repo.asc /usr/share/keyrings/sparky-stereo-test.asc
printf 'deb [signed-by=/usr/share/keyrings/sparky-stereo-test.asc] file:/repo mashtabba main\n' >/etc/apt/sources.list.d/edition.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' >/etc/apt/preferences.d/edition
# the edition's media stack sits on deb-multimedia (skill edition-packaging); plain HTTP, as the image has no CA store and apt checks the signature
printf 'deb [signed-by=/usr/share/keyrings/deb-multimedia-keyring.pgp] https://www.deb-multimedia.org forky main non-free\n' >/etc/apt/sources.list.d/multimedia.list
apt-get -y update >/out/apt-update-1.log 2>&1
apt-get -y install --no-install-recommends command-not-found sparky-stereo-console sparky-stereo-integration zsh fish dbus \
	python3-dbus python3-gi cmake g++ make libkf6runner-dev qt6-base-dev locales >/out/apt-install.log 2>&1
# glibc translates nothing in the C locales: each of the nine languages gets its real locale
for l in $languages; do localedef -i "$l" -f UTF-8 "$l.UTF-8"; done
cmake -S /tests/krunner-query -B /tmp/krunner-query >/out/krunner-query-build.log 2>&1
cmake --build /tmp/krunner-query >>/out/krunner-query-build.log 2>&1
# command-not-found's own apt hook fills its database from the Contents indexes apt-file enabled
apt-get -y update >/out/apt-update-2.log 2>&1
[ -s /var/lib/command-not-found/commands.db ]
useradd --create-home --uid 1000 --groups sudo tester
# a person who has started zsh once has a ~/.zshrc (zsh-newuser-install's choice 0, "a comment"); without it zsh's
# first-run menu takes the typed line in a pty session
printf '# Created by newuser for zsh\n' >/home/tester/.zshrc && chown tester: /home/tester/.zshrc
mkdir -p /usr/local/lib/stand-in /usr/share/sparky-stereo/integrations.d
cat >/usr/local/lib/stand-in/kdialog <<'X'
#!/bin/sh
# records each call; answers No, so nothing is installed and the hide option is declined
printf '%s\n' "$*" >>"$HOME/kdialog.log"
exit 1
X
cat >/usr/local/lib/stand-in/konsole <<'X'
#!/bin/sh
# records what the person's terminal is asked to run
printf '%s\n' "$*" >>"$HOME/konsole.log"
X
chmod 755 /usr/local/lib/stand-in/kdialog /usr/local/lib/stand-in/konsole
for c in $probe_commands; do
	printf 'program=%s\nworker=/bin/true\nmenus=\n' "$c" >/usr/share/sparky-stereo/integrations.d/j15-$c.conf
done
cp /tests/krunner-match.py /tmp/krunner-query/krunner-query /usr/local/lib/stand-in/
as_tester() { # the person's environment: their home, no display, one hash seed
	runuser -u tester -- env -i PYTHONHASHSEED=0 HOME=/home/tester TERM=dumb LANG=C.UTF-8 "$@"
}
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
krunner() { # phase file queries...: the real KRunner library and the runner's own D-Bus Match
	local d=$1 f=$2; shift 2
	as_tester PATH=/usr/local/lib/stand-in:/usr/bin:/bin QT_QPA_PLATFORM=offscreen \
		dbus-run-session -- /usr/local/lib/stand-in/krunner-query "$@" >"$d/$f-real.json" 2>"$d/$f-real.err"
	as_tester PATH=/usr/bin:/bin dbus-run-session -- python3 /usr/local/lib/stand-in/krunner-match.py "$@" \
		>"$d/$f-dbus.json" 2>"$d/$f-dbus.err"
}
shells() { # phase commands...: bash, zsh and fish with -i
	local d=$1 c sh; shift
	for c in "$@"; do
		for sh in bash zsh fish; do
			as_tester PATH=/usr/local/bin:/usr/bin:/bin "$sh" -i -c "$c" >"$d/$sh-$c.txt" 2>&1 </dev/null || true
		done
	done
}
probe() { # phase
	local d=/out/$1 c sh l
	mkdir -p "$d"
	dpkg-query -W -f '${Package} ${Version}\n' command-not-found sparky-stereo-integration sparky-stereo-console bash zsh fish >"$d/versions.txt"
	shells "$d" $probe_commands
	for c in $probe_commands; do
		rm -f /home/tester/kdialog.log
		as_tester PATH=/usr/local/lib/stand-in:/usr/bin:/bin WAYLAND_DISPLAY=j15-stand-in-no-display \
			sparky-stereo-integration run "j15-$c" -- /tmp/x >"$d/dolphin-$c.out" 2>&1 || true
		cp /home/tester/kdialog.log "$d/dolphin-$c.txt" 2>/dev/null || : >"$d/dolphin-$c.txt"
	done
	krunner "$d" krunner $probe_commands
	for sh in bash zsh fish; do
		for c in fd bat ts cal cmatrix; do
			# a pty session, as Konsole gives: the command typed, then exit
			printf '%s\nexit\n' "$c" | as_tester PATH=/usr/local/bin:/usr/bin:/bin timeout 60 script -qec "$sh -i" /dev/null \
				>"$d/pty-$sh-$c.txt" 2>&1 || true
		done
	done
	for l in $languages; do
		runuser -u tester -- env -i PYTHONHASHSEED=0 HOME=/home/tester PATH=/usr/bin:/bin LANG=$l.UTF-8 \
			/usr/lib/command-not-found -- fd >"$d/lang-$l.txt" 2>&1 || true
	done
	while read -r c; do
		printf '=== %s\n' "$c"
		as_tester PATH=/usr/bin:/bin /usr/lib/command-not-found -- "$c" 2>&1 || true
	done <"$d/../sample.txt" >"$d/sample-out.txt"
}
problem() { # phase: the table cannot be read
	local d=/out/$1 l
	mkdir -p "$d"
	as_tester PATH=/usr/bin:/bin /usr/lib/command-not-found -- fd >"$d/cnf-fd.txt" 2>&1 || true
	shells "$d" fd
	krunner "$d" krunner fd cmatrix
	for l in $languages; do
		runuser -u tester -- env -i PYTHONHASHSEED=0 HOME=/home/tester PATH=/usr/bin:/bin LANG=$l.UTF-8 \
			/usr/lib/command-not-found -- fd >"$d/lang-$l.txt" 2>&1 || true
	done
}
sample >/out/sample.txt
probe red
apt-get -y install --no-install-recommends /cand/*.deb >/out/apt-install-candidates.log 2>&1
probe green
# the renamed programs installed: command-not-found says so, and KRunner offers to run them
apt-get -y install --no-install-recommends fd-find task-spooler >/out/apt-install-renamed.log 2>&1
mkdir -p /out/installed
shells /out/installed fd ts
rm -f /home/tester/konsole.log
krunner /out/installed krunner 'fd -e txt' ts
as_tester PATH=/usr/local/lib/stand-in:/usr/bin:/bin QT_QPA_PLATFORM=offscreen \
	dbus-run-session -- /usr/local/lib/stand-in/krunner-query --run 'fd -e txt' >/out/installed/krunner-run.json 2>/out/installed/krunner-run.err
cp /home/tester/konsole.log /out/installed/konsole.log 2>/dev/null || : >/out/installed/konsole.log
apt-get -y purge fd-find task-spooler >/out/apt-purge-renamed.log 2>&1
# the table cannot be read: missing, then unreadable to the person
mv "$TABLE" "$TABLE.j15"
problem missing
mv "$TABLE.j15" "$TABLE"
chmod 000 "$TABLE"
problem unreadable
chmod 644 "$TABLE"
python3 /tests/check-callers.py /out /cand
