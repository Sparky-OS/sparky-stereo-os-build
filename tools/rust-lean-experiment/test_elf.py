#!/usr/bin/env python3
"""A real compressed ELF proves bounded logical-section comparison and byte counts."""
from pathlib import Path
import subprocess
import tempfile
from analyze import sections

with tempfile.TemporaryDirectory() as d:
    root=Path(d)
    data=b'0123456789abcdef'*(128*1024)
    for name,content in [('a',data),('b',data[:1000000]+b'X'+data[1000001:])]:
        payload=root/(name+'.data');payload.write_bytes(content)
        subprocess.run(['objcopy','--add-section','.debug_rl541='+str(payload),
                        '--set-section-flags','.debug_rl541=readonly,debug',
                        '/usr/bin/true',str(root/(name+'.raw'))],check=True)
        subprocess.run(['objcopy','--compress-debug-sections=zlib',str(root/(name+'.raw')),str(root/name)],check=True)
    same=sections(root/'a',root/'a')
    if same['file_offset_different_bytes'] or same['sections']:raise RuntimeError('identical ELF reported differences')
    diff=sections(root/'a',root/'b')
    rows=[r for r in diff['sections'] if r['section']=='.debug_rl541']
    if len(rows)!=1 or rows[0]['different_bytes_at_logical_section_offsets']!=1:
        raise RuntimeError('logical compressed-byte difference was not exactly one: '+repr(rows))
    if rows[0]['A_logical_bytes']!=len(data) or rows[0]['A_stored_bytes']>=len(data):
        raise RuntimeError('fixture did not actually compress its debug section')
    print('PASS: real zlib-compressed ELF, equal file and exactly one changed logical byte, 2 MiB streamed payload')
