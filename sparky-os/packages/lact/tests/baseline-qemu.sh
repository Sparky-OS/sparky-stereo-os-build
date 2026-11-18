#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
# The processor-level proof of a Rust program (inside a container as root; /deb the build output, /snap the recorded card folder): repo/cpu-baseline.py
# knows Go, not Rust, and a Rust program holds instructions above the baseline that its crates (ring, aes, sha) choose by CPUID at run time, so the proof
# is the program itself running on a processor that lacks them: qemu64 (SSE2 and SSE3 only), after a control program with AES-NI shows that qemu64
# refuses such an instruction. Here the daemon starts on qemu64, reads the recorded card and answers the command line.
export DEBIAN_FRONTEND=noninteractive HOME=/tmp
sh /run/https-only-apt.sh >/dev/null
apt-get -y -qq update >/dev/null 2>&1
apt-get -y -qq --no-install-recommends install qemu-user gcc libc6-dev binutils python3 >/tmp/a.log 2>&1 || tail -3 /tmp/a.log
apt-get -y -qq --no-install-recommends install /deb/lact_*+lc1_amd64.deb >/tmp/b.log 2>&1 || tail -3 /tmp/b.log
systemctl stop lactd 2>/dev/null; rm -f /run/lactd.sock
cat >/tmp/aes.c <<'EOC'
int main(void){ __asm__ volatile("aesenc %%xmm0,%%xmm0":::"xmm0"); return 0; }
EOC
gcc -O0 -o /tmp/aes /tmp/aes.c
echo "control: a program with AES-NI (aesenc)"
qemu-x86_64 -cpu qemu64 /tmp/aes; echo "  on qemu64 (SSE2/SSE3, no AES-NI, no SSE4, no POPCNT, no AVX): exit=$? (132 = illegal instruction)"
qemu-x86_64 -cpu max /tmp/aes; echo "  on max: exit=$?"
echo "the program, whose own check lists the instructions above the baseline:"
python3 -I /src/sparky-os/repo/cpu-baseline.py /usr/bin/lact 2>&1 | head -1
mkdir -p /tmp/fakedrm && cp -a /snap/. /tmp/fakedrm/; CARD=$(ls /tmp/fakedrm | head -1)
_LACT_DRM_SYSFS_PATH=/tmp/fakedrm/$CARD qemu-x86_64 -cpu qemu64 /usr/bin/lact daemon >/tmp/lact.log 2>&1 &
QPID=$!
for i in $(seq 1 60); do [ -S /run/lactd.sock ] && break; sleep 1; done
sleep 3
echo "lact daemon on qemu64: socket after ${i}s: $([ -S /run/lactd.sock ] && echo yes || echo NO)"
echo "lact cli list on qemu64:"; qemu-x86_64 -cpu qemu64 /usr/bin/lact cli list 2>&1 | head -3 | cut -c1-150
echo "illegal-instruction lines in its log: $(grep -c 'illegal\|SIGILL' /tmp/lact.log)"
kill "$QPID"; wait "$QPID" 2>/dev/null; echo "program stopped by killing its own pid $QPID"
