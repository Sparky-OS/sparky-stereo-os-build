#!/bin/bash
# usage: ptff.sh <ffmpeg-image> <clip> <outname> : PeerTube's re-encode arguments (packages/ffmpeg: presetVOD, default libx264 profile) and the check of the result
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
img=$1; clip=$2; out=$3
docker run --rm --platform linux/amd64 --user $(id -u):$(id -g) -v ${SPARKY_WORKSPACES:?}/plasmatube:/w $img bash -c "
cd /w/pt-ff
echo '--- input $clip: stereo3d side data on the first frames and the keyframes'
ffprobe -v error -select_streams v -show_entries frame=pict_type,side_data_list -of compact=p=0 -read_intervals %+#60 /w/clips/$clip | grep -c 'Stereo 3D'
ffprobe -v error -select_streams v -show_entries frame=pict_type:frame_side_data=type,type -of compact=p=0 -read_intervals %+#3 /w/clips/$clip | head -3
echo '--- PeerTube re-encode'
ffmpeg -v error -y -i /w/clips/$clip -f mp4 -movflags faststart -max_muxing_queue_size 1024 -map_metadata -1 -pix_fmt yuv420p -an -c:v libx264 -vf scale=w=-2:h=720 -preset veryfast -maxrate:v 2000000 -bufsize:v 4000000 -b_strategy 1 -bf 16 -g:v 50 $out.mp4
echo '--- output: frames with Stereo 3D side data out of the first 60'
ffprobe -v error -select_streams v -show_entries frame=pict_type,side_data_list -of compact=p=0 -read_intervals %+#60 $out.mp4 | grep -c 'Stereo 3D'
ffprobe -v error -select_streams v -show_entries frame=pict_type:frame_side_data=type,type -of compact=p=0 -read_intervals %+#3 $out.mp4 | head -3
"
