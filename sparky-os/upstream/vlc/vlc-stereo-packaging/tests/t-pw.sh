#!/bin/bash
# usage: t-pw.sh [vlc options...] ; PipeWire + pipewire-pulse + WirePlumber as on a Plasma desktop; null sinks of chosen format and rate
export HOME=/tmp/ph XDG_RUNTIME_DIR=/tmp/pr LANG=C.UTF-8; mkdir -p $HOME $XDG_RUNTIME_DIR; chmod 700 $XDG_RUNTIME_DIR
EX=("$@")
O=${OUT:-/w/run/audio/out-pw2}; mkdir -p $O
pipewire > $O/pw.log 2>&1 &
sleep 2; wireplumber > $O/wp.log 2>&1 &
sleep 3; pipewire-pulse > $O/pwp.log 2>&1 &
sleep 2
for spec in "s16le 44100" "float32le 48000" "s24le 96000" "float32le 192000" "s32le 48000" "s16le 96000"; do read f r <<< "$spec"
  pactl load-module module-null-sink sink_name=n${f}_$r format=$f rate=$r channels=2 sink_properties=device.description=n${f}_$r >/dev/null
done
[ -n "$FORCE" ] && { pw-metadata -n settings 0 clock.force-rate $FORCE >/dev/null; sleep 2; }
timeout 5 pactl list short sinks | awk '{print $2,$4,$5,$6}'
for sink in ${SINKS:-nfloat32le_48000 ns24le_96000 nfloat32le_192000 ns16le_44100 ns32le_48000 ns16le_96000}; do for f in ${FILES:-s24-96k.flac s16-44k.wav}; do
  tag=$sink-${f%%.*}${TAGX}
  PIPEWIRE_NODE=$sink PULSE_SINK=$sink timeout 30 ${VBIN:-vlc} -I dummy -vv --no-video --repeat "${EX[@]}" /w/run/audio/$f > $O/$tag.log 2>&1 &
  vp=$!
  sleep 6
  idx=$(timeout 5 pactl list short sinks | grep -w $sink | cut -f1)
  spec=$(timeout 5 pactl list short sink-inputs | awk -v i=$idx '$2==i {print $5,$6,$7}' | head -n 1)
  mod=$(grep -m1 -oE "using audio output module \"[a-z_]*\"" $O/$tag.log | sed 's/using audio output module //')
  sox=$(grep -m1 -oE "Using SoX Resampler with '[^']*' engine and '[^']*' quality" $O/$tag.log | sed "s/Using SoX Resampler with '[^']*' engine and //")
  echo "$sink $f: module $mod | server sees stream: ${spec:-none} | player resampler: ${sox:-none}"
  kill $vp 2>/dev/null; sleep 2; kill -9 $vp 2>/dev/null
done; done
