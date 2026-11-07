#!/usr/bin/env python3
"""ffmpeg-dmo 10:9.0.2-dmo1+stereo3d12(+lc1): the published +stereo3d9+lc1 source with FFmpeg pull request 25395 as corrected after its review
(ORDER 416, patches 0010 to 0013 replaced, 0068 added after 0011) and the h264_sei bound and the stereo3d eye order (ORDER 425, pull requests 25409
and 25377, patches 0069 to 0073): the whole series of the recipe, the changelog entries of +stereo3d12 and +stereo3d11, the toolkit of this tree.
Steps: plain debian/ (plain-from-lc.py on `dpkg-source --skip-patches -x` of the published .dsc, so upstream is pristine) + the recipe's patches
and series + the entry -> lean.debian_prepare with this tree's toolkit -> dpkg-source -b next to the published orig tarball.
Why not lc-successor.py: its --in-place --overlay keeps the old patched upstream tree, so a replaced patch makes dpkg-source -b stop with
"unexpected upstream changes"; its --recipe mode only allows debian/ changes.
Usage: make-source.py PLAIN0 ORIGTARBALL OUTDIR PLAN     (PLAIN0 = the plain tree: dpkg-source --skip-patches -x PUBLISHED.dsc PLAIN0, then
plain-from-lc.py --save-plan PLAN PLAIN0; PLAN is the published source's Lean Code preserve plan, which the next source keeps
byte for byte; a source without one leaves PLAN unwritten)"""
import os, shutil, subprocess, sys, tempfile
from pathlib import Path
SPARKY_OS = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(SPARKY_OS.parent))
sys.path.insert(0, str(SPARKY_OS))
sys.path.insert(0, str(SPARKY_OS / 'repo'))
from lean import debian_prepare
import reproducible
RECIPE = SPARKY_OS / 'media/ffmpeg/stereo3d12'
RECIPE11 = SPARKY_OS / 'media/ffmpeg/stereo3d11'
NEXT = '10:9.0.2-dmo1+stereo3d12'
NEXT11 = '10:9.0.2-dmo1+stereo3d11'
plain0, orig, out, plan = (Path(a).resolve() for a in sys.argv[1:5])
out.mkdir(parents=True, exist_ok=True)
# ORDER 421: the date of the source is the recipe's, the committer date of the last commit that touched the recipe folder or this
# script (or SOURCE_DATE_EPOCH); the clock, the zone, the umask and the checkout time do not reach the bytes.
try:
    STAMP = reproducible.epoch([RECIPE, Path(__file__)])
    STAMP11 = reproducible.epoch([RECIPE11])
except reproducible.NoRecipeDate as error:
    sys.exit(f'make-source: {error}')
os.environ.update(DEBFULLNAME='Daniel Ramos (Capitain Jack)', DEBEMAIL='Capitain_Jack@yahoo.com', TZ='UTC', SOURCE_DATE_EPOCH=str(STAMP))
work = Path(tempfile.mkdtemp(prefix='mk-', dir=out))
new = work / 'new'
shutil.copytree(plain0, new, symlinks=True, ignore=lambda d, n: ['debian'] if Path(d) == plain0 else [])
shutil.copytree(plain0 / 'debian', new / 'debian', symlinks=True)
pd = new / 'debian/patches'
for p in sorted((RECIPE / 'patches').glob('0*.patch')):
    shutil.copy2(p, pd / p.name)
shutil.copy2(RECIPE / 'patches/series', pd / 'series')
entry = (RECIPE / 'changelog.entry').read_text().replace('@VERSION@', NEXT).replace('@DATE@', reproducible.rfc2822(STAMP))
entry11 = (RECIPE11 / 'changelog.entry').read_text().replace('@VERSION@', NEXT11).replace('@DATE@', reproducible.rfc2822(STAMP11))
ch = new / 'debian/changelog'
ch.write_text(entry + '\n' + entry11 + '\n' + ch.read_text())
debian_prepare.prepare(new, NEXT + '+lc1', SPARKY_OS, preserve_sources=[], carried_plan=plan)
os.symlink(orig, work / orig.name)
reproducible.pack(work, 'new', STAMP)
for f in work.glob('ffmpeg-dmo_9.0.2-dmo1+*'):
    shutil.copyfile(f, out / f.name)
shutil.rmtree(work)
print(sorted(p.name for p in out.iterdir()))
