#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
"""Run both Kubabbar staging tools with untracked contamination in a checkout."""
import argparse
import os
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--work', type=Path, required=True)
parser.add_argument('--baseline-ref', required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
relative = 'sparky-os/packages/kubabbar-glass'
tracked = subprocess.check_output(['git', '-C', str(repo), 'ls-files', '-z', '--', relative,
                                   'tools/copy-recipe.py']).split(b'\0')
for case in ('red', 'green'):
    root = args.work.resolve() / case
    root.mkdir(parents=True)
    for entry in filter(None, tracked):
        name = os.fsdecode(entry)
        target = root / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(repo / name, target, follow_symlinks=False)
    recipe = root / relative
    if case == 'red':
        for script in ('stage_backgrounds.sh', 'stage_milestone.sh'):
            name = relative + '/tools/' + script
            (root / name).write_bytes(subprocess.check_output([
                'git', '-C', str(repo), 'show', args.baseline_ref + ':' + name]))
    subprocess.run(['git', '-C', str(root), 'init', '-q'], check=True)
    subprocess.run(['git', '-C', str(root), 'add', '.'], check=True)
    subprocess.run(['git', '-C', str(root), '-c', 'user.name=Fixture', '-c',
                    'user.email=fixture@example.invalid', 'commit', '-qm', 'Test input'], check=True)
    theme = recipe / 'share/plasma/desktoptheme/kubabbar-glass'
    (theme / 'untracked-note').write_text('private test note\n')
    (theme / '__pycache__').mkdir()
    (theme / '__pycache__/stray.pyc').write_bytes(b'not bytecode')
    for script, subdir in (('stage_backgrounds.sh', 'background-alpha'),
                           ('stage_milestone.sh', 'kubabbar-glass')):
        stage = args.work.resolve() / (case + '-' + subdir)
        subprocess.run(['bash', str(recipe / 'tools' / script)], check=True,
                       env=os.environ | {'SPARKY_STAGING_DIR': str(stage)})
        output = stage / 'classic-look' / subdir
        for name in ('untracked-note', '__pycache__/stray.pyc'):
            assert (output / 'usr/share/plasma/desktoptheme/kubabbar-glass' / name).exists() == (case == 'red')
        if case == 'green':
            prefix = 'share/' if subdir == 'kubabbar-glass' else 'share/plasma/desktoptheme/'
            for entry in filter(None, tracked):
                name = os.fsdecode(entry)
                if not name.startswith(relative + '/' + prefix):
                    continue
                path = Path(name).relative_to(relative)
                if subdir == 'background-alpha' and path.parts[3] not in ('kubabbar-glass', 'sparky-stereo-oxygen'):
                    continue
                source, target = recipe / path, output / 'usr' / path
                assert target.exists() or target.is_symlink(), path
                if source.is_symlink():
                    assert os.readlink(source) == os.readlink(target), path
                else:
                    assert source.read_bytes() == target.read_bytes(), path
            retry = subprocess.run(['bash', str(recipe / 'tools' / script)],
                                   env=os.environ | {'SPARKY_STAGING_DIR': str(stage)}, capture_output=True)
            assert retry.returncode != 0 and b'Use a new staging directory' in retry.stderr
        print(case, script, 'PASS', flush=True)
