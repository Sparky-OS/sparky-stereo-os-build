#!/bin/bash
# The 130-saver requalification of a new gl-stereo layer, one step per call, run as UID 1000 inside the
# audit container (requalify-root.sh) with the checkout at /workspace/gl-stereo and scratch at
# /build. It follows savers/audit/README.md: every input is made fresh here, with this
# directory's scripts.
# usage: requalify-steps.sh <step>
set -u
B=/build; W=/workspace/gl-stereo; A=$W/savers/audit
LIB=/usr/lib/gl-stereo/libgl-stereo.so
export LANG=C.UTF-8 LP_NUM_THREADS=4
# FlipText's 2D control and KWin capture take this frame of its recording: it shows text, and it is
# the same picture in every recording (savers/audit/README.md).
FLIPTEXT_FRAME=1000
cd "$A"
names() { python3 -c "import json;print(' '.join(e['id'] for e in json.load(open('$A/inventory-6.09.json')) if e['kind']=='hack'))"; }
status() { echo "$2" > "$B/$1.status"; echo "$(date +%T) $1 status $2" >> "$B/requalify.log"; }
kwin() { AUDIT_TIMEOUT=${AUDIT_TIMEOUT:-120} AUDIT_LIBRARY=${AUDIT_LIBRARY:-$LIB} GL_STEREO_SEPARATION=.5 REFERENCE_SEPARATION=.5 python3 "$A/run-kwin.py" "$@"; }
# a KWin sweep passes when every requested case completed a session with its execution record
sessions_ok() { python3 - "$@" <<'PY'
import json, sys
from pathlib import Path
root = Path(sys.argv[1]); results = json.loads((root/'results.json').read_text())
bad = [r['id'] for r in results if r.get('session_exit') != 0 or not (root/r['id']/'execution.json').exists()]
print('sessions', len(results), 'incomplete', bad)
sys.exit(1 if bad or len(results) != int(sys.argv[2]) else 0)
PY
}
# the old Flurry case joins a sweep: merge_flurry <sweep> <old-flurry sweep>
merge_flurry() { python3 - "$1" "$2" <<'PY'
import json, shutil, sys
from pathlib import Path
B = Path('/build'); main, extra = B/sys.argv[1], B/sys.argv[2]
if not (main/'flurry').exists():
    shutil.move(str(extra/'flurry'), str(main/'flurry'))
    if (extra/'flurry.log').exists(): shutil.move(str(extra/'flurry.log'), str(main/'flurry.log'))
results = json.loads((main/'results.json').read_text())
if not any(r['id'] == 'flurry' for r in results):
    results += [r for r in json.loads((extra/'results.json').read_text()) if r['id'] == 'flurry']
    (main/'results.json').write_text(json.dumps(results, indent=2) + '\n')
PY
}
case $1 in
setup)
	gcc -shared -fPIC fixture.c -o $B/fixture-egl.so -ldl -lGL -lX11 -lEGL &&
	gcc -shared -fPIC reference.c -o $B/reference.so -ldl -lGL -lm &&
	g++ ../../plasma/capture.cpp -o $B/capture $(pkg-config --cflags --libs Qt6Gui Qt6DBus) &&
	mkdir -p $B/source && tar -xf /orig/xscreensaver_6.09+dfsg1.orig.tar.xz -C $B/source &&
	ls -d $B/source/xscreensaver-6.09* > $B/source-dir.txt &&
	python3 mapscroller-tiles.py $B/home > $B/mapscroller-tiles.log &&
	printf '%s\n' 'Sparky Stereo OS' 'Two eyes, one world.' 'Every program in stereo, the desktop too.' \
		'Full side by side, left eye first.' 'Made for the people who still own a 3D TV.' > $B/audit-text.txt
	status setup $? ;;
inventory)
	python3 inventory.py "$(cat $B/source-dir.txt)" $B/installed-inventory.json > $B/installed-inventory-check.log 2>&1 &&
	python3 check-inventory.py inventory-6.09.json $B/installed-inventory.json "$(cat $B/source-dir.txt)" >> $B/installed-inventory-check.log 2>&1
	status installed-inventory-check $? ;;
sweep)
	kwin $B/installed-kwin $(names | tr ' ' '\n' | grep -vx flurry) > $B/installed-sweep.log 2>&1
	status installed-sweep-129 $? ;;
