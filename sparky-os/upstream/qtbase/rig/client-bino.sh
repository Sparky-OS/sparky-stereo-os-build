#!/bin/bash
# Bino 2.8 (our package) playing the side-by-side clip (left eye red "LEFT", right eye blue "RIGHT"),
# input layout told explicitly, no glFinish shim. usage: client-bino.sh [clip] [bino args]
clip=${1:-/clips/sbs-L.mkv}; shift
exec bino --log-level debug --log-file /ev/bino.log -l one -i left-right "$@" "$clip"
