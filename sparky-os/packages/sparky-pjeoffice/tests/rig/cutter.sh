#!/bin/bash
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
# As the person (uid 1000) in a container with sparky-pjeoffice and sparky-pjeoffice-codec installed from their .deb files, no network, a private Xvfb and an
# ALSA null device (no sound device exists): PJeOffice Pro's JavaFX media loader without and with the package's private codec libraries, then the program's own
# cutter on a generated MP4. Usage: cutter.sh OUT   Needs /classes (MediaProbe, CutterTaskProbe), /scratch (rw)
set -u
OUT=${1:?result folder}; mkdir -p "$OUT"; ulimit -c 0
export DISPLAY=:99
APP=/opt/pjeoffice-pro/current; JAVA=$APP/jre/bin/java; CODEC=/usr/lib/sparky-pjeoffice/codec
Xvfb :99 -screen 0 1280x800x24 -nolisten tcp > "$OUT/xvfb.log" 2>&1 &
sleep 1
mkdir -p "$HOME"; printf 'pcm.!default { type null }\nctl.!default { type hw card 0 }\n' > "$OUT/asound.conf"; export ALSA_CONFIG_PATH="$OUT/asound.conf"
FAIL=0
t() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1   [$2]"; FAIL=1; fi; }
ffmpeg -v error -f lavfi -i testsrc=duration=6:size=320x240:rate=25 -f lavfi -i sine=frequency=440:duration=6 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest /scratch/clip.mp4
t "the generated clip is H.264 and AAC" "ffprobe -v error -show_entries stream=codec_name -of csv=p=0 /scratch/clip.mp4 | sort | tr '\n' ' ' | grep -q 'aac h264'"
echo "== 1. the program's JavaFX Media without the private libraries (red) and with them (green)"
LD_LIBRARY_PATH= timeout 60 $JAVA -Dpjeoffice_home=$APP -cp /classes:$APP/pjeoffice-pro.jar:$APP/cutplayer4jfx.jar MediaProbe /scratch/clip.mp4 > "$OUT/media-without.txt" 2>&1; RC=$?
t "without them JavaFX cannot create the player" "[ $RC != 0 ] && grep -q -E 'MediaException|Could not create player' $OUT/media-without.txt"
LD_LIBRARY_PATH=$CODEC timeout 60 $JAVA -Dpjeoffice_home=$APP -cp /classes:$APP/pjeoffice-pro.jar:$APP/cutplayer4jfx.jar MediaProbe /scratch/clip.mp4 > "$OUT/media-with.txt" 2>&1; RC=$?
t "with them the player is READY and knows the duration" "[ $RC = 0 ] && grep -q 'READY duration=6' $OUT/media-with.txt"
LD_LIBRARY_PATH=$CODEC timeout 60 $JAVA -cp /classes:$APP/pjeoffice-pro.jar PlayProbe /scratch/clip.mp4 4000 > "$OUT/play-with.txt" 2>&1; RC=$?
t "JavaFX plays the clip: the playback clock advances" "[ $RC = 0 ] && grep -q 'PLAYED currentTime=' $OUT/play-with.txt"
echo "== 2. the program's own cutter, started the way the launcher starts the program (the codec folder on that process's library path only)"
LD_LIBRARY_PATH=$CODEC $JAVA -Djfxmedia.loglevel=debug -Xmx1g -Dpjeoffice_home=$APP -Dffmpeg_home=/var/lib/sparky-pjeoffice/ffmpeg -Dcutplayer4j_looksandfeels=Nimbus -cp /classes:$APP/pjeoffice-pro.jar:$APP/cutplayer4jfx.jar CutterTaskProbe /scratch/clip.mp4 > "$OUT/cutter.log" 2>&1 &
CUT=$!
sleep 14; import -window root "$OUT/cutter-playing.png"
xdotool search --name '.' getwindowname %@ | sort | uniq -c > "$OUT/cutter-windows.txt"
echo "$CUT" > "$OUT/cutter.pid"
python3 /rig/drive-cutter.py "$OUT"
CUTFILE=$(ls /scratch/cuts/*.mp4 2>/dev/null | head -1)
t "the cutter saved a file" "[ -n \"$CUTFILE\" ]"
ffprobe -v error -show_entries stream=codec_name:format=duration -of default=nw=1 "$CUTFILE" > "$OUT/cut-ffprobe.txt" 2>&1
t "the saved cut is H.264 and AAC and about 3 seconds" "grep -q codec_name=h264 $OUT/cut-ffprobe.txt && grep -q codec_name=aac $OUT/cut-ffprobe.txt && awk -F= '/^duration/{exit !(\$2>2.9 && \$2<3.3)}' $OUT/cut-ffprobe.txt"
ffmpeg -v error -i "$CUTFILE" -f null - > "$OUT/cut-decode.txt" 2>&1; RC=$?
t "an independent full decode of the cut reports nothing" "[ $RC = 0 ] && [ ! -s $OUT/cut-decode.txt ]"
kill $CUT 2>/dev/null
echo; [ $FAIL = 0 ] && echo "RESULT: PASS (cutter, media)" || echo "RESULT: FAIL (cutter, media)"
exit $FAIL
