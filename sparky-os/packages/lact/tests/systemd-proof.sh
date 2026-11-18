#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
# Proof under systemd, run as root inside a systemd container (docker run -d --cgroupns=private --security-opt writable-cgroups=true --tmpfs /run
# --tmpfs /tmp -v BUILD_OUT:/deb:ro IMAGE /lib/systemd/systemd; docker cp this file; docker exec CONTAINER bash systemd-proof.sh), with LACT_SNAPSHOT_DIR
# a recorded card of upstream (tests/snapshots/amd/rx5500xt of the source tarball) mounted at /snap/rx5500xt. No real card: the service
# reads a recorded one through `_LACT_DRM_SYSFS_PATH` (upstream's own test hook) set by a drop-in, the proof's only deviation from the shipped unit.
export DEBIAN_FRONTEND=noninteractive
rm -f /usr/sbin/policy-rc.d
sh /run/https-only-apt.sh >/dev/null
apt-get -y -qq update >/dev/null 2>&1
DEB=$(ls /deb/lact_*+lc1_amd64.deb)
st() { printf '  enabled=%s active=%s\n' "$(systemctl is-enabled lactd 2>&1)" "$(systemctl is-active lactd 2>&1)"; }
bump() { rm -rf /tmp/bump$1 && mkdir -p /tmp/bump$1 && dpkg-deb -R "$DEB" /tmp/bump$1/pkg && sed -i "s/^Version: .*/Version: 0.10.1-9$1+lc1/" /tmp/bump$1/pkg/DEBIAN/control && dpkg-deb -b /tmp/bump$1/pkg /tmp/bump$1/o.deb >/dev/null 2>&1; echo /tmp/bump$1/o.deb; }
mkdir -p /tmp/fakedrm && cp -a /snap/. /tmp/fakedrm/ && CARD=$(ls /tmp/fakedrm | head -1); echo "recorded card: amd/$CARD ($(ls /tmp/fakedrm/$CARD))"
dropin() { mkdir -p /etc/systemd/system/lactd.service.d; printf '[Service]\nEnvironment=_LACT_DRM_SYSFS_PATH=/tmp/fakedrm/%s\n' "$CARD" >/etc/systemd/system/lactd.service.d/10-recorded-card.conf; }
echo "== P1: installed by apt on a machine with the package alone"
dropin
apt-get -y --no-install-recommends install "$DEB" >/tmp/p1.log 2>&1; echo "install exit=$?"; grep -E "^(E:|W:)" /tmp/p1.log | head -3
systemctl daemon-reload; systemctl restart lactd; sleep 4; st
echo "  socket: $(ls -l /run/lactd.sock 2>&1 | awk '{print $1,$3,$NF}')"
echo "-- lact cli list (the recorded card):"; lact cli list 2>&1 | head -4 | cut -c1-160
echo "-- lact cli info:"; lact cli info 2>&1 | grep -iE "driver|vendor|device|vram|name" | head -5 | cut -c1-160
echo "-- journal:"; journalctl -u lactd --no-pager -o cat 2>&1 | tail -5 | cut -c1-180
echo "-- files: $(ls /etc/lact 2>&1 | tr '\n' ' ') | polkit action: $(ls /usr/share/polkit-1/actions/ | grep LACT)"
echo "== P2: the person's settings survive an upgrade (the package never writes them)"
mkdir -p /etc/lact; [ -f /etc/lact/config.yaml ] || lact cli profile list >/dev/null 2>&1; ls /etc/lact
echo "# written by the person" >> /etc/lact/config.yaml; S0=$(sha256sum /etc/lact/config.yaml | cut -c1-16)
NEW=$(bump 2); apt-get -y --no-install-recommends install "$NEW" >/tmp/p2.log 2>&1; echo "upgrade exit=$?"; sleep 3; st
echo "  config.yaml unchanged by the upgrade: $([ "$(sha256sum /etc/lact/config.yaml | cut -c1-16)" = "$S0" ] && echo yes || echo NO)"
echo "== P3: the person turns it off; an upgrade keeps it off"
systemctl disable --now lactd >/dev/null 2>&1; st
NEW3=$(bump 3); apt-get -y --no-install-recommends install "$NEW3" >/tmp/p3.log 2>&1; echo "upgrade exit=$?"; sleep 2; st
echo "== P4: removal keeps the settings, purge takes them"
apt-get -y remove lact >/tmp/p4.log 2>&1; echo "remove exit=$?"
echo "  program: $([ -e /usr/bin/lact ] && echo PRESENT || echo gone); unit: $([ -e /usr/lib/systemd/system/lactd.service ] && echo PRESENT || echo gone); /etc/lact: $([ -d /etc/lact ] && echo kept || echo GONE)"
apt-get -y purge lact >/tmp/p5.log 2>&1; echo "purge exit=$?"
echo "  /etc/lact: $([ -d /etc/lact ] && echo KEPT || echo gone); enable records: $(ls /var/lib/systemd/deb-systemd-helper-enabled 2>/dev/null | grep -c lactd); wants link: $(ls /etc/systemd/system/multi-user.target.wants 2>/dev/null | grep -c lactd)"
echo "== P5: installed again after a purge: on, as the first time"
apt-get -y --no-install-recommends install "$DEB" >/tmp/p6.log 2>&1; echo "install exit=$?"; systemctl daemon-reload; sleep 3; st
apt-get -y purge lact >/dev/null 2>&1; rm -rf /etc/systemd/system/lactd.service.d; systemctl daemon-reload
echo "== P6: a copy made by upstream's makefile (/usr/local), ours installed beside it"
mkdir -p /usr/local/bin /usr/local/lib/systemd/system /etc/lact
printf '#!/bin/sh\nexec sleep 3000\n' >/usr/local/bin/lact; chmod +x /usr/local/bin/lact
printf '[Unit]\nDescription=LACT GPU Control Daemon (upstream makefile copy)\n[Service]\nExecStart=/usr/local/bin/lact daemon\n[Install]\nWantedBy=multi-user.target\n' >/usr/local/lib/systemd/system/lactd.service
echo "# the person's settings, shared with the copy" >/etc/lact/config.yaml
systemctl daemon-reload; systemctl enable --now lactd >/dev/null 2>&1
PID0=$(systemctl show -p MainPID --value lactd); fp() { (sha256sum /usr/local/bin/lact /usr/local/lib/systemd/system/lactd.service /etc/lact/config.yaml; ls -l --time-style=+ /etc/systemd/system/multi-user.target.wants/lactd.service) | sha256sum | cut -c1-16; }
S0=$(fp); echo "  before: $(st | tr -d '\n') pid=$PID0 fingerprint=$S0 unit file: $(systemctl show -p FragmentPath --value lactd)"
apt-get -y --no-install-recommends install "$DEB" >/tmp/p7.log 2>&1; echo "install exit=$?"; grep -i "^lact:" /tmp/p7.log | head -2 | cut -c1-200
echo "  after our install: $(st | tr -d '\n') pid=$(systemctl show -p MainPID --value lactd) fingerprint=$(fp) unit file: $(systemctl show -p FragmentPath --value lactd)"
apt-get -y --no-install-recommends install "$NEW" >/tmp/p8.log 2>&1; echo "upgrade of ours exit=$?; copy: pid=$(systemctl show -p MainPID --value lactd) fingerprint=$(fp)"
apt-get -y remove lact >/dev/null 2>&1; echo "removal of ours: copy: $(st | tr -d '\n') pid=$(systemctl show -p MainPID --value lactd) fingerprint=$(fp)"
apt-get -y purge lact >/dev/null 2>&1; echo "purge of ours: copy: $(st | tr -d '\n') pid=$(systemctl show -p MainPID --value lactd) fingerprint=$(fp); /etc/lact: $([ -f /etc/lact/config.yaml ] && echo kept || echo GONE)"
[ "$(fp)" = "$S0" ] && [ "$(systemctl show -p MainPID --value lactd)" = "$PID0" ] && echo "RESULT P6: the copy made by upstream's makefile untouched through install, upgrade, removal and purge" || echo "RESULT P6: FAILED"
