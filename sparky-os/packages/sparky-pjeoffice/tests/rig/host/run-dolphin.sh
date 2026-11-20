#!/bin/bash
export DOCKER_HOST=unix:///K3D/partners/queue/pje-office-2/docker.sock
S=/var/tmp/pje-office-18/rig/$1-$(date +%s); mkdir -p $S
P=/K3D/partners/queue/pje-office-2/src/build/sparky-os/packages/sparky-pjeoffice
docker run --rm --name "pj18-$1" --pull=never --ulimit core=1 --network none --platform linux/amd64 --mount type=bind,src=$S,dst=/scratch \
 --mount type=bind,src=$P/tests/rig,dst=/rig,readonly pj18-inst:2 bash -c "useradd -m -u 1000 tester 2>/dev/null; mkdir -p /scratch/out; chown -R 1000:1000 /scratch; su tester -c 'env HOME=/home/tester LOGIN_LANG=${2:-C.UTF-8} bash /rig/dolphin.sh /scratch/out'; chown -R 1000:1000 /scratch" 2>&1
echo "scratch: $S"
