#!/bin/bash
# The 130-saver requalification of a new gl-stereo layer in the audit image (this Dockerfile over
# an installed-file base): installs the bootstrap packages, keeps Flurry from before its
# camera fix for the negative control, then runs requalify-steps.sh as UID 1000, step by step.
# Mounts: /workspace/gl-stereo (checkout), /build (scratch), /debs (bootstrap debs), /orig (the
# XScreenSaver original tarball), /old (xscreensaver-gl-extra 6.09+dfsg1-2+stereo3d1).
# usage (root, in the container): requalify-root.sh [first-step]
set -u
B=/build; W=/workspace/gl-stereo; RIG=$(dirname "$0")
export DEBIAN_FRONTEND=noninteractive
log() { echo "$(date +%T) $*" >> $B/requalify.log; }
user() { setpriv --reuid=1000 --regid=1000 --groups=125 env -i HOME=$B/home PATH=/usr/local/bin:/usr/bin:/bin LANG=C.UTF-8 bash $RIG/requalify-steps.sh "$1"; }
mkdir -p $B/home; chown 1000:1000 $B $B/home
# dbus-daemon and Xwayland look the test user up by its UID
getent group 1000 > /dev/null || groupadd -g 1000 auditor
getent passwd 1000 > /dev/null || useradd -u 1000 -g 1000 -M -d $B/home -s /bin/bash auditor
touch $B/requalify.log; chown 1000:1000 $B/requalify.log
# every container starts from the image: install the bootstrap packages each time (the scratch
# keeps only the first run's records)
apt-get -qq update > $B/install-bootstrap-$(date +%H%M%S).log 2>&1
apt-get -y --no-install-recommends install $(ls /debs/*.deb | grep -v dbgsym) >> $B/install-bootstrap-$(date +%H%M%S).log 2>&1 || { log "bootstrap install failed"; exit 1; }
log "bootstrap installed in this container: $(sha256sum /usr/lib/gl-stereo/libgl-stereo.so)"
if [ ! -f $B/installed.done ]; then
	dpkg-query -W -f='${Package} ${Version}\n' gl-stereo gl-stereo-savers gl-stereo-show kwin-wayland libgl1-mesa-dri xscreensaver-gl xscreensaver-gl-extra libstereo-declare1 > $B/installed-packages.txt
	sha256sum /usr/lib/gl-stereo/libgl-stereo.so >> $B/installed-packages.txt
	mkdir -p $B/old && dpkg-deb -x /old/xscreensaver-gl-extra_6.09+dfsg1-2+stereo3d1_amd64.deb $B/old/root
	mkdir -p $B/pre-flurry-installed && cp -a /usr/libexec/xscreensaver/. $B/pre-flurry-installed/
	install -m755 $B/old/root/usr/libexec/xscreensaver/flurry $B/pre-flurry-installed/flurry
	sha256sum /usr/libexec/xscreensaver/flurry $B/pre-flurry-installed/flurry > $B/flurry-binaries.txt
	chown -R 1000:1000 $B
	touch $B/installed.done; log "bootstrap installed: $(tail -1 $B/installed-packages.txt)"
fi
steps=${STEPS:-"setup late lights inventory sweep oldflurry merge warmup starwars flurry energy references fliptext mono monomore monostatus tiles equivalence collect flurrycheck candidate install-candidate functional compile"}
started=${1:-}
for step in $steps; do
	if [ -n "$started" ] && [ "$step" != "$started" ]; then continue; fi
	started=
	log "step $step"
	case $step in
	oldflurry)
		current=$(sha256sum /usr/libexec/xscreensaver/flurry | cut -d' ' -f1)
		cp /usr/libexec/xscreensaver/flurry $B/flurry.current
		install -m755 $B/old/root/usr/libexec/xscreensaver/flurry /usr/libexec/xscreensaver/flurry
		user oldflurry
		install -m755 $B/flurry.current /usr/libexec/xscreensaver/flurry
		[ "$(sha256sum /usr/libexec/xscreensaver/flurry | cut -d' ' -f1)" = "$current" ] || { log "Flurry not restored"; exit 1; }
		log "Flurry restored $current" ;;
	install-candidate)
		# the installed catalogue gets the candidate receipts the way the package build installs them
		python3 $W/savers/install-qualified.py $B/qualification-candidate.json /usr/share/gl-stereo/catalogue.json /usr/lib/gl-stereo/libgl-stereo.so > $B/install-candidate.log 2>&1 &&
		python3 $W/savers/make-index.py /usr/share/gl-stereo/savers.json /usr/share/gl-stereo/catalogue.json >> $B/install-candidate.log 2>&1
		echo $? > $B/install-candidate.status; log "install-candidate status $(cat $B/install-candidate.status)" ;;
	*) user $step ;;
	esac
	chown -R 1000:1000 $B 2>/dev/null
done
log "done"
