#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Reject drift between the retained base and RT release source plans."""
import argparse
import json
from pathlib import Path


def check(plans):
    if set(plans) != {'base', 'v3', 'rt'}:
        raise ValueError('Expected the base, v3 and rt source plans')
    base, rt = plans['base'], plans['rt']
    for field in ('tag', 'commit', 'source_tree', 'patches'):
        if base[field] != rt[field]:
            raise ValueError('Base/RT source parity differs in ' + field
                             + '; review compatibility explicitly before building')
    for flavour, plan in plans.items():
        if plan['flavour'] != flavour or plan['tag'] != base['tag'] or plan['commit'] != base['commit']:
            raise ValueError('Flavour identity or upstream revision differs: ' + flavour)
        paths = [row['path'] for row in plan['patches']]
        if len(paths) != len(set(paths)):
            raise ValueError('Duplicate patch in ' + flavour)
        by_path = {row['path']: row['sha256'] for row in plan['patches']}
        for row in base['patches']:
            if by_path.get(row['path']) != row['sha256']:
                raise ValueError(flavour + ': common patch absent or different: ' + row['path'])
    return len(base['patches'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    args = parser.parse_args()
    count = check(json.loads(args.manifest.read_text()))
    print(f'Kernel source parity: base/RT identical, {count} common patches retained in every flavour')
