#!/usr/bin/env python3
"""Record exact installed bench versions and compare Multi-Arch shared files."""
import argparse, hashlib, json, subprocess, tarfile
from pathlib import Path
import io
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('work',type=Path)
p.add_argument('--finish',action='store_true')
a=p.parse_args()
required=('ffmpeg','libavcodec63','mpv','libmpv2','libplacebo360','libmlt7','libqt6multimedia6','kdenlive','vlc-stereo','sparky-stereo-hardware')
def fields(path):
    data=subprocess.check_output(['dpkg-deb','-f',str(path)],text=True)
    return dict(l.split(': ',1) for l in data.splitlines() if ': ' in l and not l.startswith(' '))
versions={phase:{} for phase in ('before','after')}
rows=[]
runtime={phase:{} for phase in ('before','after')}
def playback(d):
    name=d['Package']
    return d['Architecture'] in ('amd64','all') and not any(token in name for token in ('-dev','-dbgsym','-lc-hr','-doc','-examples'))
for deb in sorted((a.work/'previous').glob('*.deb')):
    d=fields(deb)
    if playback(d):runtime['before'][d['Package']]=d['Version']
    if d.get('Architecture') in ('amd64','all') and d['Package'] in required:
        versions['before'][d['Package']]=d['Version']
versions['before']['libplacebo360']='2:7.360.1-dmo1'
for directory in sorted((a.work/'out').iterdir()):
    for deb in sorted(directory.glob('*.deb')):
        d=fields(deb)
        if playback(d):runtime['after'][d['Package']]=d['Version']
        rows.append((d['Package'],d['Version'],d['Architecture'],hashlib.sha256(deb.read_bytes()).hexdigest(),str(deb.relative_to(a.work))))
        if d['Architecture'] in ('amd64','all') and (d['Package'] in required or d['Package']=='libmedia-gpu-route0'):
            versions['after'][d['Package']]=d['Version']
if a.finish:
    for phase in ('before','after'):
        assert set(required)<=versions[phase].keys(),(phase,set(required)-versions[phase].keys())
# Keep the transaction list limited to this cohort, including its runtime companions.
runtime['before']={name:version for name,version in runtime['before'].items() if name in runtime['after']}
runtime['before']['libplacebo360']='2:7.360.1-dmo1'
(a.work/'a10-runtime-packages.json').write_text(json.dumps(runtime,indent=2,sort_keys=True)+'\n')
(a.work/'a10-versions.json').write_text(json.dumps(versions,indent=2,sort_keys=True)+'\n')
(a.work/'cohort.tsv').write_text('package\tversion\tarchitecture\tsha256\tpath\n'+''.join('\t'.join(r)+'\n' for r in rows))
# Compare overlapping /usr/share payloads from the exact architecture twins.
lookup={}
for row in rows:lookup.setdefault(row[0],{})[row[2]]=a.work/row[4]
def shared(deb):
    stream=subprocess.check_output(['dpkg-deb','--fsys-tarfile',str(deb)])
    result={}
    with tarfile.open(fileobj=io.BytesIO(stream)) as archive:
        for member in archive:
            name=member.name.removeprefix('./')
            if name.startswith('usr/share/') and member.isfile():
                result[name]=hashlib.sha256(archive.extractfile(member).read()).hexdigest()
    return result
proof=[]
for package,arches in lookup.items():
    if 'amd64' in arches and 'i386' in arches:
        left,right=shared(arches['amd64']),shared(arches['i386'])
        common=left.keys()&right.keys()
        changed=[name for name in common if left[name]!=right[name]]
        assert not changed,(package,changed)
        proof.append(f'{package}: {len(common)} overlapping /usr/share files identical\n')
(a.work/'multiarch-shared.txt').write_text(''.join(proof))
print(f'{len(rows)} archives recorded; {len(proof)} architecture pairs checked')
