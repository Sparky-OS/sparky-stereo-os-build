#!/bin/bash
# run-plasma.sh NAME [LANG] : the Plasma login case in pj18-inst:2 (network none, no device)
export DOCKER_HOST=unix:///K3D/partners/queue/pje-office-2/docker.sock
S=/var/tmp/pje-office-18/rig/$1-$(date +%s); mkdir -p $S
P=/K3D/partners/queue/pje-office-2/src/build/sparky-os/packages/sparky-pjeoffice
docker run --rm --name "pj18-$1" --pull=never --ulimit core=0 ${NET---network none} --platform linux/amd64 --cap-add SYS_NICE --cap-add SYS_PTRACE -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v /K3D/partners/https-only-apt.sh:/run/https-only-apt.sh:ro --mount type=bind,src=$S,dst=/scratch \
 --mount type=bind,src=$P/tests/rig,dst=/rig,readonly --mount type=bind,src=/var/tmp/pje-office-18/bin,dst=/tb,readonly \
 pj18-inst:2 bash -c "useradd -m -u 1000 tester 2>/dev/null; if [ -n '${2:-}' ]; then sh /run/https-only-apt.sh >/dev/null; DEBIAN_FRONTEND=noninteractive apt-get -y -q install locales >/dev/null 2>&1; printf 'pt_BR.UTF-8 UTF-8\\nde_DE.UTF-8 UTF-8\\n' > /etc/locale.gen; locale-gen >/dev/null 2>&1; fi; mkdir -p /scratch/out; chown -R 1000:1000 /scratch; bash /rig/capture-daemon.sh /scratch/out & su tester -c 'env HOME=/home/tester LOGIN_LANG=${2:-C.UTF-8} bash /rig/plasma.sh /scratch/out'; touch /scratch/out/stop; sleep 2; chown -R 1000:1000 /scratch" 2>&1
echo "scratch: $S"
