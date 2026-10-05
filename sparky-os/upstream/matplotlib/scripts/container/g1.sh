export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null; apt-get -y install --no-install-recommends ffmpeg >/dev/null 2>&1
cd /pb/media && ffmpeg -y -loglevel error -framerate 4 -i frames/frame_%05d.png -pix_fmt yuv420p -c:v libx264 -crf 18 -x264-params frame-packing=3:keyint=1 stereo-g1.mp4 && ls -la stereo-g1.mp4
ffprobe -v error -select_streams v:0 -show_entries frame=pict_type:frame_side_data_list -of compact stereo-g1.mp4 | cut -c1-120
chmod a+r stereo-g1.mp4
