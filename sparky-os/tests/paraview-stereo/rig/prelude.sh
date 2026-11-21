# Sourced as root inside a lane container: https-only apt, deb-multimedia and the published edition tree r1118a at pin 1001.
set -e
sh /run/https-only-apt.sh >/dev/null
export DEBIAN_FRONTEND=noninteractive
cat > /etc/apt/sources.list.d/dmo.sources <<S
Types: deb
URIs: https://www.deb-multimedia.org
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
apt-get update -qq 2>&1 | tail -3
