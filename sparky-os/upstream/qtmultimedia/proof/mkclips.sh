#!/bin/bash
# the test clips of this round that the earlier rounds did not have (the others: kde-sei-wave's mkclips.sh and plank-player's clips),
# in clips/ of the lane's work dir. Frame numbers and LEFT/RIGHT colours come from the earlier clips; these are for depth, chroma and scaling.
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
set -e
cd ${SPARKY_SCRATCH:?}/qtmm-lane/clips
# looped copies of the earlier non-looped clips (Dragon Player does not loop), SEI NAL units removed for the Matroska sequences
for f in sei-*.mp4 mkv-*.mkv hevc-sbs-L.mp4 2d.mp4 plain-*.mp4 plain-*.mkv; do [ -f "$f" ] && [ ! -f "Z-$f" ] && ffmpeg -v error -y -stream_loop 5 -i $f -c copy "Z-$f"; done
for c in L R; do ffmpeg -v error -y -i Z-mkv-seq-$c.mkv -c copy -bsf:v filter_units=remove_types=6 Zn-mkv-seq-$c.mkv; mkvpropedit -q Zn-mkv-seq-$c.mkv --edit track:v1 --set stereo-mode=$([ $c = L ] && echo 13 || echo 14); done
# gray ramps, side by side full (each eye 1280x720 ramp), Matroska StereoMode 1 with the display size of one eye (without it FFmpeg doubles the sample aspect ratio)
SBS="--edit track:v1 --set stereo-mode=1 --set display-width=1280 --set display-height=720"
RAMP="color=c=gray:s=2560x720:r=25:d=3"
ffmpeg -v error -y -f lavfi -i "$RAMP,format=yuv420p,geq=lum='16+219*mod(X\,1280)/1279':cb=128:cr=128" -c:v libx264 -qp 0 -pix_fmt yuv420p ramp8-sbs.mkv
ffmpeg -v error -y -f lavfi -i "$RAMP,format=yuv420p10le,geq=lum='64+876*mod(X\,1280)/1279':cb=512:cr=512" -c:v libx265 -x265-params lossless=1:log-level=error -pix_fmt yuv420p10le ramp10-sbs.mkv
ffmpeg -v error -y -f lavfi -i "$RAMP,format=yuv420p12le,geq=lum='256+3504*mod(X\,1280)/1279':cb=2048:cr=2048" -c:v libx265 -x265-params lossless=1:log-level=error -pix_fmt yuv420p12le ramp12-sbs.mkv
ffmpeg -v error -y -f lavfi -i "$RAMP,format=yuv420p16le,geq=lum='4096+56064*mod(X\,1280)/1279':cb=32768:cr=32768" -c:v ffv1 -pix_fmt yuv420p16le ramp16-sbs.mkv
ffmpeg -v error -y -f lavfi -i "$RAMP,format=yuv444p10le,geq=lum='64+876*mod(X\,1280)/1279':cb=512:cr=512" -c:v libx265 -x265-params lossless=1:log-level=error -pix_fmt yuv444p10le ramp10-444-sbs.mkv
ffmpeg -v error -y -f lavfi -i "$RAMP,format=yuv420p10le,geq=lum='64+876*mod(X\,1280)/1279':cb=512:cr=512" -c:v libx265 -x265-params lossless=1:log-level=error:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc -pix_fmt yuv420p10le ramp10-pq-sbs.mkv
ffmpeg -v error -y -f lavfi -i "$RAMP,format=yuv420p10le,geq=lum='64+876*mod(X\,1280)/1279':cb=512:cr=512" -c:v libx265 -x265-params "lossless=1:log-level=error:colorprim=bt2020:transfer=arib-std-b67:colormatrix=bt2020nc" -pix_fmt yuv420p10le ramp10-hlg-sbs.mkv
for f in ramp*-sbs.mkv; do mkvpropedit -q $f $SBS; done
# one pixel red and blue lines (chroma resolution): horizontal lines H, vertical V, 4:4:4 and 4:2:2 and 4:2:0, 8 and 10 bits
for axis in H V; do E=$([ $axis = H ] && echo 'mod(X,2)' || echo 'mod(Y,2)')
  G="color=c=black:s=2560x720:r=25:d=4,format=gbrp,geq=r='255*(1-$E)':g='0':b='255*$E'"
  for spec in "yuv444p10le 444p10" "yuv422p10le 422p10" "yuv420p10le 420p10" "yuv444p 444p8"; do set -- $spec
    ffmpeg -v error -y -f lavfi -i "$G" -vf "scale=out_color_matrix=bt709:out_range=pc,format=$1" -c:v libx265 -x265-params lossless=1:log-level=error -pix_fmt $1 -colorspace bt709 -color_range pc chroma$axis-$2-sbs.mkv 2>/dev/null || ffmpeg -v error -y -f lavfi -i "$G" -vf "scale=out_color_matrix=bt709:out_range=pc,format=$1" -c:v libx264 -qp 0 -pix_fmt $1 chroma$axis-$2-sbs.mkv
    mkvpropedit -q chroma$axis-$2-sbs.mkv $SBS; done; done
