#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
"""Copy current tracked files, or an exported folder without Python caches.

The destination receives the contents of SOURCE, not another SOURCE directory.
Git is required even for exports: a broken checkout must never look like one.
"""
import argparse
import os
from pathlib import Path
import stat
import subprocess
import sys


def git(source, *args):
    return subprocess.run(['git', '-C', str(source), *args],
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          env=os.environ | {'LC_ALL': 'C'})


def inventory(source):
    probe = git(source, 'rev-parse', '--is-inside-work-tree')
    if probe.returncode == 0:
        if probe.stdout.strip() != b'true':
            raise ValueError(f'{source}: not a Git working tree')
        listing = git(source, 'ls-files', '--stage', '-z', '--', '.')
        if listing.returncode:
            raise ValueError(listing.stderr.decode(errors='replace').strip())
        paths = []
        for entry in listing.stdout.split(b'\0'):
            if not entry:
                continue
            info, name = entry.split(b'\t', 1)
            mode, _, stage = info.split()
            if stage != b'0' or mode not in (b'100644', b'100755', b'120000'):
                raise ValueError(f'{os.fsdecode(name)!r}: unresolved index or submodule; export it separately')
            paths.append(Path(os.fsdecode(name)))
        if not paths:
            raise ValueError(f'{source}: no tracked files; add the recipe inputs to Git first')
        print(f'copy-recipe: {source}: files as git tracks them', flush=True)
        return paths
    # Git errors other than absence of a repository are not an export route.
    for parent in (source, *source.parents):
        if os.path.lexists(parent / '.git'):
            raise ValueError(probe.stderr.decode(errors='replace').strip())
    if (probe.returncode != 128 or
            not probe.stderr.startswith(b'fatal: not a git repository')):
        raise ValueError(probe.stderr.decode(errors='replace').strip())
    print(f'copy-recipe: {source}: no git work tree; folder without __pycache__ and *.pyc', flush=True)
    paths = []

    def failed(error):
        raise error

    for folder, directories, files in os.walk(source, onerror=failed, followlinks=False):
        for name in directories[:]:
            path = Path(folder) / name
            if name in ('.git', '__pycache__'):
                directories.remove(name)
            elif path.is_symlink():
                directories.remove(name)
                if not name.endswith('.pyc'):
                    paths.append(path.relative_to(source))
        paths.extend((Path(folder) / name).relative_to(source)
                     for name in files if name not in ('.git', '__pycache__') and not name.endswith('.pyc'))
    return paths


def copy(source, destination):
    source, destination = source.resolve(strict=True), destination.absolute()
    if destination.resolve().is_relative_to(source):
        raise ValueError('destination must be outside the source folder')
    paths = inventory(source)
    for relative in paths:
        if relative.is_absolute() or '..' in relative.parts:
            raise ValueError(f'invalid source path: {relative!s}')
        for parent in relative.parents:
            if (source / parent).is_symlink():
                raise ValueError(f'{source / parent}: source directory became a symlink')
        mode = (source / relative).lstat().st_mode
        if not (stat.S_ISREG(mode) or stat.S_ISLNK(mode)):
            raise ValueError(f'{source / relative}: expected a file or symlink')
        for target in (destination / relative, *(destination / relative).parents):
            if target.is_symlink():
                raise ValueError(f'{target}: destination contains a symlink')
    destination.mkdir(parents=True, exist_ok=True)
    for start in range(0, len(paths), 128):
        subprocess.run(['cp', '-a', '--parents', '-t', str(destination), '--',
                        *(str(p) for p in paths[start:start + 128])], cwd=source, check=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    try:
        copy(args.source, args.destination)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'copy-recipe: {error}; fix the input or build tools and retry\n')
