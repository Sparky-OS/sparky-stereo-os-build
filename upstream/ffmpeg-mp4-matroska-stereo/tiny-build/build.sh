#!/bin/sh
# a minimal FFmpeg 9.0.2 (demuxers mov and matroska, muxers mp4 matroska null, ffmpeg and ffprobe) built twice: as it is, and with candidate.diff
# Usage: W=some folder; unpack ffmpeg-dmo_9.0.2.orig.tar.xz in $W (it makes $W/ffmpeg-9.0.2); copy candidate.diff, build.sh and test.sh there; then
#   docker run --rm --cpus 2 -v $W:/w mdmo-base:1 nice -n 10 sh /w/build.sh        (about 7 minutes; binaries in $W/bin-base and $W/bin-patched)
#   docker run --rm --cpus 1 -v $W:/w -v PROBE-FILES:/p:ro -v FIXTURES:/fx:ro mdmo-base:1 sh /w/test.sh
# (mdmo-base:1 is a debian:testing with gcc and make: sparky-os/media/docker/Dockerfile.base)
set -e
cd /w/ffmpeg-9.0.2
./configure --disable-everything --disable-autodetect --disable-doc --disable-debug --disable-x86asm --disable-network \
  --enable-ffmpeg --enable-ffprobe --enable-protocol=file --enable-demuxer=mov,matroska --enable-muxer=mp4,matroska,null \
  --enable-parser=h264,hevc,aac --enable-filter=null,anull,buffer,buffersink,abuffer,abuffersink,format,aformat >/w/configure.log 2>&1 || { tail -n 20 /w/configure.log; exit 1; }
make -j2 ffmpeg ffprobe >/w/make-base.log 2>&1 || { tail -n 30 /w/make-base.log; exit 1; }
mkdir -p /w/bin-base && cp ffmpeg ffprobe /w/bin-base/
patch -p1 < /w/candidate.diff
make -j2 ffmpeg ffprobe >/w/make-patched.log 2>&1 || { tail -n 30 /w/make-patched.log; exit 1; }
mkdir -p /w/bin-patched && cp ffmpeg ffprobe /w/bin-patched/
echo built
/w/bin-base/ffprobe -version | head -n 1; /w/bin-patched/ffprobe -version | head -n 1