oldflurry)
	# the saver before its owning camera fix: the negative control and the original 2D pixels
	kwin $B/installed-kwin-oldflurry flurry > $B/installed-kwin-oldflurry.log 2>&1
	AUDIT_TIMEOUT=90 python3 mono.py $B/installed-mono-oldflurry $B/fixture-egl.so $LIB flurry > $B/installed-mono-oldflurry.log 2>&1
	status oldflurry $? ;;
merge)
	# a case that did not reach its frame within the budget on the shared rig runs once more with a
	# longer budget; its first attempt is kept beside it
	retry=$(python3 -c "import json;print(' '.join(r['id'] for r in json.load(open('$B/installed-kwin/results.json')) if r.get('session_exit')!=0 or r.get('error')))")
	if [ -n "$retry" ]; then
		echo "retry: $retry" >> $B/installed-sweep.log
		AUDIT_TIMEOUT=120 kwin $B/installed-kwin-retry $retry >> $B/installed-sweep.log 2>&1
		python3 - $retry <<'PY'
import json, shutil, sys
from pathlib import Path
B = Path('/build'); main = B/'installed-kwin'; retry = B/'installed-kwin-retry'; first = B/'installed-kwin-first-attempts'
first.mkdir(exist_ok=True)
results = json.loads((main/'results.json').read_text())
again = {r['id']: r for r in json.loads((retry/'results.json').read_text())}
for name in sys.argv[1:]:
    shutil.move(str(main/name), str(first/name))
    shutil.move(str(retry/name), str(main/name))
    results = [again[name] if r['id'] == name else r for r in results]
(main/'results.json').write_text(json.dumps(results, indent=2) + '\n')
PY
	fi
	merge_flurry installed-kwin installed-kwin-oldflurry
	sessions_ok $B/installed-kwin 130 >> $B/installed-sweep.log 2>&1
	status installed-sweep $? ;;
warmup)
	AUDIT_TARGET=600 AUDIT_TIMEOUT=240 kwin $B/installed-warmup chompytower energystream companioncube > $B/installed-warmup.log 2>&1
	sessions_ok $B/installed-warmup 3 >> $B/installed-warmup.log 2>&1
	status installed-warmup $? ;;
starwars)
	AUDIT_TARGET=600 AUDIT_TIMEOUT=240 AUDIT_TEXT=$B/audit-text.txt kwin $B/installed-starwars starwars > $B/installed-starwars.log 2>&1
	for eye in left right; do
		AUDIT_TARGET=600 AUDIT_TIMEOUT=240 AUDIT_TEXT=$B/audit-text.txt AUDIT_REFERENCE_EYE=$eye AUDIT_LIBRARY=$B/reference.so \
			kwin $B/installed-starwars-reference-$eye starwars >> $B/installed-starwars.log 2>&1
	done
	sessions_ok $B/installed-starwars 1 >> $B/installed-starwars.log 2>&1
	status installed-starwars $? ;;
flurry)
	kwin $B/installed-flurry flurry > $B/installed-flurry.log 2>&1
	for eye in left right; do
		AUDIT_REFERENCE_EYE=$eye AUDIT_LIBRARY=$B/reference.so kwin $B/installed-flurry-reference-$eye flurry >> $B/installed-flurry.log 2>&1
	done
	AUDIT_TIMEOUT=90 python3 mono.py $B/installed-flurry-mono $B/fixture-egl.so $LIB flurry >> $B/installed-flurry.log 2>&1
	sessions_ok $B/installed-flurry 1 >> $B/installed-flurry.log 2>&1
	status installed-flurry $? ;;
energy)
	for eye in left right; do
		AUDIT_TARGET=600 AUDIT_TIMEOUT=240 AUDIT_REFERENCE_EYE=$eye AUDIT_LIBRARY=$B/reference.so kwin $B/reference-energy-$eye energystream >> $B/reference-energy.log 2>&1
	done
	status reference-energy $? ;;
references)
	# independent one-eye cameras (reference.c) for the 24 scenes the depth oracle does not cover,
	# rendered in the same KWin and Xwayland session as the captures: text and fonts follow the
	# display (a reference made on Xvfb drew unicrud's labels differently)
	names="atlantis blinkbox bubble3d cage cubestack cubicgrid deepstars gleidescope glmatrix hexstrut hextrail highvoltage hydrostat hypnowheel polytopes providence pulsar raverhoop rubikblocks skytentacles timetunnel unicrud unknownpleasures"
	for eye in left right; do
		AUDIT_REFERENCE_EYE=$eye AUDIT_LIBRARY=$B/reference.so kwin $B/reference-kwin-$eye $names >> $B/reference-final.log 2>&1
		# GLBlur needs Mesa's display-list rasterization in the oracle too (README)
		AUDIT_REFERENCE_EYE=$eye AUDIT_LIBRARY=$B/reference.so REFERENCE_LIST_PRIMITIVES=1 kwin $B/reference-kwin-glblur-$eye glblur >> $B/reference-final.log 2>&1
	done
	python3 - <<'PY' >> $B/reference-final.log 2>&1
