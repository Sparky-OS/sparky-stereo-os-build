# SPDX-License-Identifier: GPL-2.0-or-later
import json
from pathlib import Path
import numpy as np
from PIL import Image
root = Path('out/window-sizing')
old = (root/'before/client.log').read_text()
assert 'raw=1600' in old and 'Assertion' in old, old
assert not json.loads((root/'before/run.json').read_text())['client_alive_at_end']
for name in ('after', 'quad', 'future', 'gears'):
    run = json.loads((root/name/'run.json').read_text())
    assert run['client_alive_at_end'], name
    assert '_KDE_NET_WM_STEREO_CONTENT(CARDINAL) = 3' in run['x11']['window']
    assert '_KDE_NET_WM_STEREO_CONTENT_CLASS:  not found' in run['x11']['window']
    assert '= '+('4' if name == 'future' else '3') in run['x11']['root']
    if name != 'gears':
        assert 'PASS: initial size' in (root/name/'client.log').read_text(), name
    for capture in ('c00', 'c01'):
        image = Image.open(root/name/(capture+'.png')).convert('RGB')
        assert image.size == (2560,800), (name, image.size)
        a = np.array(image)
        left, right = a[:,:1280], a[:,1280:]
        for channel in (0,2):
            masks = [(eye[:,:,channel] > (80 if name == 'gears' else 200)) & (eye[:,:,1] < 50) &
                     (eye[:,:,2-channel] < 50) for eye in (left,right)]
            counts = [int(m.sum()) for m in masks]
            if name == 'gears':
                assert min(counts) > 1000, (name, channel, counts)
            else:
                assert counts == [18000,18000], (name, channel, counts)
                assert np.array_equal(*masks), (name, '2D disparity')
        Image.fromarray(left).save(root/name/(capture+'-LEFT.png'))
        Image.fromarray(right).save(root/name/(capture+'-RIGHT.png'))
    print('PASS:', name, 'both composed eyes and format-only declaration')
print('PASS: old double-resize rejected at 1600; v3/v4, quad and legacy visual rendering')
