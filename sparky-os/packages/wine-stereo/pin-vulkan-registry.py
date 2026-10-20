#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Retain the Vulkan registry matching Wine's existing 1.4.318 generator patch."""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request

COMMIT = 'b39ab380a44b6c8df462c34e976ea9ce2d2c336b'
FILES = {
    'registry/vk.xml': '2b74b4439e44d8f425ea8e46d63dcbdbb85a0ddc00ecbc375611afa2c6c6e7d2',
    'registry/video.xml': '6c2e54f08665e38101caeca53d95032657bb0f722c85693d8c406c14388114b4',
    'LICENSE.md': 'ac24e5ea920e4318e4d02c4086ae51f53cfb03feed06c18df1019e7ada1ec7bc',
}


def main(root, cached=None):
    rules = root / 'debian/rules'
    original = rules.read_text()
    old = './make_vulkan -x /usr/share/vulkan/registry/vk.xml -X /usr/share/vulkan/registry/video.xml'
    if original.count(old) != 1 or not (root / 'debian/patches/generate/vulkan-1.4.318.patch').is_file():
        raise ValueError('Review changed Wine generator inputs')
    destination = root / 'debian/vulkan-registry'
    destination.mkdir(exist_ok=False)
    receipt = {'tag': 'v1.4.318', 'commit': COMMIT, 'files': {}}
    for name, expected in FILES.items():
        url = f'https://raw.githubusercontent.com/KhronosGroup/Vulkan-Headers/{COMMIT}/{name}'
        data = ((cached / Path(name).name).read_bytes() if cached
                else urllib.request.urlopen(url, timeout=60).read())
        if hashlib.sha256(data).hexdigest() != expected:
            raise ValueError(f'Unexpected registry input: {name}')
        (destination / Path(name).name).write_bytes(data)
        receipt['files'][Path(name).name] = {'url': url, 'sha256': expected, 'bytes': len(data)}
    (destination / 'provenance.json').write_text(json.dumps(receipt, indent=2) + '\n')
    rules.write_text(original.replace(old, './make_vulkan -x ../../debian/vulkan-registry/vk.xml -X ../../debian/vulkan-registry/video.xml'))
    path = root / 'debian/sparky-lean-preserve.json'
    plan = json.loads(path.read_text()) if path.exists() else {}
    for name in ('include/wine/vulkan.h', 'dlls/winevulkan/vulkan_thunks.c',
                 'dlls/winevulkan/vulkan_thunks.h', 'dlls/winevulkan/loader_thunks.c',
                 'dlls/winevulkan/loader_thunks.h'):
        # Debian's repacked source can omit generated outputs entirely. Preserve
        # only existing inputs; absent ones are outside the native prepass.
        if (root / name).is_file():
            plan[name] = 'make_vulkan regenerates this input during configure; do not count a discarded prepass as compiler input savings'
    path.write_text(json.dumps(plan, indent=2) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--cached', type=Path)
    args = parser.parse_args()
    main(args.source.resolve(), args.cached)
