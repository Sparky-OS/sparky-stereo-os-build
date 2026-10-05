#!/bin/bash
# B: the rate of our stream against the rate of the graph, read from the server (pw-top). Env: VBIN, CASES
export HOME=/tmp/ph XDG_RUNTIME_DIR=/tmp/pr LANG=C.UTF-8; mkdir -p $HOME $XDG_RUNTIME_DIR; chmod 700 $XDG_RUNTIME_DIR
O=${OUT:-/w/run/b/out}; mkdir -p $O
pipewire > $O/pw.log 2>&1 &
sleep 2; wireplumber > $O/wp.log 2>&1 &
sleep 3; pipewire-pulse > $O/pwp.log 2>&1 &
sleep 2
pw-cli create-node adapter '{ factory.name=support.null-audio-sink node.name=flex media.class=Audio/Sink object.linger=true audio.position=[FL FR] priority.session=3000 }' >/dev/null
sleep 1
read_top() { pw-top -b -n 2 2>/dev/null | tail -n 8; }
run_case() { # tag force allowed file other
  tag=$1; force=$2; allowed=$3; f=$4; other=$5
  pw-metadata -n settings 0 clock.force-rate $force >/dev/null
  pw-metadata -n settings 0 clock.allowed-rates "$allowed" >/dev/null
  sleep 1
  if [ "$other" = yes ]; then
    ( while true; do pw-play --target flex --rate 48000 /w/run/audio/s16-44k.wav >/dev/null 2>&1; done ) &
    other_pid=$!; sleep 3
  fi
  PIPEWIRE_NODE=flex timeout 40 ${VBIN:-vlc-stereo} -I dummy -vv --no-video --repeat /w/run/audio/$f > $O/$tag.log 2>&1 &
  vp=$!; sleep 7
  top=$(read_top)
  ours=$(echo "$top" | grep -E "^R .*VLC media player" | awk '{for(i=1;i<=NF;i++) if ($i ~ /^F32LE|^S16LE|^S32LE/) {print $i, $(i+1), $(i+2); break}}')
  drv=$(echo "$top" | grep -E "^R .* flex" | awk '{print $4}' | tail -n 1)
  sox=$(grep -m1 -oE "Using SoX Resampler" $O/$tag.log >/dev/null && echo yes || echo no)
  frate=$(grep -m1 -oE "input '[a-z0-9]*' [0-9]+" $O/$tag.log | awk '{print $3}')
  echo "$tag: force=$force allowed=$allowed file=$f(${frate}Hz) other-stream=$other | graph(driver) ${drv:-?} Hz | our stream (server): ${ours:-?}"
  kill $vp 2>/dev/null; [ "$other" = yes ] && { kill $other_pid 2>/dev/null; pkill -f "pw-play" ; }; sleep 3; kill -9 $vp 2>/dev/null
}
for forced in 96000 192000; do for f in s16-44k.wav s24-96k.flac; do for other in no yes; do
  run_case F${forced}-${f%%.*}-$other $forced "[ 48000 ]" $f $other
done; done; done
