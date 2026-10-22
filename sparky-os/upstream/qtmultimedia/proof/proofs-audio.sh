#!/bin/bash
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
cd ${SPARKY_SCRATCH:?}/qtmm-lane/run
{
echo "== audio: the sink format Qt chose and what PipeWire negotiated for the stream; offerable build (Qt's defaults) and the edition build (hi-fi defaults); a null sink of 48 kHz S32 (SINKRATE/SINKFMT) in a PipeWire of its own"
for t in offer final; do
  for c in a44k16.mkv a96k24.mkv a44kaac.mp4; do
    DEV=1 DEVDIR=/w/b-$t ./ra.sh au-$t-$c $c > ../out/au-$t-$c.txt 2>&1
    echo "[$t] $c (stream: $(ffprobe -v error -select_streams a -show_entries stream=sample_fmt,sample_rate,channels -of csv=p=0 ../clips/$c))"
    grep "Stream" ../out/au-$t-$c.txt | sed 's/^node Qml Runtime class=Stream\/Output\/Audio app=None -> /   PipeWire stream /'
    grep -h "audio sink format\|audio resampler" ../out/au-$t-$c/app.out | sed 's/^qt.multimedia.ffmpeg.utils: /   /' | cut -c1-330
  done
done
} > ../proof-audio.txt 2>&1
echo done > ../proofs-audio-done
