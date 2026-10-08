#!/usr/bin/env python3
# Test helper: a copy of a .deb with another version, nothing else changed but the strict dependencies of the
# source's packages on the old version ("(= old)" becomes "(= new)"). The test repository gets its "+stereo3d3" update
# from the +stereo3d2 packages this way: only the version differs, so apt sees a newer FFmpeg, and the packages install.
# Usage: relabel-version.py in.deb OLDVERSION NEWVERSION out.deb
import os, re, shutil, subprocess, sys, tempfile
deb, old, new, out = sys.argv[1:5]
w = tempfile.mkdtemp(prefix='relabel-version.', dir=os.path.dirname(os.path.abspath(out)))
x = os.path.join(w, 'x')
subprocess.run(['dpkg-deb', '-R', deb, x], check=True)
cf = os.path.join(x, 'DEBIAN', 'control')
c = open(cf, encoding='utf-8').read()
c = re.sub(r'^Version: .*$', 'Version: ' + new, c, count=1, flags=re.M)
c = c.replace('(= %s)' % old, '(= %s)' % new)
open(cf, 'w', encoding='utf-8').write(c)
subprocess.run(['dpkg-deb', '--root-owner-group', '-Zxz', '-b', x, out], check=True, stdout=subprocess.DEVNULL)
shutil.rmtree(w)
