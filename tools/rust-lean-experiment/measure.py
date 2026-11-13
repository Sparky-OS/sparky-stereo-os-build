#!/usr/bin/env python3
"""Measure one command and descendants inside a perf-enabled container."""
import argparse
from decimal import Decimal
import json
import math
import os
from pathlib import Path
import re
import subprocess
import shutil
import time


def number(text):
    text = text.strip()
    if not re.fullmatch(r'[+-]?\d+(?:[.,]\d+)?(?:[eE][+-]?\d+)?', text):
        raise ValueError(f'not an unambiguous decimal number: {text!r}')
    value=float(Decimal(text.replace(',', '.')))
    if not math.isfinite(value):raise ValueError('non-finite numeric value')
    return value


def parse_perf(text):
    patterns = {
        'instructions': r'^\s*([0-9][0-9.,]*)\s+instructions:u\b',
        'page_faults': r'^\s*([0-9][0-9.,]*)\s+page-faults\b',
        'wall_seconds': r'^\s*([0-9][0-9.,]*)\s+seconds time elapsed',
        'user_seconds': r'^\s*([0-9][0-9.,]*)\s+seconds user',
        'system_seconds': r'^\s*([0-9][0-9.,]*)\s+seconds sys',
    }
    result = {}
    for key, pattern in patterns.items():
        matches = re.findall(pattern, text, re.M)
        if len(matches) != 1:
            raise ValueError(f'perf did not provide exactly one {key}; inspect raw perf.txt')
        result[key] = number(matches[0])
    if result['instructions'] <= 0 or result['wall_seconds'] <= 0:
        raise ValueError('perf returned an empty instruction or elapsed-time measurement')
    if any(v<0 for v in result.values()):raise ValueError('negative perf measurement')
    if not result['instructions'].is_integer() or not result['page_faults'].is_integer():
        raise ValueError('non-integral perf event count')
    result['instructions'] = int(result['instructions'])
    result['page_faults'] = int(result['page_faults'])
    return result


def run(command, output, expected=0):
    output.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ, LC_ALL='C')
    resolved=shutil.which(command[0],path=env.get('PATH'))
    if resolved is None:raise RuntimeError('named executable is unavailable: '+command[0])
    # File-capability perf runs under secure exec. Re-establish the explicitly
    # selected compiler path after that boundary; never let perf choose a seed.
    launch=['/usr/bin/env','PATH='+env['PATH']]
    if 'LD_LIBRARY_PATH' in env:launch.append('LD_LIBRARY_PATH='+env['LD_LIBRARY_PATH'])
    launch += [resolved,*command[1:]]
    argv = ['/usr/bin/time', '-f', 'maxrss_kib=%M', '-o', str(output/'rss.txt'),
            '/usr/bin/perf', 'stat', '--no-big-num', '-o', str(output/'perf.txt'),
            '-e', 'instructions:u,page-faults', '--', *launch]
    started = time.time()
    with (output/'stdout').open('wb') as out, (output/'stderr').open('wb') as err:
        r = subprocess.run(argv, stdout=out, stderr=err, env=env)
    ended=time.time()
    if r.returncode != expected:
        raise RuntimeError(f'command exit {r.returncode}, expected {expected}; inspect {output}/stderr')
    metrics = parse_perf((output/'perf.txt').read_text())
    rss = re.findall(r'^maxrss_kib=(\d+)$', (output/'rss.txt').read_text(), re.M)
    if len(rss) != 1:
        raise RuntimeError('GNU time did not provide peak child RSS')
    metrics.update(resolved_executable=resolved,perf_launch=launch,max_child_rss_kib=int(rss[0]), command=command, started_unix=started, ended_unix=ended,
                   exit_code=r.returncode, cgroup_peak_bytes=int(Path('/sys/fs/cgroup/memory.peak').read_text()))
    tmp = output/'metrics.json.partial'
    tmp.write_text(json.dumps(metrics, indent=2, sort_keys=True)+'\n')
    tmp.replace(output/'metrics.json')
    return metrics


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('output', type=Path)
    ap.add_argument('command', nargs=argparse.REMAINDER)
    a = ap.parse_args()
    print(json.dumps(run(a.command, a.output), indent=2))
