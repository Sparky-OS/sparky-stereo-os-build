#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/17
# Copyright 2026 under the GNU GPL3 License
# Proof under systemd, run inside a systemd container as root (docker run -d --cgroupns=private --security-opt writable-cgroups=true --tmpfs /run --tmpfs /tmp
#   -v BUILD_OUT:/deb:ro -v https-only-apt.sh:/run/https-only-apt.sh:ro -v ca-certificates.crt:/run/host-ca.crt:ro IMAGE /lib/systemd/systemd; docker exec CONTAINER bash systemd-proof.sh).
# Installs the built package by apt, checks the unit, the user, the web page, the state, an upgrade that keeps a changed default, the
# disable kept across an upgrade, removal and purge, and a fake upstream /opt/OpenLinkHub install that must stay untouched. No real device.
# inside the systemd container (root): OpenLinkHub installed by apt, run as its user, upgraded, removed, purged; then beside a fake upstream /opt install
export DEBIAN_FRONTEND=noninteractive
rm -f /usr/sbin/policy-rc.d
sh /run/https-only-apt.sh >/dev/null
apt-get -y -qq update >/dev/null 2>&1
apt-get -y -qq --no-install-recommends install curl >/dev/null 2>&1
# the container's /sys is read-only, so systemd-udevd cannot run and the unit's three udevadm steps (upstream's own, kept) cannot succeed here:
# this drop-in, the proof's only deviation from the shipped unit, leaves them out
mkdir -p /etc/systemd/system/OpenLinkHub.service.d
printf '[Service]\nExecStartPre=\nExecStartPre=/usr/libexec/openlinkhub/openlinkhub-seed\n' >/etc/systemd/system/OpenLinkHub.service.d/10-container-no-udev.conf
DEB=$(ls /deb/openlinkhub_*+lc1_amd64.deb)
st() { printf '  enabled=%s active=%s user=%s\n' "$(systemctl is-enabled OpenLinkHub 2>&1)" "$(systemctl is-active OpenLinkHub 2>&1)" "$(ps -o user= -p "$(systemctl show -p MainPID --value OpenLinkHub)" 2>/dev/null | tr -d ' ')"; }
web() { for i in $(seq 1 40); do c=$(curl -s -o /tmp/page.html -w '%{http_code}' http://127.0.0.1:27003/ 2>/dev/null); [ "$c" = 200 ] && break; sleep 1; done; echo "  web page http://127.0.0.1:27003/ -> $c after ${i}s, $(wc -c </tmp/page.html) bytes, title: $(grep -o '<title>[^<]*' /tmp/page.html | head -1)"; }
bump() { # N: a copy of the package with version -N and changed default profiles
  rm -rf /tmp/bump$1 && mkdir -p /tmp/bump$1 && dpkg-deb -R "$DEB" /tmp/bump$1/pkg
  sed -i "s/^Version: .*/Version: 0.9.4-$1+lc1/" /tmp/bump$1/pkg/DEBIAN/control
  D=/tmp/bump$1/pkg/usr/share/openlinkhub/database
  [ "$1" = 2 ] && { for f in $FILES; do printf '\n' >>$D/$f; done; cp $D/$B $D/zz-new-default.json; }
  dpkg-deb -b /tmp/bump$1/pkg /tmp/bump$1/o.deb >/dev/null 2>&1; echo /tmp/bump$1/o.deb
}
FILES=$(cd /usr/share/openlinkhub 2>/dev/null; true)
echo "== P1: installed by apt on a machine with the package alone"
apt-get -y --no-install-recommends install "$DEB" >/tmp/p1.log 2>&1; echo "install exit=$?"; grep -E "^(E:|W:)" /tmp/p1.log | head -5
id openlinkhub; ls -ld /var/lib/openlinkhub; sleep 3; st; web
echo "-- state folder:"; ls -la /var/lib/openlinkhub | sed 's/^/    /'; ls /var/lib/openlinkhub/database | head -20 | tr '\n' ' '; echo; echo "  database files: $(find /var/lib/openlinkhub/database -type f | wc -l) copied of $(find /usr/share/openlinkhub/database -type f | wc -l)"
echo "-- journal:"; journalctl -u OpenLinkHub --no-pager -o cat 2>&1 | head -12 | cut -c1-200
MP=$(systemctl show -p MainPID --value OpenLinkHub); echo "-- the program: pid $MP, exe $(readlink /proc/$MP/exe), working folder $(readlink /proc/$MP/cwd), uid $(awk '/^Uid/{print $2}' /proc/$MP/status), cgroup: $(systemctl show -p ControlGroup --value OpenLinkHub)"
echo "-- udev: $(ls -l /usr/lib/udev/rules.d/99-openlinkhub.rules | awk '{print $1,$3,$9}'); sysusers: $(cat /usr/lib/sysusers.d/openlinkhub.conf)"
echo "== P2: the person edits profile A, deletes profile C; the next version changes A, B, C and adds D"
P=/var/lib/openlinkhub/database; set -- $(cd $P && find . -type f ! -name .gitkeep | sed "s|^\./||" | sort | sed -n "2,4p"); A=$1; B=$2; C=$3; FILES="$A $B $C"
echo '{"edited":"by the person"}' >$P/$A; rm -f $P/$C; cp $P/$B /tmp/B.before
echo "  A=$A (edited) B=$B (untouched) C=$C (deleted)"
NEW=$(bump 2); apt-get -y --no-install-recommends install "$NEW" >/tmp/p2.log 2>&1; echo "upgrade exit=$?"; sleep 3; st; web
echo "  A still the person's: $(cat $P/$A)"; echo "  B replaced by the newer default: $(cmp -s $P/$B /usr/share/openlinkhub/database/$B && echo yes || echo NO) (was different from before: $(cmp -s /tmp/B.before $P/$B && echo no || echo yes))"; echo "  C still absent: $([ ! -e $P/$C ] && echo yes || echo NO)"; echo "  D copied: $([ -e $P/zz-new-default.json ] && echo yes || echo NO)"
journalctl -u OpenLinkHub --no-pager -o cat 2>&1 | grep seed | tail -2
echo "== P3: the person turns it off; an upgrade keeps it off"
systemctl disable --now OpenLinkHub >/dev/null 2>&1; st
NEW3=$(bump 3); apt-get -y --no-install-recommends install "$NEW3" >/tmp/p3.log 2>&1; echo "upgrade exit=$?"; sleep 2; st
echo "== P4: removal keeps the state, purge takes it (the user stays)"
apt-get -y remove openlinkhub >/tmp/p4.log 2>&1; echo "remove exit=$?"
echo "  program: $([ -e /usr/bin/OpenLinkHub ] && echo PRESENT || echo gone); unit: $([ -e /usr/lib/systemd/system/OpenLinkHub.service ] && echo PRESENT || echo gone); state folder: $([ -d /var/lib/openlinkhub ] && echo kept || echo GONE) (A: $(cat $P/$A 2>/dev/null)); user: $(id -un openlinkhub 2>&1); web: $(curl -s -o /dev/null -w %{http_code} http://127.0.0.1:27003/ 2>&1)"
apt-get -y purge openlinkhub >/tmp/p5.log 2>&1; echo "purge exit=$?"
echo "  state folder: $([ -d /var/lib/openlinkhub ] && echo KEPT || echo gone); user: $(id -un openlinkhub 2>&1); enable records: $(ls /var/lib/systemd/deb-systemd-helper-enabled 2>/dev/null | grep -c OpenLinkHub) ; wants link: $(ls /etc/systemd/system/multi-user.target.wants 2>/dev/null | grep -c OpenLinkHub)"
echo "== P5: installed again after a purge: on, as the first time"
apt-get -y --no-install-recommends install "$DEB" >/tmp/p6.log 2>&1; echo "install exit=$?"; sleep 3; st
echo "  database files copied again: $(find /var/lib/openlinkhub/database -type f | wc -l)"
apt-get -y purge openlinkhub >/dev/null 2>&1; rm -rf /etc/systemd/system/OpenLinkHub.service.d; systemctl daemon-reload
echo "== P6: upstream's own install in /opt (the station's kind), ours installed beside it"
mkdir -p /opt/OpenLinkHub/database/profiles /opt/OpenLinkHub/web
cp /bin/sleep /opt/OpenLinkHub/OpenLinkHub; echo '{"profile":"mine, in /opt"}' >/opt/OpenLinkHub/database/profiles/mine.json; echo '{"listenPort":27003}' >/opt/OpenLinkHub/config.json
cp /usr/share/openlinkhub/../../lib/udev/rules.d/99-openlinkhub.rules /tmp/ 2>/dev/null
cat >/etc/systemd/system/OpenLinkHub.service <<'EOU'
[Unit]
Description=Open source interface for iCUE LINK System Hub, Corsair AIOs and Hubs
After=sleep.target
[Service]
User=openlinkhub
WorkingDirectory=/opt/OpenLinkHub
ExecStart=/opt/OpenLinkHub/OpenLinkHub 3000
Restart=always
[Install]
WantedBy=multi-user.target
EOU
echo '# upstream rules, stand-in' >/etc/udev/rules.d/99-openlinkhub.rules
useradd -r openlinkhub --shell=/bin/false 2>/dev/null; chown -R openlinkhub:openlinkhub /opt/OpenLinkHub
systemctl daemon-reload; systemctl enable --now OpenLinkHub >/dev/null 2>&1
PID0=$(systemctl show -p MainPID --value OpenLinkHub); sum() { (find /opt/OpenLinkHub /etc/systemd/system/OpenLinkHub.service /etc/udev/rules.d/99-openlinkhub.rules -type f | sort | xargs sha256sum; ls -l --time-style=+ /etc/systemd/system/multi-user.target.wants/OpenLinkHub.service) | sha256sum | cut -c1-16; }
S0=$(sum); echo "  before: $(st | tr -d '\n') pid=$PID0 fingerprint=$S0 unit file: $(systemctl show -p FragmentPath --value OpenLinkHub)"
apt-get -y --no-install-recommends install "$DEB" >/tmp/p7.log 2>&1; echo "install exit=$?"; grep -i "openlinkhub:" /tmp/p7.log | head -3 | cut -c1-230
echo "  after our install: $(st | tr -d '\n') pid=$(systemctl show -p MainPID --value OpenLinkHub) fingerprint=$(sum) unit file: $(systemctl show -p FragmentPath --value OpenLinkHub)"
echo "  ours: program $([ -x /usr/bin/OpenLinkHub ] && echo installed), our unit file not enabled by us: $(ls /var/lib/systemd/deb-systemd-helper-enabled 2>/dev/null | grep -c OpenLinkHub) records"
apt-get -y --no-install-recommends install "$NEW" >/tmp/p8.log 2>&1; echo "upgrade of ours exit=$?; upstream: $(st | tr -d '\n') pid=$(systemctl show -p MainPID --value OpenLinkHub) fingerprint=$(sum)"
apt-get -y remove openlinkhub >/dev/null 2>&1; echo "removal of ours: upstream: $(st | tr -d '\n') pid=$(systemctl show -p MainPID --value OpenLinkHub) fingerprint=$(sum)"
apt-get -y purge openlinkhub >/dev/null 2>&1; echo "purge of ours: upstream: $(st | tr -d '\n') pid=$(systemctl show -p MainPID --value OpenLinkHub) fingerprint=$(sum); /opt profile: $(cat /opt/OpenLinkHub/database/profiles/mine.json)"
[ "$(sum)" = "$S0" ] && [ "$(systemctl show -p MainPID --value OpenLinkHub)" = "$PID0" ] && echo "RESULT P6: upstream's install untouched through install, upgrade, removal and purge" || echo "RESULT P6: FAILED"
