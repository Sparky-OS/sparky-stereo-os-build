#!/usr/bin/env python3
"""Check actual published-package routes against the required display GPU default."""
import argparse,csv,subprocess,sys
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('work',type=Path)
p.add_argument('references',type=Path)
a=p.parse_args()
root=a.work/'final/published-controls'
ref=a.references/'final/amd-engines'
lines=[]
for engine in ('mlt','qt','vlc','libmpv'):
    rows=list(csv.reader((root/(engine+'.trace')).read_text().splitlines()))
    assert rows
    formats={r[2] for r in rows}
    assert formats==({'cuda'} if engine=='qt' else {'yuv420p'}),(engine,formats)
    assert all(r[4]=='8' and r[5]=='1' and r[6]=='0' for r in rows)
    if engine in ('mlt','qt'):
        assert (root/(engine+'.raw')).read_bytes()==(ref/(engine+'-h264-eyes8-software.raw')).read_bytes()
    if engine=='vlc':
        frame=640*192*2
        reference=(ref/'qt-h264-eyes8-software.raw').read_bytes()
        source_frames={reference[i:i+frame] for i in range(0,len(reference),frame)}
        data=(root/'vlc.raw').read_bytes()
        assert data and len(data)%frame==0
        assert all(data[i:i+frame] in source_frames for i in range(0,len(data),frame))
    # Every published route fails the AMD display-device expectation.
    assert formats!={'vaapi'}
    assertion=subprocess.run([sys.executable,str(Path(__file__).with_name('route-assert.py')),str(root/(engine+'.trace')),'vaapi'],capture_output=True,text=True)
    assert assertion.returncode==1,assertion.stdout
    (root/(engine+'-display-route.log')).write_text(assertion.stdout+assertion.stderr)
    (root/(engine+'-display-route.exit')).write_text(str(assertion.returncode)+'\n')
    lines.append(f'{engine}: published {formats}; AMD display-route assertion exit 1; source depth and mark retained\n')
assert (root/'device-choice.exit').read_text().strip()=='1'
assert (a.work/'final/fallback/before.exit').read_text().strip()=='134'
lines.append('Published FFmpeg format-query fallback aborts with exit 134\n')
(root/'expected-failures.txt').write_text(''.join(lines))
print(''.join(lines))
