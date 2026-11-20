#!/bin/bash
# run-rig.sh NAME MODE : one container of pj18-inst:2 (network none), the installed package, uid 1000, the signing rig
export DOCKER_HOST=unix:///K3D/partners/queue/pje-office-2/docker.sock
S=/var/tmp/pje-office-18/rig/$1-$(date +%s); mkdir -p $S
docker run --rm --name "pj18-$1" --pull=never --ulimit core=1 --network none --platform linux/amd64 --mount type=bind,src=$S,dst=/scratch \
 --mount type=bind,src=/K3D/partners/queue/pje-office-2/src/build/tools/pjeoffice-audit,dst=/tools,readonly --mount type=bind,src=/var/tmp/pje-office-18/classes,dst=/classes,readonly \
 --mount type=bind,src=/K3D/partners/queue/pje-office-2/src/build/sparky-os/packages/sparky-pjeoffice/tests/rig,dst=/rig,readonly --mount type=bind,src=/var/tmp/pje-office-18/bin,dst=/tb,readonly \
 pj18-inst:2 bash -c ". /tb/rig-common.sh; export STEPS='${3:-pdf login}'; as_tester '/rig/signing.sh $2 /scratch/out' ; chown -R 1000:1000 /scratch" 2>&1
echo "scratch: $S"
