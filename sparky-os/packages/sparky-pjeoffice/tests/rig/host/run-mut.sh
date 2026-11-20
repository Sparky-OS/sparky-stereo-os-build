#!/bin/bash
# run-mut.sh MUTATION : one mutation in a throwaway container
export DOCKER_HOST=unix:///K3D/partners/queue/pje-office-2/docker.sock
S=/var/tmp/pje-office-18/rig/mut-$1-$(date +%s); mkdir -p $S
P=/K3D/partners/queue/pje-office-2/src/build/sparky-os/packages/sparky-pjeoffice
IMG=pj18-run:1; [ "$1" = launcher-no-lock ] && IMG=pj18-inst:2
docker run --rm --name "pj18-mut-$1" --pull=never --ulimit core=1 --network none --platform linux/amd64 --mount type=bind,src=$P,dst=/pkg,readonly \
 --mount type=bind,src=/var/tmp/pje-office-18/bin,dst=/tb,readonly --mount type=bind,src=/var/tmp/pje-office-18/x,dst=/real,readonly --mount type=bind,src=$S,dst=/fx --tmpfs /run:exec \
 $IMG bash -c "if [ '$1' = launcher-no-lock ]; then useradd -m -u 1000 tester; chown 1000:1000 /fx; su tester -c 'HOME=/home/tester bash /pkg/tests/mutations.sh $1 /fx'; else bash /pkg/tests/mutations.sh $1 /fx; fi; chown -R 1000:1000 /fx" 2>&1
echo "scratch: $S"
