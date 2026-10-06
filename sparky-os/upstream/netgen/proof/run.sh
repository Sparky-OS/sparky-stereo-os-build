#!/bin/bash
# usage: run.sh <name> <stock|ours> <gpu|software> <on|off> [extra env VAR=val ...]
name=$1; img=$2; mode=$3; st=$4; shift 4
here=$(dirname "$(readlink -f "$0")"); mkdir -p $here/out
gpuargs=""; [ "$mode" = gpu ] && gpuargs="--device /dev/dri/renderD128 --group-add 125"
extra=""; for e in "$@"; do extra="$extra -e $e"; done
exec docker run --rm --name netgen-stereo-$name --platform linux/amd64 --cpus 4 --cap-add SYS_NICE $gpuargs \
  -e NAME=$name -e MODE=$mode $extra -e SMOKE_GID=125 \
  -v $here:/w netgen-stereo-run:$img \
  bash -c 'useradd -m -u 1000 t 2>/dev/null; groupadd -g 125 hostrender 2>/dev/null; usermod -aG 125 t; chown -R t /w/out 2>/dev/null; su t -c "dbus-run-session -- /w/inner.sh" 2>&1 | grep -v -E "ignoring unknown|a11y"'
