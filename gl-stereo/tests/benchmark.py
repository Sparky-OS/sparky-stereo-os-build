# SPDX-License-Identifier: GPL-2.0-or-later
"""Wall time and total CPU, including llvmpipe's software rendering work."""
import json
import os
from pathlib import Path
import re
import resource
import statistics
import subprocess
import time
results = []
for repeat in range(3):
    for mode in ('mono', 'stereo'):
        env = os.environ.copy()
        env.pop('LD_PRELOAD', None)
        for key in list(env):
            if key.startswith('GL_STEREO'):
                env.pop(key)
        env['vblank_mode'] = '0'
        if mode == 'stereo':
            env['GL_STEREO'] = '1'
            env['LD_PRELOAD'] = str(Path('libgl-stereo.so').resolve())
        before = resource.getrusage(resource.RUSAGE_CHILDREN)
        start = time.monotonic()
        process = subprocess.Popen(['glxgears','-geometry','640x360'], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            output, error = process.communicate(timeout=6.2)
        except subprocess.TimeoutExpired:
            process.terminate()
            output, error = process.communicate(timeout=3)
        after = resource.getrusage(resource.RUSAGE_CHILDREN)
        elapsed = time.monotonic() - start
        matches = re.findall(r'(\d+) frames in ([\d.]+) seconds = ([\d.]+) FPS', output)
        assert matches, (output, error)
        fps = float(matches[-1][2])
        cpu = after.ru_utime + after.ru_stime - before.ru_utime - before.ru_stime
        row = dict(mode=mode, repeat=repeat, fps=fps, frame_ms=1000/fps, cpu_seconds=cpu, wall_seconds=elapsed)
        results.append(row)
        print(row, flush=True)
Path('out/benchmark.json').write_text(json.dumps(results, indent=2))
for mode in ('mono','stereo'):
    values = [x['frame_ms'] for x in results if x['mode'] == mode]
    print(mode, 'median frame ms', statistics.median(values), flush=True)
