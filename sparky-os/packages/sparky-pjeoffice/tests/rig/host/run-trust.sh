#!/bin/bash
export DOCKER_HOST=unix:///K3D/partners/queue/pje-office-2/docker.sock
S=/var/tmp/pje-office-18/rig/trust-$(date +%s); mkdir -p $S
P=/K3D/partners/queue/pje-office-2/src/build/sparky-os/packages/sparky-pjeoffice
docker run --rm --name pj18-trust --pull=never --ulimit core=1 --network none --platform linux/amd64 -e LANG=C.UTF-8 --mount type=bind,src=$S,dst=/out --mount type=bind,src=$P,dst=/pkg,readonly \
 --mount type=bind,src=$P/tests/rig,dst=/rig,readonly --mount type=bind,src=/var/tmp/pje-office-18/classes,dst=/classes,readonly pj18-inst:2 bash -c "bash /rig/trust.sh /out; chown -R 1000:1000 /out" 2>&1
echo "scratch: $S"
