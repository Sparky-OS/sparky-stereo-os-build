#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
# The processor-level proof of the Rust daemon (inside a systemd container as root, run like systemd-proof.sh; /deb the build output, /fix the fixtures): repo/cpu-baseline.py knows Go, not Rust, and a Rust
# program holds instructions above the baseline that its crates (ring, aes, sha) choose by CPUID at run time, so the proof is the program itself running on a
# processor that lacks them: qemu64 (SSE2 and SSE3 only), after a control program with AES-NI shows that qemu64 refuses such an instruction. The daemon starts on
# qemu64 over the recorded machine (the fixture mounted and verified as in systemd-proof.sh), serves its API and lists the fans. THE FANS OF THIS STATION ARE REAL:
# nothing starts before the fixture is verified.
export DEBIAN_FRONTEND=noninteractive HOME=/tmp
sh /run/https-only-apt.sh >/dev/null 2>&1
apt-get -y -qq update >/dev/null 2>&1
apt-get -y -qq --no-install-recommends install qemu-user gcc libc6-dev binutils python3 curl xz-utils >/tmp/a.log 2>&1 || tail -3 /tmp/a.log
mkdir -p /tmp/hw && tar -xJf /fix/hwmon-station.tar.xz -C /tmp/hw && echo fixture >/tmp/hw/hwmon/FIXTURE-NOT-SYSFS
mount --bind /tmp/hw/hwmon /sys/class/hwmon || { echo "STOP: the mount failed; nothing was started"; exit 3; }
[ -f /sys/class/hwmon/FIXTURE-NOT-SYSFS ] && [ "$(cat /sys/class/hwmon/hwmon4/name)" = nct6798 ] || { echo "STOP: /sys/class/hwmon is not the fixture"; exit 3; }
echo "fixture verified over /sys/class/hwmon"
apt-get -y -qq --no-install-recommends install /deb/coolercontrold_*+lc1_amd64.deb >/tmp/b.log 2>&1 || tail -3 /tmp/b.log
systemctl stop coolercontrold 2>/dev/null; systemctl disable coolercontrold >/dev/null 2>&1
cat >/tmp/aes.c <<'EOC'
int main(void){ __asm__ volatile("aesenc %%xmm0,%%xmm0":::"xmm0"); return 0; }
EOC
gcc -O0 -o /tmp/aes /tmp/aes.c
echo "control: a program with AES-NI (aesenc)"
qemu-x86_64 -cpu qemu64 /tmp/aes; echo "  on qemu64 (SSE2/SSE3, no AES-NI, no SSE4, no POPCNT, no AVX): exit=$? (132 = illegal instruction)"
qemu-x86_64 -cpu max /tmp/aes; echo "  on max: exit=$?"
echo "the daemon and the window, whose own check lists the instructions above the baseline:"
python3 -I /src/sparky-os/repo/cpu-baseline.py /usr/bin/coolercontrold 2>&1 | head -2
echo "coolercontrold --version on qemu64: $(qemu-x86_64 -cpu qemu64 /usr/bin/coolercontrold --version 2>&1 | head -1)"
CC_SENSORS_DETECT=OFF qemu-x86_64 -cpu qemu64 /usr/bin/coolercontrold >/tmp/cc.log 2>&1 &
for i in $(seq 1 120); do curl -s -m 3 http://127.0.0.1:11987/health >/dev/null 2>&1 && break; sleep 2; done
echo "the daemon on qemu64: API answers after ~$((i*2))s: $(curl -s -m 5 http://127.0.0.1:11987/health | cut -c1-80)"
curl -s -m 10 -c /tmp/jar -u CCAdmin:coolAdmin -X POST http://127.0.0.1:11987/login -o /dev/null
echo "devices on qemu64: $(curl -s -m 20 -b /tmp/jar http://127.0.0.1:11987/devices | python3 -c "import json,sys;print([x['name'] for x in json.load(sys.stdin)['devices']])")"
echo "illegal-instruction lines in its log: $(grep -c 'illegal\|SIGILL' /tmp/cc.log)"
