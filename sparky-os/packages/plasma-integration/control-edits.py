# Created by Daniel Ramos (Capitain Jack) 2026/11/22
# plasma-integration +stereo3d1 (queue row 77 milestone 2): the trigger links the stereo layer (Stereo::ScreenMode), and
# it learns of a drawn stereo icon only from KIconThemes +stereo3d3, which counts each drawing of one: a build
# dependency and a dependency of the feature.
# Copyright 2026 under the GNU GPL3 License
import sys
from pathlib import Path

p = Path(sys.argv[1])
s = p.read_text()
old = '               libkf6iconthemes-dev (>= 6.26.0~),\n'
assert s.count(old) == 1, 'Build-Depends line moved'
s = s.replace(old, old + '               libstereo-layer-dev (>= 1.22.0),\n')
old = 'Depends: breeze (>= 4:6.2.90~),\n'
assert s.count(old) == 1, 'Depends line moved'
s = s.replace(old, old + '         libkf6iconthemes6 (>= 6.32.0-1+stereo3d3~),\n')
p.write_text(s)
