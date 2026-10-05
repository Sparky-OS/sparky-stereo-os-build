#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
if [ -d /debs ]; then
	cd /debs; inst=""
	for p in $(dpkg-query -W -f '${Package}\n' | sort -u); do f=$(ls ${p}_*_amd64.deb 2>/dev/null | grep -v dbgsym | tail -1); [ -n "$f" ] && inst="$inst /debs/$f"; done
	[ -n "$inst" ] && dpkg -i $inst > /tmp/dpkg.log 2>&1; echo "installed over the image: $(echo $inst | wc -w) packages"
fi
dpkg-query -W -f '${Package} ${Version}; ' libglx-mesa0 mesa-libgallium kwin-wayland; echo
command -v xprop > /dev/null || apt-get install -y -qq x11-utils > /dev/null 2>&1
useradd -m -u 1000 t > /dev/null 2>&1
if [ "$SMOKE_MODE" = gpu ]; then groupadd -g "$SMOKE_GID" hostrender > /dev/null 2>&1; usermod -aG "$SMOKE_GID" t > /dev/null 2>&1; fi
su t -c "SMOKE_MODE=$SMOKE_MODE dbus-run-session -- /w/inner.sh" 2>&1 | grep -v -E 'ignoring unknown|a11y'
