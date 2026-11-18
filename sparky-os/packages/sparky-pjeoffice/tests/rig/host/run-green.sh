#!/bin/bash
export DOCKER_HOST=unix:///K3D/partners/queue/pje-office-2/docker.sock
S=/var/tmp/pje-office-18/rig/green-$(date +%s); mkdir -p $S/fx $S/fx2
P=/K3D/partners/queue/pje-office-2/src/build/sparky-os/packages/sparky-pjeoffice
docker run --rm --name pj18-green --pull=never --ulimit core=0 --network none --platform linux/amd64 --mount type=bind,src=$P,dst=/pkg,readonly \
 --mount type=bind,src=/var/tmp/pje-office-18/debs,dst=/debs,readonly --mount type=bind,src=/var/tmp/pje-office-18/x,dst=/real,readonly --mount type=bind,src=$S/fx,dst=/fx --mount type=bind,src=$S/fx2,dst=/fx2 --tmpfs /run:exec \
 pj18-run:1 bash -c "dpkg-deb -x /debs/sparky-pjeoffice_0.1.0+lc1_amd64.deb / && echo '== installer tests against the files of the built .deb' && bash /pkg/tests/installer.sh /fx > /fx/installer-result.txt 2>&1; tail -3 /fx/installer-result.txt; grep -c '^PASS' /fx/installer-result.txt; grep '^FAIL' /fx/installer-result.txt; echo '== watcher tests' && python3 /pkg/watcher/test_watch.py /fx2/w > /fx2/watcher-result.txt 2>&1; tail -2 /fx2/watcher-result.txt; grep -c '^PASS' /fx2/watcher-result.txt; chown -R 1000:1000 /fx /fx2" 2>&1
echo "scratch: $S"
