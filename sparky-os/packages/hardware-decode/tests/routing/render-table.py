#!/usr/bin/env python3
import argparse, json, re
from pathlib import Path
p=argparse.ArgumentParser(); p.add_argument('work',type=Path);a=p.parse_args()
print('| GPU case | Outputs | API | Film | Decode GPU / API | Render GPU | Frame path | VO flips/s | VO drops total / settled; decoder max | Process CPU |')
print('| --- | ---: | --- | --- | --- | --- | --- | ---: | ---: | ---: |')
for pair in ('amd-only','nvidia-only','hybrid-amd','hybrid-nvidia'):
    for screens in (1,2):
        case=f'{"matrix" if pair=="amd-only" else "matrix2"}-{pair}-{screens}'
        for api in ('vulkan','opengl'):
            for film,label in [('h264-2d8','2D 24 fps, 640x192'),('h264-sbs8','3D 48 fps, 1920x540')]:
                name=f'{api}-{film}'
                root=a.work/'final'/case
                data=json.loads((root/(name+'.json')).read_text())
                assert data['exit']==0,root/name
                rows=data['samples']
                decoders={r['hwdec-current'].get('data') for r in rows[3:]}
                expected='nvdec' if pair in ('nvidia-only','hybrid-nvidia') else 'vaapi'
                assert decoders=={expected},(case,decoders)
                log=(root/(name+'.mpv.log')).read_text()
                gpu='RTX 3060' if expected=='nvdec' else 'Renoir'
                if api=='vulkan':
                    names=re.findall(r'Device Name: (.*)',log)
                    assert names and ('NVIDIA' if expected=='nvdec' else 'AMD') in names[-1],(case,names)
                else:
                    names=re.findall(r'GL_RENDERER: (.*)',log)
                    assert names and ('NVIDIA' if expected=='nvdec' else 'AMD') in names[-1],(case,names)
                wayland=(root/(name+'.log')).read_text()
                declared=bool(re.search(r'kde_stereo_content_v1#\d+\.set_content\(3\)',wayland))
                assert declared==(film=='h264-sbs8'),(root/name,declared)
                flips=[int(line.split()[0])/1e9 for line in (root/(name+'.stats')).read_text().splitlines() if line.endswith('start video-flip')]
                assert len(flips)>20,root/name
                # Both source fixtures run long enough for an identical settled interval.
                start=flips[0]+1
                end=start+5
                assert flips[-1]>=end,root/name
                selected=[t for t in flips if start<=t<=end]
                assert len(selected)>10,root/name
                fps=(len(selected)-1)/(selected[-1]-selected[0])
                timing=(root/(name+'.stats')).read_text().splitlines()
                drops=sum(line.endswith(' drop-vo') for line in timing)
                steady_drops=sum(line.endswith(' drop-vo') and start<=int(line.split()[0])/1e9<=end for line in timing)
                decoder_drops=max(r['decoder-frame-drop-count'].get('data',0) for r in rows)
                params=rows[-1]['video-out-params']['data']
                copy=params['pixelformat'] not in ('vaapi','cuda')
                path=('download, stereo copy, upload' if copy and film=='h264-sbs8' else 'hardware surface import' if not copy else 'download and upload')+', same GPU to compositor'
                print(f'| {pair} | {screens} | {api} | {label} | {gpu} / {expected} | {gpu} | {path} | {fps:.2f} | {drops} / {steady_drops}; {decoder_drops} | {data["cpu_percent"]:.1f}% |')
