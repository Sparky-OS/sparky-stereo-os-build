#!/bin/bash
# usage: run.sh <name> <image> <vo> <clip (under clips/)> <times json> [extra mpv args...]   env: SCREEN (1280x800), GEOM, SW (1 = llvmpipe)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
cd ${SPARKY_WORKSPACES:?}/media-on-dmo/work/rig
name=$1; img=$2; vo=$3; clip=$4; times=$5; shift 5
out=runs/$name; rm -rf $out; mkdir -p $out
SCREEN=${SCREEN:-1280x800}
mpv=$(python3 - "$vo" "$clip" "${GEOM:---geometry=960x540}" "$@" <<'PY'
import sys, json
vo, clip, geom = sys.argv[1:4]
print(json.dumps(['--vo=' + vo, '--no-osc', '--osd-level=0', '--keep-open=yes', geom] + sys.argv[4:] + ['/w/' + clip]))
PY
)
cfg=$(STEPS="$STEPS" python3 -c "import json,sys,os; t=json.loads(sys.argv[1]); print(json.dumps({'mpv': json.loads(sys.argv[2]), 'caps': t, 'screen': sys.argv[3], 'end': t[-1]+1, 'bin': sys.argv[4], **({'steps': json.loads(os.environ['STEPS'])} if os.environ.get('STEPS') else {})}))" "$times" "$mpv" "$SCREEN" "${MPVBIN:-mpv}")
timeout ${TMO:-180} docker run --rm --name mdmo-run-$name --user $(id -u):$(id -g) --cpus ${CPUS:-2} --cap-add SYS_NICE --device /dev/dri/renderD128 --group-add 125 \
  -v $PWD/passwd:/etc/passwd:ro -e HOME=/tmp/home -e LIBGL_ALWAYS_SOFTWARE=${SW:-0} -v $PWD:/w $img \
  sh -c "dbus-run-session -- python3 /w/scripts/drv.py /w/$out '$cfg' > /w/$out/drv.log 2>&1"
python3 scripts/analyze.py $out ${SCREEN%x*} > $out/analysis.txt 2>&1; cat $out/analysis.txt | tail -${TAILN:-14}
