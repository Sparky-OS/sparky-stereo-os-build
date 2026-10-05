#!/bin/bash
# inside vlc-both:1 as the user: the original VLC and VLC Stereo side by side
export HOME=/tmp/sbs LANG=C.UTF-8 XDG_RUNTIME_DIR=/tmp/pr; rm -rf $HOME; mkdir -p $HOME $XDG_RUNTIME_DIR; chmod 700 $XDG_RUNTIME_DIR
O=/w/run/audio/out-sbs; mkdir -p $O
echo "== versions and libraries"
vlc --version 2>&1 | head -n 1; vlc-stereo --version 2>&1 | head -n 1
echo "vlc          libvlccore -> $(ldd /usr/lib/x86_64-linux-gnu/vlc/plugins/misc/libxdg_screensaver_plugin.so 2>/dev/null | grep -o '/[^ ]*libvlccore[^ ]*' | head -n 1)"
echo "vlc-stereo   libvlccore -> $(ldd /usr/bin/vlc-stereo | grep -o '/[^ ]*libvlccore[^ ]*' | head -n 1)"
echo "== settings: each writes only its own directory"
vlc -I dummy --reset-config --play-and-exit /w/run/audio/s16-44k.wav >/dev/null 2>&1
vlc-stereo -I dummy --reset-config --play-and-exit /w/run/audio/s16-44k.wav >/dev/null 2>&1
(cd $HOME; find .config .cache .local -type f 2>/dev/null | sort)
# a preference changed in each (what the preferences dialog does: it rewrites the file of its own program)
sed -i 's/^#audio-replay-gain-mode=.*/audio-replay-gain-mode=track/' ~/.config/vlc/vlcrc
a=$(md5sum < ~/.config/vlc/vlcrc)
sed -i 's/^#audio-replay-gain-mode=.*/audio-replay-gain-mode=album/; s/^#alsa-audio-rate=.*/alsa-audio-rate=96000/' ~/.config/vlc-stereo/vlcrc
echo "vlc        vlcrc: $(grep -E '^audio-replay-gain-mode' ~/.config/vlc/vlcrc | tr '\n' ' ')"
echo "vlc-stereo vlcrc: $(grep -E '^audio-replay-gain-mode|^alsa-audio-rate' ~/.config/vlc-stereo/vlcrc | tr '\n' ' ')"
[ "$a" = "$(md5sum < ~/.config/vlc/vlcrc)" ] && echo "vlc-stereo's change left vlc's vlcrc untouched (md5 equal)"
b=$(md5sum < ~/.config/vlc-stereo/vlcrc)
vlc -I dummy --play-and-exit /w/run/audio/s16-44k.wav >/dev/null 2>&1
vlc-stereo -I dummy --play-and-exit /w/run/audio/s16-44k.wav >/dev/null 2>&1
[ "$b" = "$(md5sum < ~/.config/vlc-stereo/vlcrc)" ] && echo "running vlc and vlc-stereo changed neither file (md5 equal)"
echo "vlc-stereo reads its own file: ALSA sink opened at: $(HOME=$HOME vlc-stereo -I dummy -vv --no-video --aout=alsa --alsa-audio-device=null /w/run/audio/s24-96k.flac --play-and-exit 2>&1 | sed -n '/final HW setup/,/initial software/p' | grep -E '^RATE' | tr '\n' ' ')  (default 48000)"
echo "== both at once, on PipeWire"
pipewire > $O/pw.log 2>&1 &
sleep 2; wireplumber > $O/wp.log 2>&1 &
sleep 3; pipewire-pulse > $O/pwp.log 2>&1 &
sleep 2
pactl load-module module-null-sink sink_name=n96k format=s24le rate=96000 channels=2 >/dev/null
pactl load-module module-null-sink sink_name=n48k format=float32le rate=48000 channels=2 >/dev/null
export PULSE_SINK=n96k PIPEWIRE_NODE=n96k
dbus-run-session -- bash -c '
vlc -I dummy --control dbus --no-video --repeat -vv /w/run/audio/s24-96k.flac > '$O'/both-vlc.log 2>&1 &
vlc-stereo -I dummy --control dbus --no-video --repeat -vv /w/run/audio/s24-96k.flac > '$O'/both-stereo.log 2>&1 &
sleep 8
echo "bus names:"; dbus-send --session --dest=org.freedesktop.DBus --print-reply /org/freedesktop/DBus org.freedesktop.DBus.ListNames | grep -o "org.mpris[^\"]*"
echo "audio output chosen: vlc $(grep -m1 -oE "using audio output module \"[a-z_]*\"" '$O'/both-vlc.log | sed "s/.*module //") | vlc-stereo $(grep -m1 -oE "using audio output module \"[a-z_]*\"" '$O'/both-stereo.log | sed "s/.*module //")"
echo "sink-inputs on the sink: $(pactl list short sink-inputs | wc -l)"; pactl list short sink-inputs | awk "{print \"  \", \$4, \$5, \$6, \$7}"
echo "both processes alive: $(pgrep -c -x vlc) vlc, $(pgrep -c -x vlc-stereo) vlc-stereo"
pkill -x vlc; pkill -x vlc-stereo; sleep 1'
