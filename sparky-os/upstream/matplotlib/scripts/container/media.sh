export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null; apt-get -y install --no-install-recommends python3-matplotlib python3-numpy python3-pil ffmpeg mkvtoolnix >/dev/null 2>&1
cat > /tmp/m.sh <<'EOS'
export HOME=/tmp MPLCONFIGDIR=/tmp/mpl
cd /w && rm -rf build/pb/media && python3 scripts/make_playback_media.py build/pb/media && ls build/pb/media
for f in stereo.mkv stereo.mp4; do ffprobe -v error -show_entries stream=codec_name,profile,pix_fmt,width,height -of csv=p=0 build/pb/media/$f; done
mkvinfo build/pb/media/stereo.mkv | grep -i "stereo mode"
EOS
setpriv --reuid=1000 --regid=1000 --clear-groups bash /tmp/m.sh
