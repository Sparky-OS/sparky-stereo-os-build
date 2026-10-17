#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""Docker's default seccomp profile, plus personality(ADDR_NO_RANDOMIZE) for setarch -R.

usage: seccomp-setarch.py <default.json> <output.json>
<default.json> is the profile the Docker daemon in use was built with
(vendor/github.com/moby/profiles/seccomp/default.json at the daemon's commit).
Everything else stays as Docker sets it: with seccomp off altogether, Bubblewrap
gets far enough to fail where it otherwise falls back, and glycin's image
loaders, which savers use for their textures, then fail.
"""
import json
import sys

ADDR_NO_RANDOMIZE = 0x0040000
profile = json.load(open(sys.argv[1]))
assert any('personality' in rule['names'] for rule in profile['syscalls']), 'not a Docker default profile'
rule = {'names': ['personality'], 'action': 'SCMP_ACT_ALLOW',
        'args': [{'index': 0, 'value': ADDR_NO_RANDOMIZE, 'op': 'SCMP_CMP_EQ'}]}
if rule not in profile['syscalls']:
    profile['syscalls'].append(rule)
json.dump(profile, open(sys.argv[2], 'w'), indent=1)
