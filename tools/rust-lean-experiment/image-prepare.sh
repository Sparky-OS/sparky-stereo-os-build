#!/bin/bash
# Prepare the immutable experiment environment, with network only during apt.
set -euo pipefail
export LC_ALL=C DEBIAN_FRONTEND=noninteractive
export DEBFULLNAME='Daniel Ramos (Capitain Jack)' DEBEMAIL=Capitain_Jack@yahoo.com
sh /run/https-only-apt.sh
cat >/etc/apt/sources.list.d/debian.sources <<'SOURCES'
Types: deb deb-src
URIs: https://snapshot.debian.org/archive/debian/20261112T000000Z/
Suites: testing
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.pgp
Check-Valid-Until: no
SOURCES
apt-get --error-on=any update
apt-cache policy devscripts dpkg-dev python3 linux-perf time python3-pyelftools zstd python3-yaml nodejs node-acorn git procps > /evidence/dependency-policy.txt
apt-get -y --no-install-recommends install devscripts dpkg-dev python3 linux-perf time python3-pyelftools zstd python3-yaml nodejs node-acorn git procps
mkdir -p /var/local/rl541-seed
for package in rustc cargo libstd-rust-1.98 libstd-rust-dev libstd-rust-61d1d3882fa5d346; do
    path=/seed/${package}_1.98.1+dfsg1-1+stereo3d1+lc1_amd64.deb
    test -f "$path"
    cp "$path" /var/local/rl541-seed/
done
(cd /var/local/rl541-seed && dpkg-scanpackages . >Packages)
printf 'deb [trusted=yes] file:/var/local/rl541-seed ./\n' >/etc/apt/sources.list.d/rl541-seed.list
printf 'Package: *\nPin: origin ""\nPin-Priority: 1001\n' >/etc/apt/preferences.d/rl541-seed
apt-get --error-on=any update
test "$(apt-cache policy rustc | awk '/Candidate:/ {print $2}')" = 1.98.1+dfsg1-1+stereo3d1+lc1
apt-get -y --no-install-recommends build-dep /source/rustc_1.99.1+dfsg1-1~exp1.dsc
test "$(dpkg-query -W -f='${Version}' rustc)" = 1.98.1+dfsg1-1+stereo3d1+lc1
test "$(dpkg-query -W -f='${Version}' cargo)" = 1.98.1+dfsg1-1+stereo3d1+lc1
id builder >/dev/null 2>&1 || useradd --uid 1000 --create-home builder
apt-cache policy libcap2-bin > /evidence/libcap-policy.txt
apt-get -y --no-install-recommends install libcap2-bin
setcap cap_sys_admin,cap_perfmon+ep /usr/bin/perf
dpkg-query -W > /evidence/image-packages.tsv
rustc -vV > /evidence/image-rustc.txt
perf --version > /evidence/image-perf.txt
cp /etc/apt/sources.list.d/debian.sources /evidence/image-snapshot.sources
apt-get clean
