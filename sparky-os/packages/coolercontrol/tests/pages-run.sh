#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
# Every page of the interface in a browser against the running daemon, in a systemd container run as systemd-proof.sh is (the recorded machine mounted over
# /sys/class/hwmon and VERIFIED before anything starts: THE FANS OF THIS STATION ARE REAL). Installs the package, starts the service, sets a fan curve and a fixed
# duty through the API, installs chromium, and runs pages-proof.py (every route, its text and its errors, a screenshot each).
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive
sh /run/https-only-apt.sh >/dev/null 2>&1
apt-get -y -qq update >/dev/null 2>&1; apt-get -y -qq --no-install-recommends install curl python3 xz-utils >/dev/null 2>&1
mkdir -p /tmp/hw && tar -xJf /fix/hwmon-station.tar.xz -C /tmp/hw || { echo "STOP: the fixture does not unpack"; exit 3; }
echo fixture > /tmp/hw/hwmon/FIXTURE-NOT-SYSFS
mount --bind /tmp/hw/hwmon /sys/class/hwmon || { echo "STOP: the mount failed; nothing was started"; exit 3; }
[ -f /sys/class/hwmon/FIXTURE-NOT-SYSFS ] && [ "$(cat /sys/class/hwmon/hwmon4/name)" = nct6798 ] && [ "$(findmnt -n -o FSTYPE /sys/class/hwmon)" = tmpfs ] || { echo "STOP: /sys/class/hwmon is not the fixture"; exit 3; }
echo "fixture verified over /sys/class/hwmon"
mkdir -p /etc/systemd/system/coolercontrold.service.d; printf '[Service]\nEnvironment=CC_SENSORS_DETECT=OFF\n' >/etc/systemd/system/coolercontrold.service.d/10-proof.conf
apt-get -y --no-install-recommends install /deb/coolercontrold_*+lc1_amd64.deb /deb/coolercontrol_*+lc1_amd64.deb >/tmp/i.log 2>&1; echo "install exit=$?"
systemctl daemon-reload; systemctl restart coolercontrold
for i in $(seq 1 60); do curl -s -m 5 http://127.0.0.1:11987/health >/dev/null 2>&1 && break; sleep 2; done
curl -s -m 20 -c /tmp/jar -u CCAdmin:coolAdmin -X POST http://127.0.0.1:11987/login -o /dev/null
api() { curl -s -m 20 -b /tmp/jar -H 'Content-Type: application/json' "$@"; }
UID1=$(api http://127.0.0.1:11987/devices | python3 -c "import json,sys;print([x['uid'] for x in json.load(sys.stdin)['devices'] if x['name']=='nct6798'][0])")
api -X POST -d "{\"uid\":\"proofcurve\",\"name\":\"Proof curve\",\"p_type\":\"Graph\",\"speed_profile\":[[20.0,30],[40.0,50],[60.0,100]],\"temp_source\":{\"device_uid\":\"$UID1\",\"temp_name\":\"temp1\"},\"function_uid\":\"0\"}" http://127.0.0.1:11987/profiles -o /dev/null
api -X PUT -d '{"profile_uid":"proofcurve"}' http://127.0.0.1:11987/devices/$UID1/settings/fan2/profile -o /dev/null
api -X PUT -d '{"speed_fixed":40}' http://127.0.0.1:11987/devices/$UID1/settings/fan1/manual -o /dev/null
sleep 8; echo "pwm1=$(cat /sys/class/hwmon/hwmon4/pwm1) pwm2=$(cat /sys/class/hwmon/hwmon4/pwm2)"
apt-get -y -qq --no-install-recommends install chromium python3-websockets >/tmp/c.log 2>&1; echo "chromium install exit=$?"
mkdir -p /out; python3 /t/pages-proof.py /out/pages 2>&1 | tee /out/pages.log | tail -60
