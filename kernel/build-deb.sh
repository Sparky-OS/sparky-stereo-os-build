#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Builds the edition's kernel as Debian packages: vanilla Linux at a pinned tag, plus the patch series (kernel/series), with
# Debian's own configuration for the nearest kernel plus the edition's fragment (kernel/config, kernel/configure.sh). Runs in a
# container (kernel/docker/Dockerfile, built on first use) as the invoking user; the host is not touched.
#
#   kernel/build-deb.sh -b BUILD [-f base|v3|rt] [-o out-dir] [-k] [-t]
#
#   -b BUILD     build counter, part of the release name; a release name is never reused (the script stops if it exists)
#   -f FLAVOUR   base (default): generic x86-64; v3: x86-64-v3 (AVX2 and newer CPUs); rt: PREEMPT_RT (audio production)
#   -o OUT       output directory (default ${SPARKY_SCRATCH}/linux-stereo3d-out); packages land in OUT/<release>/
#   -k           keep the work directory (default: removed after a successful build)
#   -t           smoke test: a tiny kernel through the same packaging steps (see tests/package-smoke.sh), no series, no Debian configuration
#
# Release names (uname -r), chosen so that GRUB's version sort (sort -V, newest first) puts v3 above base above rt:
#   base  7.3.1-stereo3d<BUILD>            v3  7.3.1-stereo3d<BUILD>-v3            rt  7.3.1-rt-stereo3d<BUILD>   (v7.3.1; v7.3 gave 7.3.0-..., v7.3-rc6 7.3.0-rc6-...)
#
# Environment:
#   TAG, TAG_COMMIT   upstream tag and the commit it must point to (default v7.3.1, 79a90760...); move both together (kernel/lean/upstream.py pins them)
#   KERNEL_GIT        a git directory that has TAG (otherwise the tag is cloned from git.kernel.org, depth 1)
#   SERIES            patch series directory (default kernel/series); SKIP: regular expression of series lines to leave out
#   CPUS, MEM, JOBS   container limits (default 4, 16g) and make -j (default 4)
#   WORK              work directory (default ${SPARKY_SCRATCH}/linux-stereo3d-build)
#
# The packages are NOT signed. The kernel image is signed by whoever holds the Secure Boot key; the modules are already
# signed with a key that exists only during the build and is deleted before the script ends.
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
FLAVOUR=base; OUT=${SPARKY_SCRATCH:?}/linux-stereo3d-out; BUILD=; KEEP=0; SMOKE=0
while getopts b:f:o:kth opt; do
    case "$opt" in
        b) BUILD=$OPTARG;; f) FLAVOUR=$OPTARG;; o) OUT=$OPTARG;; k) KEEP=1;; t) SMOKE=1;;
        *) sed -n '2,/^set -eu/p' "$0" | sed 's/^# \{0,1\}//; /^set -eu/d'; exit 2;;
    esac
done
[ -n "$BUILD" ] || { echo "build-deb.sh: -b BUILD is required (a new number for every build)" >&2; exit 2; }
case "$BUILD" in *[!0-9]*|'') echo "build-deb.sh: BUILD must be a number" >&2; exit 2;; esac
TAG=${TAG:-v7.3.1}
TAG_COMMIT=${TAG_COMMIT:-79a907609d53d5cd645b42c11550d295d43abf99}
SERIES=${SERIES:-$HERE/series}
CPUS=${CPUS:-4}; MEM=${MEM:-16g}; JOBS=${JOBS:-4}
WORK=${WORK:-${SPARKY_SCRATCH:?}/linux-stereo3d-build}
IMAGE=${IMAGE:-sparky-kernel-build:1}

# version strings from the tag: v7.3-rc6 -> 7.3.0-rc6 (kernel) / 7.3.0~rc6 (Debian); v7.3 -> 7.3.0; v7.3.1 -> 7.3.1
T=${TAG#v}
case "$T" in
    *-rc*) KVER=$(echo "$T" | sed 's/^\([0-9]*\.[0-9]*\)-/\1.0-/'); DVER=$(echo "$KVER" | sed 's/-rc/~rc/');;
    *.*.*) KVER=$T; DVER=$T;;
    *) KVER=$T.0; DVER=$T.0;;
