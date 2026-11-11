#!/bin/bash
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/09
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/10
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${OUT:?Set OUT to the workspace output directory}
VERSION=20261111.1~sparky9~0+lc1
PACKAGE=sparky-stereo-kernel-settings
DEPENDS='python3, apt, sparky-stereo-problems, libpam-modules, systemd, mount, udev'
FILES='etc/security/limits.d/20-sparky-audio.conf etc/tmpfiles.d/tmp.conf usr/lib/modules-load.d/sparky-stereo.conf usr/lib/sysctl.d/70-sparky-stereo.conf usr/lib/tmpfiles.d/sparky-thp.conf usr/lib/udev/rules.d/60-sparky-block.rules usr/lib/udev/rules.d/70-sparky-ntsync.rules usr/lib/udev/rules.d/99-sparky-audio.rules'
mkdir -p "$OUT"
WORK=$(mktemp -d "$OUT/.kernel-settings.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
D=$WORK/$PACKAGE
mkdir -p "$D/DEBIAN" "$D/usr/share/doc/$PACKAGE"
for f in $FILES; do install -Dm644 "$HERE/$f" "$D/$f"; done
install -m755 "$HERE/preinst" "$D/DEBIAN/preinst"
install -m644 "$HERE/copyright" "$D/usr/share/doc/$PACKAGE/copyright"
install -Dm755 "$HERE/usr/libexec/sparky-stereo/zram-migration" "$D/usr/libexec/sparky-stereo/zram-migration"
install -Dm755 "$HERE/usr/libexec/sparky-stereo/tmp-on-disk" "$D/usr/libexec/sparky-stereo/tmp-on-disk"
install -Dm644 "$HERE/README.md" "$D/usr/share/doc/$PACKAGE/README.md"
mkdir -p "$D/usr/lib/systemd/system/systemd-zram-setup@zram0.service.d" "$D/usr/lib/systemd/system/dev-zram0.swap.d"
cat >"$D/usr/lib/systemd/system/systemd-zram-setup@zram0.service.d/50-sparky-migration.conf" <<'EOF'
[Unit]
RequiresMountsFor=/var/lib/apt /var/lib/sparky-stereo-kernel-settings
# At boot this unit is started several times; on a machine where the guard skipped each start they ended in
# "start-limit-hit", a failure of a unit that was correctly doing nothing (station's journal, 2026-11-08).
StartLimitIntervalSec=0
[Service]
ExecCondition=/usr/libexec/sparky-stereo/zram-migration --allow
EOF
cat >"$D/usr/lib/systemd/system/dev-zram0.swap.d/50-sparky-migration.conf" <<'EOF'
[Unit]
# The generator orders this swap after its setup service, which evaluates the guard.
ConditionPathExists=!/run/sparky-stereo-kernel-settings/blocked-zram0
EOF
# ORDER 463: the leftover generator is removed once (after the apt run, or at the next boot), and a failed zram unit is told
# without the engine's generic Repair, which would start a unit the edition did not set up.
SYSTEMD=$D/usr/lib/systemd/system
cat >"$SYSTEMD/sparky-stereo-kernel-settings-zram-leftover.service" <<'EOF'
[Unit]
Description=Remove the compressed swap generator an older edition left installed (once)
Documentation=file:/usr/share/doc/sparky-stereo-kernel-settings/README.md
ConditionPathExists=/var/lib/sparky-stereo-kernel-settings/leftover-zram-generator

[Service]
Type=simple
ExecStart=/usr/libexec/sparky-stereo/zram-migration --purge-leftover
TimeoutStartSec=infinity
KillMode=process

[Install]
WantedBy=multi-user.target
EOF
mkdir -p "$SYSTEMD/multi-user.target.wants"
ln -s ../sparky-stereo-kernel-settings-zram-leftover.service "$SYSTEMD/multi-user.target.wants/sparky-stereo-kernel-settings-zram-leftover.service"
cat >"$SYSTEMD/sparky-stereo-kernel-settings-zram-failed@.service" <<'EOF'
[Unit]
Description=Say the failure of %i without offering to start it again

[Service]
Type=oneshot
ExecStart=/usr/libexec/sparky-stereo/zram-migration --failed %i
EOF
cat >"$SYSTEMD/systemd-zram-setup@zram0.service.d/60-sparky-zram-failure.conf" <<'EOF'
[Unit]
# The engine's generic handler (Repair: systemctl restart) is masked by name beside this one; see problems-engine-350.
OnFailure=sparky-stereo-kernel-settings-zram-failed@%n.service
EOF
ln -s /dev/null "$SYSTEMD/systemd-zram-setup@zram0.service.d/50-sparky-stereo-problems.conf"
sparky-stereo-problems catalog "$PACKAGE" "$HERE/problems-lang" "$D/usr/lib/systemd/catalog" --subject LOCAL1
SIZE=$(du -sk --exclude=DEBIAN "$D" | cut -f1)
cat >"$D/DEBIAN/control" <<EOT
Package: $PACKAGE
Version: $VERSION
Architecture: all
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
Installed-Size: $SIZE
Depends: $DEPENDS
Section: System
Priority: optional
Homepage: https://sparkylinux.org
Description: Kernel tunables for Sparky Stereo OS
  Sysctl, udev, tmpfiles, modules-load and audio-limit settings that replace
  kernel patches of performance kernels. Closes kexec after boot and excludes
  automatic compressed RAM swap; the person may opt in through Stereo APTus.
EOT
printf '%s\n' /etc/security/limits.d/20-sparky-audio.conf /etc/tmpfiles.d/tmp.conf >"$D/DEBIAN/conffiles"
cat >"$D/DEBIAN/postinst" <<'EOT'
#!/bin/sh
set -e
# /tmp on disk (Daniel), the way Debian's trixie release notes describe it (5.1.6: systemctl mask tmp.mount, then reboot).
# Once, when this version first arrives; an administrator's own tmp.mount is left alone, and unmasking it is respected.
if [ "$1" = configure ] && dpkg --compare-versions "${2:-0}" lt 20261010.2~sparky9~0 && [ ! -e /etc/systemd/system/tmp.mount ]; then
	systemctl mask tmp.mount >/dev/null 2>&1 || ln -s /dev/null /etc/systemd/system/tmp.mount
	mkdir -p /var/lib/sparky-stereo-kernel-settings
	: >/var/lib/sparky-stereo-kernel-settings/tmp-mount-masked
fi
if [ "$1" = configure ]; then
	/usr/libexec/sparky-stereo/tmp-on-disk
	# Stop/reset only the edition’s former Auto zram0, never a person’s choice.
	sparky-stereo-problems run --machine sparky-stereo-kernel-settings zram-migration LOCAL5 -- /usr/libexec/sparky-stereo/zram-migration --migrate || :
	# ORDER 463: a generator left by the old package is purged once when the person did not choose it; the apt run that is
	# configuring this package still holds the locks, so the unit waits for it
	if [ -f /var/lib/sparky-stereo-kernel-settings/leftover-zram-generator ] && [ -d /run/systemd/system ] && [ -z "${DPKG_ROOT:-}" ]; then
		systemctl --no-block start sparky-stereo-kernel-settings-zram-leftover.service || sparky-stereo-problems say sparky-stereo-kernel-settings LOCAL28
	fi
	if [ -f /var/lib/sparky-stereo-kernel-settings/retire-owned-zram0 ]; then
		cleanup='
set -e
active=$(awk '\''$1 == "/dev/zram0" { found=1 } END { print found+0 }'\'' /proc/swaps)
if [ "$active" = 1 ]; then
    if [ -d /run/systemd/system ]; then
        systemctl stop dev-zram0.swap
    fi
    # The service may already have stopped it; swapoff is needed without a manager.
    active=$(awk '\''$1 == "/dev/zram0" { found=1 } END { print found+0 }'\'' /proc/swaps)
    if [ "$active" = 1 ]; then
    swapoff /dev/zram0
    fi
fi
if [ -r /sys/block/zram0/disksize ] && [ "$(cat /sys/block/zram0/disksize)" != 0 ]; then
    printf "1\\n" >/sys/block/zram0/reset
fi
rm -f /var/lib/sparky-stereo-kernel-settings/retire-owned-zram0
'
		if sparky-stereo-problems run --machine sparky-stereo-kernel-settings retire-zram LOCAL5 -- /bin/sh -c "$cleanup"; then
			sparky-stereo-problems say sparky-stereo-kernel-settings LOCAL6
		fi
	fi
	# ORDER 358: installed settings remain configured after a failed live reload.
	# debhelper 14.5 autoscripts/postinst-systemd-restart similarly completes:
	# systemctl --system daemon-reload >/dev/null || true
	# We show and keep the failure instead. Policy 6 has no reload exception.
	# dh_installudev 14.5 installs rules but has no reload autoscript.
	if [ -z "${DPKG_ROOT:-}" ] && [ -S /run/udev/control ]; then
		sparky-stereo-problems run --machine sparky-stereo-kernel-settings udev-reload LOCAL2 -- udevadm control --reload || :
	else
		sparky-stereo-problems say sparky-stereo-kernel-settings LOCAL4
	fi
fi
EOT
cat >"$D/DEBIAN/postrm" <<'EOT'
#!/bin/sh
set -e
if [ "$1" = remove ] && command -v sparky-stereo-problems >/dev/null 2>&1; then
	sparky-stereo-problems clear --all sparky-stereo-kernel-settings
fi
if [ "$1" = purge ]; then
	rm -f /etc/apt/apt.conf.d/90sparky-stereo-chosen-zram
fi
if [ "$1" = purge ] && [ -e /var/lib/sparky-stereo-kernel-settings/tmp-mount-masked ]; then
	if [ "$(readlink /etc/systemd/system/tmp.mount 2>/dev/null)" = /dev/null ]; then
		rm -f /etc/systemd/system/tmp.mount
	fi
	rm -rf /var/lib/sparky-stereo-kernel-settings
fi
EOT
chmod 755 "$D/DEBIAN/postinst" "$D/DEBIAN/postrm"
(cd "$D" && find etc usr -type f -print0 | sort -z | xargs -0 md5sum >DEBIAN/md5sums)
PYTHONPATH="$HERE/../..${PYTHONPATH:+:$PYTHONPATH}" python3 -m lean.standalone "$D" "$OUT" --authoring "$HERE" --build-dependency sparky-stereo-problems