from pathlib import Path
B = Path('/build'); final = B/'reference-final'; final.mkdir(exist_ok=True)
for eye in ('left', 'right'):
    for root in (B/f'reference-kwin-{eye}', B/f'reference-kwin-glblur-{eye}'):
        for case in root.iterdir():
            if case.is_dir() and (case/'frame.png').exists():
                (final/case.name).mkdir(exist_ok=True)
                link = final/case.name/eye
                if not link.exists(): link.symlink_to(case, target_is_directory=True)
missing = [c.name for c in final.iterdir() if not ((c/'left'/'frame.png').exists() and (c/'right'/'frame.png').exists())]
print('references', len(list(final.iterdir())), 'incomplete', missing)
assert len(list(final.iterdir())) == 24 and not missing
PY
	status reference-final $? ;;
fliptext)
	# recorded GL input with neutral text at the text-generator boundary: the 2D control
	AUDIT_SNAPSHOT_FRAMES=fliptext=$FLIPTEXT_FRAME AUDIT_RECORD_SECONDS=40 AUDIT_RECORD_FIXTURE=$B/fixture-egl.so AUDIT_RECORD_TEXT=$B/audit-text.txt python3 trace-mono.py $B/installed-controlled-mono $LIB fliptext > $B/installed-controlled-mono.log 2>&1
	python3 -c "import json,sys;r=json.load(open('$B/installed-controlled-mono/results.json'));sys.exit(0 if all(x.get('passed') for x in r) else 1)"
	status installed-controlled-mono $?
	# the same input trimmed to complete frames for the KWin capture and both camera references
	trace=$B/installed-controlled-mono/fliptext/input.trace
	frames=$(apitrace dump --calls=frame $trace | grep -cE '^[0-9]+ ')
	last=$FLIPTEXT_FRAME
	apitrace trim --frames=0-$last --output=$B/installed-fliptext-complete.trace $trace > $B/installed-fliptext-final2.log 2>&1
	call=$(apitrace dump --calls=frame $B/installed-fliptext-complete.trace | grep -oE '^[0-9]+' | tail -n1)
	echo "trace frames $frames, trimmed to 0-$last, snapshot call $call" >> $B/installed-fliptext-final2.log
	# The replay repeats its final frame, and its first rendering differs from the repeats. The
	# fixture freezes both the layer's run and the references on the same repeat (the fifth
	# swap after the trace's last frame), where the layer also dumps its frame for the
	# composition check; frozen on the first rendering, the layer's capture and the references
	# disagreed by 6/255.
	AUDIT_TRACE=$B/installed-fliptext-complete.trace AUDIT_TRACE_CALL=$call AUDIT_TARGET=$((last + 5)) kwin $B/installed-fliptext-final2 fliptext >> $B/installed-fliptext-final2.log 2>&1
	for eye in left right; do
		AUDIT_TRACE=$B/installed-fliptext-complete.trace AUDIT_TRACE_CALL=$call AUDIT_TARGET=$((last + 5)) AUDIT_REFERENCE_EYE=$eye AUDIT_LIBRARY=$B/reference.so \
			kwin $B/installed-fliptext-final2-reference-$eye fliptext >> $B/installed-fliptext-final2.log 2>&1
	done
	sessions_ok $B/installed-fliptext-final2 1 >> $B/installed-fliptext-final2.log 2>&1
	status installed-fliptext-final2 $? ;;
tiles)
	# Mapscroller drew only synthetic tiles from its cache: its helper logged "cached:" and
	# never "downloading" (the audit runs with the network off)
	python3 - > $B/installed-tiles.log 2>&1 <<'PY'
import sys
from pathlib import Path
B = Path('/build'); bad = []
for log in ('installed-kwin/mapscroller/client.log', 'installed-mono/mapscroller/stock/producer.log',
            'installed-mono/mapscroller/disabled/producer.log', 'installed-trace-mono-fixed/mapscroller/record.log'):
    text = (B/log).read_text(errors='replace') if (B/log).exists() else ''
    cached, downloading = text.count('cached:'), text.count('downloading')
    print(log, 'cached', cached, 'downloading', downloading)
    if not cached or downloading: bad.append(log)