# the upscale clip: a half side by side video (SEI), both halves the same eye (640x720 of the 1280x720 test picture), no sample aspect ratio
ffmpeg -v error -y -f lavfi -i "testsrc2=s=1280x720:r=1:d=1" -frames:v 1 ../ref/truth.png
ffmpeg -v error -y -i ../ref/truth.png -vf "scale=640:720:flags=area" ../ref/eye.png
ffmpeg -v error -y -loop 1 -t 6 -r 25 -i ../ref/eye.png -loop 1 -t 6 -r 25 -i ../ref/eye.png -filter_complex "[0][1]hstack,setsar=0,format=yuv444p" -c:v libx264 -qp 0 -pix_fmt yuv444p -colorspace bt709 -color_range pc -x264-params frame-packing=3 up-sei-sbs-half.mp4
for f in bilinear bicubic lanczos; do ffmpeg -v error -y -i ../ref/eye.png -vf "scale=1280:720:flags=$f" ../ref/ref-$f.png; done
# a still 2D clip for the 2D control (8 and 10 bits)
ffmpeg -v error -y -f lavfi -i "testsrc2=s=1280x720:r=25:d=6" -vf "select=eq(n\,0),loop=-1:1:0,fps=25,trim=duration=6" -c:v libx264 -qp 0 -pix_fmt yuv420p static2d.mp4
ffmpeg -v error -y -f lavfi -i "testsrc2=s=1280x720:r=25:d=6" -vf "select=eq(n\,0),loop=-1:1:0,fps=25,trim=duration=6,format=yuv420p10le" -c:v libx265 -x265-params lossless=1:log-level=error -pix_fmt yuv420p10le static2d10.mkv
# audio: a 44.1 kHz 16 bit PCM, a 96 kHz 24 bit FLAC, a 44.1 kHz AAC (float planar), 6 s each with the still video
ffmpeg -v error -y -f lavfi -i "anoisesrc=d=8:c=pink:r=44100:a=0.2,aformat=sample_fmts=s16:sample_rates=44100:channel_layouts=stereo" -i static2d.mp4 -t 6 -c:v copy -c:a pcm_s16le a44k16.mkv
ffmpeg -v error -y -f lavfi -i "sine=f=1000:d=8:r=96000,aformat=sample_fmts=s32:sample_rates=96000:channel_layouts=stereo" -i static2d.mp4 -t 6 -c:v copy -c:a flac -sample_fmt s32 a96k24.mkv
ffmpeg -v error -y -f lavfi -i "sine=f=440:d=8:r=44100" -i static2d.mp4 -t 6 -c:v copy -c:a aac a44kaac.mp4
