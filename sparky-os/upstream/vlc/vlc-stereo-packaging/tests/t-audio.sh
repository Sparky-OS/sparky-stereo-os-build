#!/bin/bash
# inside the installed-package container as the user: ALSA output formats against sinks that report their own
export HOME=/tmp/ah LANG=C.UTF-8; mkdir -p $HOME; cp /w/run/audio/asoundrc $HOME/.asoundrc
O=/w/run/audio/out; mkdir -p $O
run() { # tag sink file extra...
  tag=$1; sink=$2; f=$3; shift 3
  timeout 25 ${VBIN:-vlc} -I dummy -vv --no-video --aout=alsa --alsa-audio-device=$sink "$@" --play-and-exit /w/run/audio/$f > $O/$tag.log 2>&1
  fmt=$(sed -n '/final HW setup/,/initial software/p' $O/$tag.log | grep -E "^(FORMAT|RATE):" | tr '\n' ' ')
  dflt=$(sed -n '/initial hardware setup/,/final HW setup/p' $O/$tag.log | grep -E "^(FORMAT|RATE):" | cut -c1-60 | tr '\n' ' ')
  res=$(grep -m1 -oE "using audio resampler module \"[a-z_]*\"" $O/$tag.log)
  sox=$(grep -m1 -oE "Using SoX Resampler with '[^']*' engine and '[^']*' quality" $O/$tag.log)
  err=$(grep -c "alsa audio output error\|Audio output failed" $O/$tag.log)
  echo "$tag [$sink $f $*]"
  echo "    sink offers: $dflt"
  echo "    VLC opened : $fmt| ${res:-no resampler} ${sox:+| $sox}| errors: $err"
}
run a1 any48 s24-96k.flac
run a2 fmt_s32 s24-96k.flac
run a3 fmt_s16 s24-96k.flac
run a4 rate_44k s24-96k.flac
run a5 rate_96k s24-96k.flac
run a6 rate_192k s24-96k.flac
run a7 rate_44k s16-44k.wav
run a8 fmt_s16 s16-44k.wav
run a9 any48 s16-44k.wav
run a10 s16_44k s24-96k.flac
run a11 s16_44k s16-44k.wav
run b1 any48 s24-96k.flac --alsa-audio-rate=0 --alsa-audio-format=stream
run b2 fmt_s32 s16-44k.wav --alsa-audio-format=stream
run b3 any48 s24-96k.flac --alsa-audio-rate=96000
run b4 any48 s16-44k.wav --alsa-buffer-multiplier=4
# a default changed in the preferences file
mkdir -p $HOME/.config/vlc; echo "alsa-audio-rate=96000" > $HOME/.config/vlc/vlcrc
run c1 any48 s24-96k.flac
rm $HOME/.config/vlc/vlcrc
