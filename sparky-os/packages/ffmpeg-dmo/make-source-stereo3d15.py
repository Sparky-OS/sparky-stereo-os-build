#!/usr/bin/env python3
"""Make +stereo3d15 from plain +stereo3d15.

Usage: make-source-stereo3d15.py PLAIN14 ORIGTARBALL OUTDIR PLAN
Extract +14 with --skip-patches, then use plain-from-lc.py --save-plan PLAN.
All architectures are built from the one resulting source package.
"""
import os, shutil, sys, tempfile
from pathlib import Path
SPARKY_OS = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(SPARKY_OS.parent))
sys.path.insert(0, str(SPARKY_OS))
sys.path.insert(0, str(SPARKY_OS / 'repo'))
from lean import debian_prepare
import reproducible
from patch_authors import sanitize_patches
RECIPE = SPARKY_OS / 'media/ffmpeg/stereo3d15'
BASE = '10:9.0.2-dmo1+stereo3d14'
NEXT = '10:9.0.2-dmo1+stereo3d15'
plain14, orig, out, plan = (Path(a).resolve() for a in sys.argv[1:5])
first = (plain14 / 'debian/changelog').read_text().split('\n', 1)[0]
if f'({BASE})' not in first:
    sys.exit(f'make-source-stereo3d15: {plain14} is not the plain source of {BASE}: {first}')
out.mkdir(parents=True, exist_ok=True)
# ORDER 421: the date of the source is the recipe's (the last commit that touched the recipe folder or this script, or
# SOURCE_DATE_EPOCH); the clock, the zone, the umask and the checkout time do not reach the bytes.
try:
    STAMP = reproducible.epoch([RECIPE, Path(__file__)])
except reproducible.NoRecipeDate as error:
    sys.exit(f'make-source-stereo3d15: {error}')
os.environ.update(DEBFULLNAME='Daniel Ramos (Capitain Jack)', DEBEMAIL='Capitain_Jack@yahoo.com', TZ='UTC', SOURCE_DATE_EPOCH=str(STAMP))
work = Path(tempfile.mkdtemp(prefix='mk-', dir=out))
new = work / 'new'
shutil.copytree(plain14, new, symlinks=True, ignore=lambda d, n: ['debian'] if Path(d) == plain14 else [])
shutil.copytree(plain14 / 'debian', new / 'debian', symlinks=True)
pd = new / 'debian/patches'
for p in sorted((RECIPE / 'patches').glob('0*.patch')):
    shutil.copy2(p, pd / p.name)
shutil.copy2(RECIPE / 'patches/series', pd / 'series')
listed = [l for l in (pd / 'series').read_text().split('\n') if l]
missing = [p for p in listed if not (pd / p).is_file()]
if missing:
    sys.exit(f'make-source-stereo3d15: the series names patches the tree lacks: {missing}')
sanitize_patches(pd)
entry = (RECIPE / 'changelog.entry').read_text().replace('@VERSION@', NEXT).replace('@DATE@', reproducible.rfc2822(STAMP))
ch = new / 'debian/changelog'
ch.write_text(entry + '\n' + ch.read_text())
debian_prepare.prepare(new, NEXT + '+lc1', SPARKY_OS, preserve_sources=[(
    "libswscale/aarch64/ops_entries.c",
    "FATE sws-ops-entries-aarch64 compares this generated-source reference byte for byte"
)], carried_plan=plan)
os.symlink(orig, work / orig.name)
reproducible.pack(work, 'new', STAMP)
for f in work.glob('ffmpeg-dmo_9.0.2-dmo1+*'):
    shutil.copyfile(f, out / f.name)
shutil.rmtree(work)
print(sorted(p.name for p in out.iterdir()))
