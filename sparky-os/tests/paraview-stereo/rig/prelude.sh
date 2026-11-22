# Sourced as root inside a lane container: https-only apt, Debian testing from snapshot.debian.org at one instant
# (SNAP, default 20261119T023717Z: see rig/SNAPSHOT.md), deb-multimedia from its frozen signed index under /dmo
# ($S/frozen/dmo, mounted read-only), and the published edition tree r1118a at pin 1001 under /repo.
set -e
sh /run/https-only-apt.sh >/dev/null
export DEBIAN_FRONTEND=noninteractive
SNAP=${SNAP:-20261119T023717Z}
rm -f /etc/apt/sources.list
cat > /etc/apt/sources.list.d/debian.sources <<S
Types: deb
URIs: https://snapshot.debian.org/archive/debian/$SNAP
Suites: testing testing-updates
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.pgp
Check-Valid-Until: no

Types: deb
URIs: https://snapshot.debian.org/archive/debian-security/$SNAP
Suites: testing-security
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.pgp
Check-Valid-Until: no
S
cat > /etc/apt/sources.list.d/dmo.sources <<S
Types: deb
URIs: file:///dmo
Suites: forky
Components: main non-free
Signed-By: /run/keys/deb-multimedia-keyring.pgp
S
cat > /etc/apt/sources.list.d/sparky-published.sources <<S
Types: deb
URIs: file:///repo
Suites: mashtabba
Components: main
Signed-By: /run/keys/sparky-stereo-repo.asc
S
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/00-sparky
printf 'Acquire::Retries "5";\n' > /etc/apt/apt.conf.d/80sci50f-retries
echo "$SNAP" > /etc/apt/sci50f-snapshot
apt-get update -qq 2>&1 | tail -3
