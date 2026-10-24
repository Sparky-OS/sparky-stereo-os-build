#!/bin/bash
# Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT
# MLT (Kdenlive's engine) and VLC Stereo copy every hardware-decoded picture
# back to memory, so their automatic choice goes through libmedia-gpu-route
# as copy-back callers: software by default, hardware where copying back is
# allowed, and hardware whenever the person names a decoder. Runs the
# installed melt and cvlc on a GPU's render node, with no display.
# Usage: engines.sh OUTDIR FILM
set -u
out=$1 film=$2
mkdir -p "$out"
export XDG_CONFIG_DIRS=/nonexistent XDG_CONFIG_HOME=/nonexistent
unset MEDIA_GPU_ROUTE_COPY_BACK DISPLAY WAYLAND_DISPLAY
failures=0
expect() {
    local name=$1 want=$2 pattern=$3
    if grep -qE -- "$pattern" "$out/$name.log"; then found=yes; else found=no; fi
    if [ "$found" = "$want" ]; then echo "ok   $name: /$pattern/ found=$found"; else
        echo "FAIL $name: /$pattern/ found=$found, wanted $want"; failures=$((failures + 1)); fi
}
melt_run() { local name=$1; shift; env "$@" melt -verbose "$film" out=47 -consumer null > "$out/$name.log" 2>&1; }
vlc_run() { local name=$1; shift; env "${@:1:$#-1}" cvlc-stereo -vv --no-audio --vout=dummy --play-and-exit --run-time=3 \
    --avcodec-hw="${@: -1}" "$film" > "$out/$name.log" 2>&1; }
hardware_mlt='Using hardware decoding \(vaapi\)|Default decoder GPU'
melt_run mlt-default
expect mlt-default no "$hardware_mlt"
melt_run mlt-allowed MEDIA_GPU_ROUTE_COPY_BACK=true
expect mlt-allowed yes 'Default decoder GPU'
melt_run mlt-explicit MLT_AVFORMAT_HWACCEL=vaapi
expect mlt-explicit yes 'hwaccel vaapi av_hwdevice_ctx_create\(\) success'
hardware_vlc='Default decoder GPU|copy-back for hardware decoding'
vlc_run vlc-default any
expect vlc-default no "$hardware_vlc"
vlc_run vlc-allowed MEDIA_GPU_ROUTE_COPY_BACK=true any
expect vlc-allowed yes 'Default decoder GPU'
vlc_run vlc-explicit vaapi
expect vlc-explicit yes 'Using VAAPI copy-back for hardware decoding'
dpkg-query -W -f='${Package} ${Version}\n' libmedia-gpu-route0 melt libmlt7 vlc-stereo > "$out/versions.txt"
[ "$failures" = 0 ] && echo PASSED || echo "FAILED ($failures)"
exit $((failures != 0))
