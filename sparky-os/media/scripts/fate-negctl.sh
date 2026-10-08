#!/bin/sh
# The command lines of four of the new FATE tests (tests/fate/*.mak), run with the ffmpeg and ffprobe of the image
# and compared with the reference files (tests/ref/fate): the packaged binaries must match, the unpatched ones must not.
S=/samples; R=/ref; T=/tmp/fn; mkdir -p $T; cd $T
sh_() { sed -n "s/^.* n: *\([0-9]*\) .*/frame \1/p; s/^.*side data - Stereo 3D: //p" "$1"; }
run_ff() { ffmpeg -nostdin -nostats -threads 4 -thread_type frame+slice -i "$1" -vf showinfo -f null - > /dev/null 2> $T/log; sh_ $T/log; }
chk() { if diff -q "$2" "$T/out" >/dev/null; then echo "MATCH   $1"; else echo "DIFFERS $1 ($(diff "$2" "$T/out" | grep -c '^[<>]') lines differ)"; fi; }
run_ff $S/h264/frame-packing-output-order.h264 > $T/out; chk h264-frame-packing-order $R/h264-frame-packing-order
ffprobe -bitexact -threads 4 -show_frames -show_entries frame=side_data_list:frame_tags= -of compact $S/h264/frame-packing-persistence.h264 > $T/out 2>/dev/null; chk h264-frame-packing-persistence $R/h264-frame-packing-persistence
ffprobe -bitexact -threads 4 -show_frames -show_entries frame=side_data_list:frame_tags= -of compact $S/hevc/frame-packing-persistence.hevc > $T/out 2>/dev/null; chk hevc-frame-packing-persistence $R/hevc-frame-packing-persistence
{ echo "sequence:"; run_ff $S/hevc/frame-packing-sequence.hevc; echo "current picture only:"; run_ff $S/hevc/frame-packing-current-only.hevc; echo "changed:"; run_ff $S/hevc/frame-packing-changed.hevc; } > $T/out; chk hevc-frame-packing-lifetime $R/hevc-frame-packing-lifetime
