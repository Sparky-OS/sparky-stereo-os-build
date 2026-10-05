export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null; apt-get -y install --no-install-recommends python3-matplotlib python3-numpy python3-pil ffmpeg mkvtoolnix >/dev/null 2>&1
cat > /tmp/p.sh <<'EOS'
export HOME=/tmp MPLCONFIGDIR=/tmp/mpl
cd /w && python3 scripts/prove_stereo.py > build/pb/out/prove.txt 2>&1; echo prove rc=$?
mkvinfo build/test/stereo.mkv > evidence/mkvinfo-stereo.txt
ffprobe -v error -select_streams v:0 -show_entries stream_tags=stereo_mode -of default=nw=1 build/test/stereo.mkv > evidence/ffprobe-matroska-tags.txt
ffprobe -v error -show_entries stream=codec_name,width,height,pix_fmt:stream_side_data=type,inverted,view -of json build/test/stereo.mkv > evidence/ffprobe-matroska.json
ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height,pix_fmt -of json build/test/stereo.mp4 > evidence/ffprobe-mp4.json
ffmpeg -hide_banner -i build/test/stereo.mp4 -c:v copy -bsf:v trace_headers -frames:v 1 -f null - 2>&1 | grep -A12 "Frame Packing Arrangement" | head -14 > evidence/h264-frame-packing.txt
grep -E "frame_packing_arrangement_type" evidence/h264-frame-packing.txt
grep -E "stereo mode|Pixel (width|height)" evidence/mkvinfo-stereo.txt
cat evidence/ffprobe-matroska-tags.txt
EOS
setpriv --reuid=1000 --regid=1000 --clear-groups bash /tmp/p.sh
