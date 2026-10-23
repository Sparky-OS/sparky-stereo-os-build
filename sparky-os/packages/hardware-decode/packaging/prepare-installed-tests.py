#!/usr/bin/env python3
"""Configure the accepted decoder harness to run only installed engine binaries."""
import argparse,hashlib,json,shutil
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('work',type=Path)
a=p.parse_args()
source=Path(__file__).resolve().parent.parent/'tests'
target=a.work/'installed-kit/tests'
target.mkdir(parents=True,exist_ok=True)
changes={
 '/w/mpv-build/mpv':'/usr/bin/mpv',
 '/w/mlt-build/out/lib/mlt':'/usr/lib/x86_64-linux-gnu/mlt-7',
 '/w/mlt-build/out/lib':'/usr/lib/x86_64-linux-gnu',
 '/w/ffmpeg-build/libavcodec':'/usr/lib/x86_64-linux-gnu',
 '/w/decoder-trace.so':'/w/probes/decoder-trace.so',
}
for name in ('decode-proof','mlt-proof','qt-proof','vlc-proof','libmpv-proof'):
 changes['/w/'+name]='/w/probes/'+name
records={}
names=('qualify-gpu','final-run-mpv','final-run-engines','final-run-cancellation-recorded','additional-codecs','references','mpv-images','final-run-vlc','vlc-vmem-matrix','libmpv-defaults','vlc-weston-cases','vlc-qt-cases')
for path in (source/(name+'.sh') for name in names):
 text=path.read_text()
 for old,new in changes.items():text=text.replace(old,new)
 text=text.replace('LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu/vlc-stereo', 'LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu/vlc-stereo')
 # Keep Weston alive for its client; the container/session owns termination.
 text=text.replace('exec timeout 60 weston ', 'exec weston ')
 assert not any(token in text for token in ('/w/ffmpeg-build','/w/mlt-build','/w/mpv-build'))
 (target/path.name).write_text(text)
 records[path.name]={'source_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'configured_sha256':hashlib.sha256(text.encode()).hexdigest()}
(a.work/'installed-kit/harness-config.json').write_text(json.dumps(records,indent=2,sort_keys=True)+'\n')
shutil.copy2(source/'check-results.py',a.work/'installed-kit/check-results.py')
