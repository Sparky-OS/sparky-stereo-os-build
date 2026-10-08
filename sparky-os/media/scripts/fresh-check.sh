#!/bin/sh
# In a fresh debian:testing container (root) with deb-multimedia's repository (the proofbase image) and the Sparky Stereo OS
# repository mounted at /repo with the edition's pins (/etc/apt/preferences.d): what apt decides about the media stack.
export DEBIAN_FRONTEND=noninteractive
set -u
cp /pins/sparky-stereo /pins/sparky-stereo-only-ours /etc/apt/preferences.d/
echo 'deb [trusted=yes] file:/repo ./' > /etc/apt/sources.list.d/sparky-stereo.list
dpkg --add-architecture i386
apt-get update -qq 2>&1 | tail -3
echo "=== the pin file for FFmpeg that was dropped: $(ls /etc/apt/preferences.d | tr '\n' ' ')"
echo "=== candidates"
for p in ffmpeg ffplay libavcodec63 libavformat63 libavutil61 libswscale10 libswresample7 libavfilter12 libavdevice63 libavcodec-dev mpv libmpv2 libmpv-dev; do printf "%-16s %s\n" $p "$(apt-cache policy $p | awk '/Candidate/{print $2}')"; done
echo "=== i386 candidates"
for p in libavcodec63:i386 libavformat63:i386 libavutil61:i386 libswscale10:i386 libswresample7:i386 libavfilter12:i386 libavdevice63:i386 libavcodec-dev:i386; do printf "%-24s %s\n" $p "$(apt-cache policy $p | awk '/Candidate/{print $2}')"; done
echo "=== who still needs FFmpeg 8.1's libraries (libavcodec62 family) in Debian testing"
apt-cache rdepends libavcodec62 libavformat62 libavutil60 libswscale9 libavfilter11 libavdevice62 2>/dev/null | grep -E "^  " | sort -u | tr '\n' ' '; echo
echo "=== Debian's libavcodec62 available: $(apt-cache policy libavcodec62 | awk '/Candidate/{print $2}')"
echo "=== simulations (apt-get -s install)"
sim() { echo "--- $*"; apt-get -s install "$@" 2>&1 | grep -E "^(E:|The following (packages will be REMOVED|NEW packages|packages will be upgraded|packages will be DOWNGRADED)|[0-9]+ upgraded|Remv|Inst (ffmpeg|mpv|libav|libsw|libmpv|libplacebo))" | cut -c1-150 | head -${LINES_MAX:-25}; }
sim ffmpeg mpv
sim ffmpeg:i386 libavcodec63:i386
sim blender
sim obs-studio
sim handbrake handbrake-gtk
sim vlc
sim vlc-stereo
sim kdenlive audacity
sim gstreamer1.0-libav
sim libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libswresample-dev libavfilter-dev libavdevice-dev
sim libavcodec-dev:i386 libavutil-dev:i386
sim libmpv-dev haruna bino dragonplayer
sim kodi cyanrip baresip-ffmpeg
sim ffmpeg libavcodec63:i386 libavformat63:i386 libavutil61:i386
sim libavcodec62 libavutil60 libavformat62 libswscale9 ffmpeg
