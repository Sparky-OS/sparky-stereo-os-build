#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Compare the published and corrected helper in an isolated native test root."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('source', type=Path, help='Extracted published source before the ownership fix')
parser.add_argument('work', type=Path, help='New directory in owned scratch')
args = parser.parse_args()
work = args.work.resolve()
recipe = Path(__file__).resolve().parents[1]
if Path(f'/run/user/{os.getuid()}').exists():
    raise SystemExit('Use an isolated user without /run/user/UID to exercise the TMPDIR fallback')
work.mkdir(parents=True, exist_ok=False)
rows = []
for version in ('old', 'fixed'):
    tree = work / version
    include = tree / 'include/wine'
    include.mkdir(parents=True)
    shutil.copy2(args.source / 'include/wine/server_tmpdir.h', include)
    if version == 'fixed':
        subprocess.run(['patch', '-p1', '-i', str(recipe/'patches/wine-tmpdir-ownership.patch')], cwd=tree, check=True)
    subprocess.run(['cc', '-g', '-Wall', '-Wextra', '-Werror', '-fsanitize=address',
                    '-I'+str(include), str(recipe/'tests/tmpdir.c'), '-o', str(tree/'probe')], check=True)
    for label, tmp in [('unset', None), ('tmp', '/tmp'), ('custom', str(work/'custom')), ('spaces', str(work/'with spaces'))]:
        cfg = work / (version+'-'+label)
        cfg.mkdir(mode=0o700)
        env = os.environ.copy()
        env.pop('TMPDIR', None)
        if tmp is not None:
            Path(tmp).mkdir(exist_ok=True)
            env['TMPDIR'] = tmp
        env['ASAN_OPTIONS'] = 'detect_leaks=0'
        result = subprocess.run([str(tree/'probe'), str(cfg)], env=env, capture_output=True, text=True)
        (work/(version+'-'+label+'.log')).write_text(result.stdout+result.stderr)
        expected = (result.returncode == 0 if version == 'fixed' or tmp is None else
                    result.returncode != 0 and 'attempting free on address which was not malloc()-ed' in result.stderr)
        rows.append({'version':version, 'case':label, 'returncode':result.returncode, 'expected_result':expected})
        (work/'result.json').write_text(json.dumps(rows, indent=2)+'\n')
        if not expected:
            raise SystemExit(result.stdout+result.stderr)
print('PASS: unset TMPDIR control, three old-code negatives and all four corrected cases')
