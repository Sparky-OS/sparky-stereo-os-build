#!/bin/bash
# Builds the test clips (host ffmpeg + mkvpropedit) into $1 (default ${SPARKY_SCRATCH}/bino-lane/clips).
# Left eye: red with LEFT, right eye: blue with RIGHT, plus a white frame and a yellow bar at the
# left edge of each eye so a crop or a mirror shows.
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -e
out=${1:-${SPARKY_SCRATCH:?}/bino-lane/clips}; mkdir -p $out; cd $out
F=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf
W=960; H=540
eye() { # name colour text
  ffmpeg -v error -y -f lavfi -i "color=c=$2:s=${W}x${H}:r=25:d=60,drawbox=x=0:y=0:w=$W:h=$H:color=white:t=8,drawbox=x=8:y=8:w=60:h=$((H-16)):color=yellow:t=fill,drawtext=fontfile=$F:text='$3':fontsize=200:fontcolor=white:x=(w-text_w)/2:y=(h-text_h)/2" -c:v ffv1 $1.mkv
}
eye eyeL 0xc02020 LEFT
eye eyeR 0x2020c0 RIGHT
enc="-c:v libx264 -preset fast -crf 14 -pix_fmt yuv420p"
# left first
ffmpeg -v error -y -i eyeL.mkv -i eyeR.mkv -filter_complex hstack $enc sbs-L.mkv
ffmpeg -v error -y -i eyeL.mkv -i eyeR.mkv -filter_complex vstack $enc tb-L.mkv
# right first (right eye in the first half)
ffmpeg -v error -y -i eyeR.mkv -i eyeL.mkv -filter_complex hstack $enc sbs-R.mkv
ffmpeg -v error -y -i eyeR.mkv -i eyeL.mkv -filter_complex vstack $enc tb-R.mkv
# H.264 frame packing SEI (x264 frame-packing: 3 side by side, 4 top and bottom), left first; no Matroska tag
ffmpeg -v error -y -i eyeL.mkv -i eyeR.mkv -filter_complex hstack $enc -x264-params frame-packing=3 sei-sbs-L.mp4
ffmpeg -v error -y -i eyeL.mkv -i eyeR.mkv -filter_complex vstack $enc -x264-params frame-packing=4 sei-tb-L.mp4
# half side by side, 960x540 (each eye squeezed to 480x540), SEI only
ffmpeg -v error -y -i eyeL.mkv -i eyeR.mkv -filter_complex "[0:v]scale=480:540[a];[1:v]scale=480:540[b];[a][b]hstack" $enc -x264-params frame-packing=3 sei-halfsbs-L.mp4
# Matroska StereoMode (1 left-right, 11 right-left, 3 top-bottom, 2 bottom-top)
cp sbs-L.mkv sbs-L-tag.mkv; mkvpropedit sbs-L-tag.mkv --edit track:v1 --set display-width=960 --set display-height=540 --set stereo-mode=1 >/dev/null
cp sbs-R.mkv sbs-R-tag.mkv; mkvpropedit sbs-R-tag.mkv --edit track:v1 --set display-width=960 --set display-height=540 --set stereo-mode=11 >/dev/null
cp tb-L.mkv tb-L-tag.mkv;   mkvpropedit tb-L-tag.mkv --edit track:v1 --set display-width=960 --set display-height=540 --set stereo-mode=3 >/dev/null
cp tb-R.mkv tb-R-tag.mkv;   mkvpropedit tb-R-tag.mkv --edit track:v1 --set display-width=960 --set display-height=540 --set stereo-mode=2 >/dev/null
# stereo 360: two equirectangular spheres 1920x960, top and bottom, left on top
sph() { # name colour label
  local t=""
  for lon in 0 90 180 270; do
    t="$t,drawtext=fontfile=$F:text='$3 $lon':fontsize=90:fontcolor=white:x=$((960 + lon*1920/360 - 150)):y=430"
  done
  # the 180 degree seam wraps: draw it also at x=-... (lon 180 is at the edge)
  ffmpeg -v error -y -f lavfi -i "color=c=$2:s=1920x960:r=25:d=60,drawbox=x=0:y=478:w=1920:h=4:color=white:t=fill,drawbox=x=958:y=0:w=4:h=960:color=yellow:t=fill,drawbox=x=0:y=0:w=1920:h=60:color=white:t=fill,drawbox=x=0:y=900:w=1920:h=60:color=white:t=fill$t" -c:v ffv1 $1.mkv
}
sph sphL 0xc02020 LEFT
sph sphR 0x2020c0 RIGHT
ffmpeg -v error -y -i sphL.mkv -i sphR.mkv -filter_complex vstack $enc sphere-stereo.mkv
mkvpropedit sphere-stereo.mkv --edit track:v1 --set display-width=1920 --set display-height=960 --set stereo-mode=3 --set projection-type=1 >/dev/null
# VR180: two 180 degree eyes 960x960 side by side, left first
vr() {
  local t=""
  for lon in -60 -30 0 30 60; do
    t="$t,drawtext=fontfile=$F:text='$3 $lon':fontsize=44:fontcolor=white:x=$((480 + lon*960/180 - 80)):y=450"
  done
  ffmpeg -v error -y -f lavfi -i "color=c=$2:s=960x960:r=25:d=60,drawbox=x=0:y=478:w=960:h=4:color=white:t=fill,drawbox=x=478:y=0:w=4:h=960:color=yellow:t=fill$t" -c:v ffv1 $1.mkv
}
vr vrL 0xc02020 LEFT
vr vrR 0x2020c0 RIGHT
ffmpeg -v error -y -i vrL.mkv -i vrR.mkv -filter_complex hstack $enc dome-stereo.mkv
mkvpropedit dome-stereo.mkv --edit track:v1 --set display-width=960 --set display-height=960 --set stereo-mode=1 --set projection-type=1 >/dev/null
rm -f eyeL.mkv eyeR.mkv sphL.mkv sphR.mkv vrL.mkv vrR.mkv
ls -la
