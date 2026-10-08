#!/bin/sh
# In a fresh debian:testing container with deb-multimedia (the proof base), the repository at /repo, the edition's pins at /pins
# and the rig's clips at /clips: ffmpeg and mpv install from the repository, and both decode a clip with no display and no audio.
# Run as root in the container (apt needs it); prints what was installed and the exit codes.
export DEBIAN_FRONTEND=noninteractive
cp /pins/sparky-stereo /pins/sparky-stereo-only-ours /etc/apt/preferences.d/
echo 'deb [trusted=yes] file:/repo ./' >/etc/apt/sources.list.d/sparky-stereo.list
dpkg --add-architecture i386
apt-get update -qq 2>&1 | tail -n 2
apt-get -y --no-install-recommends install ffmpeg mpv >/tmp/i.log 2>&1; echo "install exit: $?"; tail -n 2 /tmp/i.log
dpkg -l ffmpeg mpv libmpv2 libavcodec63 libavutil61 libstereo-declare1 | awk '/^ii/{print $2, $3}'
echo "fdk packages: $(dpkg -l | grep -c -i '^ii.*fdk')"
echo "ffmpeg -encoders, aac: $(ffmpeg -hide_banner -encoders 2>/dev/null | grep -i aac | tr -s ' ' | tr '\n' ';')"
mpv --no-config --vo=null --ao=null --frames=30 --msg-level=all=error /clips/ord-sbs-L-g12.mp4; echo "mpv exit: $?"
mpv --no-config --vo=null --ao=null --frames=30 --msg-level=all=error /clips/hevc-sbs-L-g250.mkv; echo "mpv (HEVC, Matroska) exit: $?"
ffmpeg -v error -i /clips/ord-sbs-L-g12.mp4 -f null -; echo "ffmpeg exit: $?"