esac
case "$FLAVOUR" in
    base) LV=-stereo3d$BUILD;;
    v3) LV=-stereo3d$BUILD-v3;;
    rt) LV=-rt-stereo3d$BUILD;;
    *) echo "build-deb.sh: flavour must be base, v3 or rt" >&2; exit 2;;
esac
case "$KVER" in *-rc*) RELEASE=${KVER%%-rc*}-rc${KVER##*-rc}$LV;; *) RELEASE=$KVER$LV;; esac
PKGVER=$DVER-$BUILD

[ -d "$SERIES" ] && [ -f "$SERIES/series.txt" ] || { echo "build-deb.sh: no patch series at $SERIES" >&2; exit 2; }
[ ! -e "$OUT/$RELEASE" ] || { echo "build-deb.sh: $OUT/$RELEASE exists: a release name is never reused, take a new -b" >&2; exit 2; }
mkdir -p "$OUT" "$WORK"
# Disk floors. The build tree is the big thing: measured on the first builds, 20 GB for one flavour (with CONFIG_DEBUG_INFO_COMPRESSED_ZSTD=y; about 30 GB without), the
# packages 0.15 GB. WORK must have MIN_WORK_GB free (default 35: the tree and 15 GB to spare); OUT only MIN_OUT_GB (default 3), unless it is on the same file system as WORK,
# where the floor of WORK already covers it. (The first version asked 35 GB of both: a build whose packages go to a small disk and whose tree goes to a big one was refused.)
MIN_WORK_GB=${MIN_WORK_GB:-35}; MIN_OUT_GB=${MIN_OUT_GB:-3}
free_gb() { df -Pk "$1" | awk 'NR==2{print int($4/1048576)}'; }
fw=$(free_gb "$WORK")
[ "$fw" -ge "$MIN_WORK_GB" ] || { echo "build-deb.sh: only $fw GB free on $WORK (need $MIN_WORK_GB)" >&2; exit 3; }
if [ "$(df -Pk "$OUT" | awk 'NR==2{print $1}')" != "$(df -Pk "$WORK" | awk 'NR==2{print $1}')" ]; then
    fo=$(free_gb "$OUT")
    [ "$fo" -ge "$MIN_OUT_GB" ] || { echo "build-deb.sh: only $fo GB free on $OUT (need $MIN_OUT_GB)" >&2; exit 3; }
fi
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "== building the build image $IMAGE"
    docker build --platform linux/amd64 -t "$IMAGE" "$HERE/docker"
fi
rm -rf "$WORK/$RELEASE"; mkdir -p "$WORK/$RELEASE" "$OUT/$RELEASE"
echo "== release $RELEASE  package version $PKGVER  flavour $FLAVOUR  tag $TAG  cpus $CPUS  memory $MEM"
GITMOUNT=; [ -n "${KERNEL_GIT:-}" ] && GITMOUNT="-v $KERNEL_GIT:/kernel-git:ro"
# shellcheck disable=SC2086
docker run --rm --name "sparky-kernel-$RELEASE" --platform linux/amd64 --cpus "$CPUS" --memory "$MEM" --user "$(id -u):$(id -g)" \
    -v "$WORK/$RELEASE":/work -v "$OUT/$RELEASE":/out -v "$HERE":/kernel:ro -v "$SERIES":/series:ro $GITMOUNT \
    -e FLAVOUR="$FLAVOUR" -e BUILD="$BUILD" -e TAG="$TAG" -e TAG_COMMIT="$TAG_COMMIT" -e RELEASE="$RELEASE" -e LV="$LV" \
    -e PKGVER="$PKGVER" -e JOBS="$JOBS" -e SMOKE="$SMOKE" -e SKIP="${SKIP:-}" -e HAVE_KERNEL_GIT="${KERNEL_GIT:+1}" \
    "$IMAGE" sh /kernel/build-inner.sh 2>&1 | tee "$OUT/$RELEASE/build.log"
rc=$(cat "$OUT/$RELEASE/exit-status" 2>/dev/null || echo 1)
sync
if [ "$rc" != 0 ]; then echo "build-deb.sh: the build failed, see $OUT/$RELEASE/build.log (work kept in $WORK/$RELEASE)" >&2; exit 1; fi
[ "$KEEP" = 1 ] || rm -rf "$WORK/$RELEASE"
echo "== done: $OUT/$RELEASE"; ls -l "$OUT/$RELEASE"/*.deb
