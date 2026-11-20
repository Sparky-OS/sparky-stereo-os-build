#!/bin/bash
# run-entry.sh CASE [LANG] : the entry cases in a container of the flat-repository image (the program is NOT installed)
export DOCKER_HOST=unix:///K3D/partners/queue/pje-office-2/docker.sock
case $1 in good|wronghash) NETARG="" ;; *) NETARG="--network none" ;; esac
S=/var/tmp/pje-office-18/rig/entry-$1-$(date +%s); mkdir -p $S/fx $S/out
P=/K3D/partners/queue/pje-office-2/src/build/sparky-os/packages/sparky-pjeoffice
docker run --rm --name "pj18-entry-$1" --pull=never --ulimit core=1 $NETARG --platform linux/amd64 -e LANG=${2:-en_US.UTF-8} -v /etc/ssl/certs/ca-certificates.crt:/run/host-ca.crt:ro -v /K3D/partners/https-only-apt.sh:/run/https-only-apt.sh:ro \
 --mount type=bind,src=/var/tmp/pje-office-18/debs,dst=/debs,readonly --mount type=bind,src=$P,dst=/pkg,readonly --mount type=bind,src=$P/tests/rig,dst=/rig,readonly \
 --mount type=bind,src=/var/tmp/pje-office-18/x,dst=/real,readonly --mount type=bind,src=$S/fx,dst=/fx --mount type=bind,src=$S/out,dst=/out \
 pj18-flat:2 bash -c "sh /run/https-only-apt.sh >/dev/null 2>&1; bash /rig/entry.sh $1 /out; chown -R 1000:1000 /out /fx" 2>&1
echo "scratch: $S"
