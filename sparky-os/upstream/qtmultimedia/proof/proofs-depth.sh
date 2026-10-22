#!/bin/bash
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
cd ${SPARKY_SCRATCH:?}/qtmm-lane/run
LOG='{"QT_LOGGING_RULES":"qt.multimedia.video.stereopresenter.debug=true;qt.multimedia.video.stereolayer.debug=true"}'
{
echo "== depth: the buffer of the layer under the edition's defaults (stereoSurface BySource), levels of red per view, measured in the buffer before it is committed (KWin's capture is 8 bit)"
for c in ramp8-sbs.mkv ramp10-sbs.mkv ramp12-sbs.mkv ramp16-sbs.mkv ramp10-444-sbs.mkv ramp10-pq-sbs.mkv; do
  n=dp-$c
  PEXTRA=$LOG DEV=1 DEVDIR=/w/b-final ./rt.sh $n '[["wait",6],["cap","c1"]]' /w/clips/$c >/dev/null 2>&1
  echo "$c: $(grep -h 'levels of red' ../out/$n/client0.out ../out/$n/client0.log | head -1 | sed 's/.*packing/packing/; s/ right first.*view/ view/; s/QVideoFrameFormat:://')"
  grep -h "color description" ../out/$n/client0.log ../out/$n/client0.out | head -1 | sed 's/^/    /'
  echo "    wl_shm format of the buffer: $(grep -o 'create_buffer(new id wl_buffer#[0-9]*, 0, [0-9]*, [0-9]*, [0-9]*, [0-9]*)' ../out/$n/client0.log | grep -v '64, 64, 256' | head -1)"
done
echo "(shm format codes: 1 XRGB8888, 808669784 XRGB2101010 'XR30', 942948952 XBGR16161616 'XB48')"
} > ../proof-depth.txt 2>&1
echo done > ../proofs-depth-done
