#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
# Proof under systemd, as root inside a systemd container (docker run -d --cgroupns=private --security-opt writable-cgroups=true --security-opt seccomp=unconfined
# --security-opt apparmor=unconfined --cap-add SYS_ADMIN --tmpfs /run --tmpfs /tmp -v BUILD_OUT:/deb:ro -v FIXTURES:/fix:ro -v TESTS:/t:ro IMAGE /lib/systemd/systemd; no
# --privileged; the container's /sys stays read only). THE FANS OF THIS STATION ARE REAL: before anything is installed or started the recorded machine
# (tests/fixtures/hwmon-station.tar.xz, plain files) is mounted over /sys/class/hwmon and the mount is VERIFIED (a marker file that sysfs does not have, the
# source of the mount a tmpfs); if that fails the script stops with exit 3 and nothing else runs. The proof's only deviation from the shipped unit is a drop-in that
# sets CC_SENSORS_DETECT=OFF (the daemon would otherwise run sensors-detect and load modules on a machine that is not the recorded one).
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive
rm -f /usr/sbin/policy-rc.d
sh /run/https-only-apt.sh >/dev/null 2>&1
apt-get -y -qq update >/dev/null 2>&1; apt-get -y -qq --no-install-recommends install curl python3 xz-utils >/dev/null 2>&1
echo "== P0: the recorded machine over /sys/class/hwmon, verified before anything runs"
mkdir -p /tmp/hw && tar -xJf /fix/hwmon-station.tar.xz -C /tmp/hw || { echo "STOP: the fixture does not unpack"; exit 3; }
echo fixture > /tmp/hw/hwmon/FIXTURE-NOT-SYSFS
mount --bind /tmp/hw/hwmon /sys/class/hwmon || { echo "STOP: the mount over /sys/class/hwmon failed (the container needs --cap-add SYS_ADMIN); nothing was started"; exit 3; }
src=$(findmnt -n -o SOURCE /sys/class/hwmon); fstype=$(findmnt -n -o FSTYPE /sys/class/hwmon)
[ -f /sys/class/hwmon/FIXTURE-NOT-SYSFS ] && [ "$(cat /sys/class/hwmon/hwmon4/name)" = nct6798 ] && [ "$fstype" = tmpfs ] || { echo "STOP: /sys/class/hwmon is not the fixture (source=$src fstype=$fstype); nothing was started"; exit 3; }
# the real sysfs is read only here: a write that missed the fixture would fail
real_ro=$(touch /sys/class/drm/.probe 2>&1 | grep -c "Read-only")
echo "  /sys/class/hwmon: fixture verified (marker file, fstype=$fstype source=$src); the rest of /sys read only: $([ "$real_ro" = 1 ] && echo yes || echo UNKNOWN)"
FAN() { cat /sys/class/hwmon/hwmon4/$1; }
DEB1=$(ls /deb/coolercontrold_*+lc1_amd64.deb); DEB2=$(ls /deb/coolercontrol_*+lc1_amd64.deb)
st() { printf '  enabled=%s active=%s\n' "$(systemctl is-enabled coolercontrold 2>&1)" "$(systemctl is-active coolercontrold 2>&1)"; }
bump() { rm -rf /tmp/bump$1 && mkdir -p /tmp/bump$1; V=5.1.2-9$1+lc1; B=$(basename "$DEB1" | sed 's/^coolercontrold_//; s/_amd64.deb//')
	for d in "$DEB1" "$DEB2"; do n=$(basename "$d" | cut -d_ -f1); dpkg-deb -R "$d" /tmp/bump$1/$n && sed -i "s/^Version: .*/Version: $V/; s/(= $B)/(= $V)/" /tmp/bump$1/$n/DEBIAN/control && dpkg-deb -b /tmp/bump$1/$n /tmp/bump$1/$n.deb >/dev/null 2>&1; done
	echo "/tmp/bump$1/coolercontrold.deb /tmp/bump$1/coolercontrol.deb"; }
