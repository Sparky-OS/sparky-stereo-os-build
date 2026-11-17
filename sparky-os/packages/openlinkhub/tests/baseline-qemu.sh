#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/17
# Copyright 2026 under the GNU GPL3 License
# The processor-level proof of a Go program (inside a container as root; /deb the build output, /src the build repository):
# repo/cpu-baseline.py lists the instructions above the amd64 baseline, which a Go program always holds (the standard library and x/crypto
# carry AES-NI, AVX2, SHA-NI, POPCNT and SSE4.1 code that the runtime chooses by CPUID, and GOAMD64=v1 guards the compiler own POPCNT and ROUNDSD
# the same way), so the proof is the program itself running on a processor that lacks them: qemu64 (SSE2 and SSE3 only), after a control
# program with AES-NI shows that qemu64 refuses such an instruction.
export DEBIAN_FRONTEND=noninteractive HOME=/tmp
sh /run/https-only-apt.sh >/dev/null
apt-get -y -qq update >/dev/null 2>&1
apt-get -y -qq --no-install-recommends install qemu-user gcc libc6-dev libpipewire-0.3-0t64 libudev1 curl binutils python3 >/tmp/a.log 2>&1 || tail -3 /tmp/a.log
dpkg-deb -x /deb/openlinkhub_*+lc1_amd64.deb /r
cat >/tmp/aes.c <<'EOC'
int main(void){ __asm__ volatile("aesenc %%xmm0,%%xmm0":::"xmm0"); return 0; }
EOC
gcc -O0 -o /tmp/aes /tmp/aes.c
echo "control: a program with AES-NI (aesenc)"
qemu-x86_64 -cpu qemu64 /tmp/aes; echo "  on qemu64 (SSE2/SSE3, no AES-NI, no SSE4, no POPCNT, no AVX): exit=$? (132 = illegal instruction)"
qemu-x86_64 -cpu max /tmp/aes; echo "  on max: exit=$?"
echo "the program, whose own check lists 6,620 instructions above the baseline:"
python3 -I /src/sparky-os/repo/cpu-baseline.py /r/usr/bin/OpenLinkHub 2>&1 | head -2
mkdir -p /st && cp -a /r/usr/share/openlinkhub/database /st/ && ln -s /r/usr/share/openlinkhub/web /st/web && ln -s /r/usr/share/openlinkhub/static /st/static
cd /st
(qemu-x86_64 -cpu qemu64 /r/usr/bin/OpenLinkHub >/tmp/olh.log 2>&1; echo "program exit=$?" >>/tmp/olh.log) &
for i in $(seq 1 60); do c=$(curl -s -o /tmp/page.html -w '%{http_code}' http://127.0.0.1:27003/ 2>/dev/null); [ "$c" = 200 ] && break; sleep 1; done
echo "OpenLinkHub on qemu64: web page -> $c after ${i}s, $(wc -c </tmp/page.html) bytes; title: $(grep -o '<title>[^<]*' /tmp/page.html | head -1)"
grep -c "illegal\|SIGILL" /tmp/olh.log | sed 's/^/illegal-instruction lines in its log: /'
pkill -f 'qemu-x86_64.*OpenLinkHub'; sleep 1; tail -3 /tmp/olh.log | cut -c1-200
echo "build info:"; python3 - <<'EOP'
import re
d=open('/r/usr/bin/OpenLinkHub','rb').read()
for k in (b'GOAMD64=v1',b'-buildmode=pie',b'-trimpath=true',b'CGO_ENABLED=1',b'-mod=vendor'): print(' ',k.decode(), 'present' if k in d else 'ABSENT')
EOP
