#!/usr/bin/env python3
"""ffmpeg-dmo 10:9.0.2-dmo1+stereo3d11(+lc1): the published +stereo3d9+lc1 source with FFmpeg pull request 25395 as corrected after its review
(ORDER 416): patches 0010 to 0013 replaced, 0068 added after 0011, the whole new series, a changelog entry, the toolkit of this tree.
Steps: plain debian/ (plain-from-lc.py on `dpkg-source --skip-patches -x` of the published .dsc, so upstream is pristine) + the recipe's patches
and series + the entry -> lean.debian_prepare with this tree's toolkit -> dpkg-source -b next to the published orig tarball.
Why not lc-successor.py: its --in-place --overlay keeps the old patched upstream tree, so a replaced patch makes dpkg-source -b stop with
"unexpected upstream changes"; its --recipe mode only allows debian/ changes.
Usage: make-source.py PLAIN0 ORIGTARBALL OUTDIR     (PLAIN0 = the plain tree: dpkg-source --skip-patches -x PUBLISHED.dsc PLAIN0, then
plain-from-lc.py PLAIN0)"""
import email.utils, os, shutil, subprocess, sys, tempfile
from pathlib import Path
SPARKY_OS = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(SPARKY_OS.parent))
sys.path.insert(0, str(SPARKY_OS))
from lean import debian_prepare
RECIPE = SPARKY_OS / 'media/ffmpeg/stereo3d11'
NEXT = '10:9.0.2-dmo1+stereo3d11'
plain0, orig, out = (Path(a).resolve() for a in sys.argv[1:4])
out.mkdir(parents=True, exist_ok=True)
os.environ.update(DEBFULLNAME='Daniel Ramos (Capitain Jack)', DEBEMAIL='Capitain_Jack@yahoo.com', TZ='America/Sao_Paulo')
work = Path(tempfile.mkdtemp(prefix='mk-', dir=out))
new = work / 'new'
shutil.copytree(plain0, new, symlinks=True, ignore=lambda d, n: ['debian'] if Path(d) == plain0 else [])
shutil.copytree(plain0 / 'debian', new / 'debian', symlinks=True)
pd = new / 'debian/patches'
for p in sorted((RECIPE / 'patches').glob('0*.patch')):
    shutil.copy2(p, pd / p.name)
shutil.copy2(RECIPE / 'patches/series', pd / 'series')
entry = (RECIPE / 'changelog.entry').read_text().replace('@VERSION@', NEXT).replace('@DATE@', email.utils.formatdate(localtime=True))
ch = new / 'debian/changelog'
ch.write_text(entry + '\n' + ch.read_text())
debian_prepare.prepare(new, NEXT + '+lc1', SPARKY_OS, preserve_sources=[])
os.symlink(orig, work / orig.name)
subprocess.run(['dpkg-source', '-b', 'new'], cwd=work, check=True)
for f in work.glob('ffmpeg-dmo_9.0.2-dmo1+*'):
    shutil.copyfile(f, out / f.name)
shutil.rmtree(work)
print(sorted(p.name for p in out.iterdir()))
