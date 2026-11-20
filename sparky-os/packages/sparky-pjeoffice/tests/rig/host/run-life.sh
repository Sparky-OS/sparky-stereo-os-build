#!/bin/bash
export DOCKER_HOST=unix:///K3D/partners/queue/pje-office-2/docker.sock
S=/var/tmp/pje-office-18/rig/life-$(date +%s); mkdir -p $S/fx $S/out
P=/K3D/partners/queue/pje-office-2/src/build/sparky-os/packages/sparky-pjeoffice
docker run --rm --name pj18-life --pull=never --ulimit core=1 --network none --platform linux/amd64 -e LANG=C.UTF-8 \
 --mount type=bind,src=/var/tmp/pje-office-18/debs,dst=/debs,readonly --mount type=bind,src=$P,dst=/pkg,readonly --mount type=bind,src=$P/tests/rig,dst=/rig,readonly \
 --mount type=bind,src=/var/tmp/pje-office-18/x,dst=/real,readonly --mount type=bind,src=$S/fx,dst=/fx --mount type=bind,src=$S/out,dst=/out \
 pj18-flat:2 bash -c "bash /rig/lifecycle.sh /out; chown -R 1000:1000 /out /fx" 2>&1
echo "scratch: $S"