print('PASS' if not bad else f'FAIL: {bad}')
sys.exit(1 if bad else 0)
PY
	status installed-tiles $? ;;
lights)
	# glsnake's second light: the default capture is one single-light picture (owning-settings.json)
	python3 glsnake-lights.py $B/installed-glsnake-lights.json $B/fixture-egl.so > $B/installed-glsnake-lights.log 2>&1
	status installed-glsnake-lights $? ;;
late)
	# a compositor that reads the declaration late: the capture waits for the sized window
	mkdir -p $B/installed-late-compositor
	bash late-compositor.sh $B/installed-late-compositor > $B/installed-late-compositor.log 2>&1
	status installed-late-compositor $? ;;
mono)
	AUDIT_TIMEOUT=90 python3 mono.py $B/installed-mono $B/fixture-egl.so $LIB $(names | tr ' ' '\n' | grep -vx flurry) > $B/installed-mono.log 2>&1
	status installed-mono-129 $? ;;
monomore)
	AUDIT_TARGET=600 AUDIT_TIMEOUT=240 python3 mono.py $B/installed-mono-warmup $B/fixture-egl.so $LIB chompytower energystream companioncube > $B/installed-mono-warmup.log 2>&1
	python3 trace-mono.py $B/installed-trace-mono $LIB splitflap carousel winduprobot starwars fliptext > $B/installed-trace-mono.log 2>&1
	# Mapscroller's recording runs on the fixture's clock, so it visits the same places and asks for
	# the same tiles as every other run (mapscroller-tiles.json)
	AUDIT_RECORD_FIXTURE=$B/fixture-egl.so AUDIT_RECORD_TEXT=$B/audit-text.txt python3 trace-mono.py $B/installed-trace-mono-fixed $LIB mapscroller > $B/installed-trace-mono-fixed.log 2>&1
	status installed-mono-more $? ;;
monostatus)
	merge_flurry installed-mono installed-mono-oldflurry
	python3 - > $B/installed-mono-summary.log 2>&1 <<'PY'
import json, sys
from pathlib import Path
B = Path('/build'); good = {}
for name in ('installed-mono', 'installed-mono-warmup', 'installed-trace-mono', 'installed-trace-mono-fixed', 'installed-controlled-mono', 'installed-flurry-mono'):
    for r in json.loads((B/name/'results.json').read_text()):
        if r.get('equal') and r.get('stddev', 0) > 1: good.setdefault(r['id'], name)
hacks = [e['id'] for e in json.loads(Path('/workspace/gl-stereo/savers/audit/inventory-6.09.json').read_text()) if e['kind'] == 'hack']
missing = [h for h in hacks if h not in good]
print('exact nonempty 2D controls', len(good), 'of', len(hacks), 'missing', missing)
sys.exit(1 if missing else 0)
PY
	status installed-mono $? ;;
equivalence)
	# every capture here was made with the installed executables, so no evidence is carried across
	# binaries: the "before" set is the installed one, with Flurry from before its camera fix
	python3 debug-equivalence.py $B/pre-flurry-installed $B/installed-inventory.json $B/installed-debug-equivalence.json > $B/installed-debug-equivalence.log 2>&1
	status installed-debug-equivalence $? ;;
collect)
	python3 collect-installed.py $B > $B/installed-collect.log 2>&1
	status installed-collect $? ;;
flurrycheck)
	python3 check-flurry.py $B > $B/installed-flurry-check.log 2>&1
	status installed-flurry-check $? ;;
candidate)
	# the manifest before the functional suite: compile-qualification without that one gate, so the
	# installed catalogue can hold the 132 receipts the functional suite checks
	grep -v "installed-functional.status" compile-qualification.py > $B/compile-candidate.py
	ln -sf $A/debug-equivalence.py $A/owning-fixes.json $B/
	python3 $B/compile-candidate.py $B $B/qualification-candidate.json > $B/qualification-candidate.log 2>&1
	status qualification-candidate $? ;;
functional)
	bash $W/packaging/test-installed.sh $W > $B/installed-functional.log 2>&1
	status installed-functional $? ;;
compile)
	python3 compile-qualification.py $B $B/qualification-6.09.json > $B/installed-qualification.log 2>&1 &&
	cmp $B/qualification-candidate.json $B/qualification-6.09.json >> $B/installed-qualification.log 2>&1
	status installed-qualification $?
	python3 test-qualification.py $B/qualification-6.09.json $LIB $B > $B/installed-qualification-mutations.log 2>&1
	status installed-qualification-mutations $? ;;
*) echo "unknown step $1"; exit 2 ;;
esac