login() { curl -s -m 20 -c /tmp/jar -u CCAdmin:coolAdmin -X POST http://127.0.0.1:11987/login -o /dev/null -w '  login -> HTTP %{http_code}\n'; }
api() { curl -s -m 20 -b /tmp/jar -H 'Content-Type: application/json' "$@"; }
dropin() { mkdir -p /etc/systemd/system/coolercontrold.service.d; printf '[Service]\nEnvironment=CC_SENSORS_DETECT=OFF\n' >/etc/systemd/system/coolercontrold.service.d/10-proof.conf; }
dropin
echo "== P1: installed by apt (both packages); service up; the recorded machine's fans listed"
apt-get -y --no-install-recommends install "$DEB1" "$DEB2" >/tmp/p1.log 2>&1; echo "install exit=$?"; grep -E "^(E:|W:)" /tmp/p1.log | head -3
systemctl daemon-reload; systemctl restart coolercontrold; for i in $(seq 1 60); do curl -s -m 5 http://127.0.0.1:11987/health >/dev/null 2>&1 && break; sleep 2; done; st; login
echo "  version: $(coolercontrold --version 2>&1 | head -1)"
api http://127.0.0.1:11987/health | cut -c1-200; echo
api http://127.0.0.1:11987/devices >/tmp/devices.json
python3 - <<'PY'
import json
d = json.load(open('/tmp/devices.json'))['devices']
for x in d:
    ch = (x.get('info') or {}).get('channels', {})
    print(f"  device {x['name']} ({x['type']}) uid {x['uid'][:12]}: channels {sorted(ch)[:10]}")
PY
echo "-- journal:"; journalctl -u coolercontrold --no-pager -o cat 2>&1 | tail -4 | cut -c1-180
UID1=$(python3 -c "import json;print([x['uid'] for x in json.load(open('/tmp/devices.json'))['devices'] if x['name']=='nct6798'][0])" 2>/dev/null); echo "  nct6798 uid: ${UID1:0:12}"
[ -n "$UID1" ] || { echo "RESULT P1: FAILED: the recorded fan controller is not listed"; }
CH=$(python3 -c "import json;d=[x for x in json.load(open('/tmp/devices.json'))['devices'] if x['name']=='nct6798'][0];print(sorted(c for c,v in d['info']['channels'].items() if v.get('speed_options'))[0])" 2>/dev/null); echo "  first fan channel with speed control: $CH"
echo "== P2: a fixed duty is set and read back (the daemon writes the pwm file of the recorded machine)"
P0=$(FAN pwm1); echo "  pwm1 before: $P0 enable=$(FAN pwm1_enable)"
api -X PUT -d '{"speed_fixed":40}' http://127.0.0.1:11987/devices/$UID1/settings/$CH/manual -o /dev/null -w "  PUT manual 40 -> HTTP %{http_code}\n"
sleep 3; echo "  $CH settings read back: $(api http://127.0.0.1:11987/devices/$UID1/settings | python3 -c "import json,sys;d=json.load(sys.stdin);print(json.dumps([x for x in (d if isinstance(d,list) else d.get('settings',[])) if '$CH' in json.dumps(x)])[:260])")"
echo "  pwm files after: $(for n in 1 2 3 4 5 6 7; do printf 'pwm%s=%s(en%s) ' $n $(FAN pwm$n) $(FAN pwm${n}_enable); done)"
echo "== P3: a fan curve is set and read back"
TEMPNAME=$(python3 -c "import json;d=[x for x in json.load(open('/tmp/devices.json'))['devices'] if x['name']=='nct6798'][0];print(sorted(d['info'].get('temps',{}))[0])" 2>/dev/null); echo "  temperature source: $TEMPNAME ($(FAN temp1_input 2>/dev/null))"
api -X POST -d "{\"uid\":\"proofcurve\",\"name\":\"Proof curve\",\"p_type\":\"Graph\",\"speed_profile\":[[20.0,30],[40.0,50],[60.0,100]],\"temp_source\":{\"device_uid\":\"$UID1\",\"temp_name\":\"$TEMPNAME\"},\"function_uid\":\"0\"}" http://127.0.0.1:11987/profiles -o /dev/null -w "  POST profile -> HTTP %{http_code}\n"
CH2=$(python3 -c "import json;d=[x for x in json.load(open('/tmp/devices.json'))['devices'] if x['name']=='nct6798'][0];print(sorted(c for c,v in d['info']['channels'].items() if v.get('speed_options'))[1])" 2>/dev/null)
api -X PUT -d '{"profile_uid":"proofcurve"}' http://127.0.0.1:11987/devices/$UID1/settings/$CH2/profile -o /dev/null -w "  PUT profile on $CH2 -> HTTP %{http_code}\n"
sleep 12; echo "  the curve read back: $(api http://127.0.0.1:11987/profiles | python3 -c "import json,sys;print([ (p['name'],p.get('speed_profile')) for p in json.load(sys.stdin)['profiles'] if p['uid']=='proofcurve'])")"
echo "  $CH2 setting: $(api http://127.0.0.1:11987/devices/$UID1/settings | python3 -c "import json,sys;d=json.load(sys.stdin);print(json.dumps([x for x in (d if isinstance(d,list) else d.get('settings',[])) if '$CH2' in json.dumps(x)])[:260])")"
echo "  pwm files after: $(for n in 1 2 3 4 5 6 7; do printf 'pwm%s=%s ' $n $(FAN pwm$n); done)"
echo "== P4: the person's settings survive a restart and an upgrade (the package never writes them)"
ls /etc/coolercontrol; S0=$(sha256sum /etc/coolercontrol/config.toml | cut -c1-16); echo "  config.toml $S0, holds the curve: $(grep -c proofcurve /etc/coolercontrol/config.toml)"
NEW=$(bump 2); apt-get -y --no-install-recommends install $NEW >/tmp/p2.log 2>&1; echo "upgrade exit=$?"; sleep 6; st
echo "  config.toml unchanged by the upgrade: $([ "$(sha256sum /etc/coolercontrol/config.toml | cut -c1-16)" = "$S0" ] && echo yes || echo CHANGED-BY-THE-RUNNING-DAEMON-CHECK)"
echo "  the curve still listed: $(api http://127.0.0.1:11987/profiles | grep -c proofcurve)"
echo "== P5: the person turns it off; an upgrade keeps it off"
systemctl disable --now coolercontrold >/dev/null 2>&1; st
NEW3=$(bump 3); apt-get -y --no-install-recommends install $NEW3 >/tmp/p3.log 2>&1; echo "upgrade exit=$?"; sleep 2; st
echo "== P6: removal keeps the settings, purge takes them"
apt-get -y remove coolercontrol coolercontrold >/tmp/p4.log 2>&1; echo "remove exit=$?"
echo "  program: $([ -e /usr/bin/coolercontrold ] && echo PRESENT || echo gone); window: $([ -e /usr/bin/coolercontrol ] && echo PRESENT || echo gone); unit: $([ -e /usr/lib/systemd/system/coolercontrold.service ] && echo PRESENT || echo gone); /etc/coolercontrol: $([ -d /etc/coolercontrol ] && echo kept || echo GONE)"
dpkg --purge coolercontrol coolercontrold >/tmp/p5.log 2>&1; echo "purge exit=$?"
echo "  /etc/coolercontrol: $([ -d /etc/coolercontrol ] && echo KEPT || echo gone); /var/lib/coolercontrol: $([ -d /var/lib/coolercontrol ] && echo KEPT || echo gone); enable records: $(ls /var/lib/systemd/deb-systemd-helper-enabled 2>/dev/null | grep -c coolercontrold); wants link: $(ls /etc/systemd/system/multi-user.target.wants 2>/dev/null | grep -c coolercontrold)"
echo "  the apt sources are untouched by install and purge: $(ls /etc/apt/sources.list.d | tr '\n' ' ' | cut -c1-120)"
echo "== P7: installed again after a purge: on, as the first time"
apt-get -y --no-install-recommends install "$DEB1" "$DEB2" >/tmp/p6.log 2>&1; echo "install exit=$?"; systemctl daemon-reload; sleep 4; st
dpkg --purge coolercontrol coolercontrold >/dev/null 2>&1; rm -rf /etc/systemd/system/coolercontrold.service.d; systemctl daemon-reload
echo "== P8: a copy made by upstream's makefile (/usr/local), ours installed beside it"
mkdir -p /usr/local/bin /usr/local/lib/systemd/system /etc/coolercontrol
printf '#!/bin/sh\nexec sleep 3000\n' >/usr/local/bin/coolercontrold; chmod +x /usr/local/bin/coolercontrold
printf '[Unit]\nDescription=CoolerControl Daemon (upstream makefile copy)\n[Service]\nExecStart=/usr/local/bin/coolercontrold\n[Install]\nWantedBy=multi-user.target\n' >/usr/local/lib/systemd/system/coolercontrold.service
echo "# the person's settings, shared with the copy" >/etc/coolercontrol/config.toml
systemctl daemon-reload; systemctl enable --now coolercontrold >/dev/null 2>&1
PID0=$(systemctl show -p MainPID --value coolercontrold); fp() { (sha256sum /usr/local/bin/coolercontrold /usr/local/lib/systemd/system/coolercontrold.service /etc/coolercontrol/config.toml; ls -l --time-style=+ /etc/systemd/system/multi-user.target.wants/coolercontrold.service) | sha256sum | cut -c1-16; }
S0=$(fp); echo "  before: $(st | tr -d '\n') pid=$PID0 fingerprint=$S0 unit file: $(systemctl show -p FragmentPath --value coolercontrold)"
apt-get -y --no-install-recommends install "$DEB1" "$DEB2" >/tmp/p7.log 2>&1; echo "install exit=$?"; grep -i "^coolercontrold:" /tmp/p7.log | head -2 | cut -c1-200
echo "  after our install: $(st | tr -d '\n') pid=$(systemctl show -p MainPID --value coolercontrold) fingerprint=$(fp) unit file: $(systemctl show -p FragmentPath --value coolercontrold)"
apt-get -y --no-install-recommends install $NEW >/tmp/p8.log 2>&1; echo "upgrade of ours exit=$?; copy: pid=$(systemctl show -p MainPID --value coolercontrold) fingerprint=$(fp)"
apt-get -y remove coolercontrol coolercontrold >/dev/null 2>&1; echo "removal of ours: copy: $(st | tr -d '\n') pid=$(systemctl show -p MainPID --value coolercontrold) fingerprint=$(fp)"
dpkg --purge coolercontrol coolercontrold >/dev/null 2>&1; echo "purge of ours: copy: $(st | tr -d '\n') pid=$(systemctl show -p MainPID --value coolercontrold) fingerprint=$(fp); /etc/coolercontrol: $([ -f /etc/coolercontrol/config.toml ] && echo kept || echo GONE)"
[ "$(fp)" = "$S0" ] && [ "$(systemctl show -p MainPID --value coolercontrold)" = "$PID0" ] && echo "RESULT P8: the copy made by upstream's makefile untouched through install, upgrade, removal and purge" || echo "RESULT P8: FAILED"
