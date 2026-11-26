#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Make ffmpeg-dmo 10:9.1-dmo1+stereo3d18(+lc1): deb-multimedia's 10:9.1-dmo1 with the edition's series (queue row 916).

Usage: make-source-stereo3d18.py DMO_DSC PUBLISHED15_DSC OUTDIR
DMO_DSC is deb-multimedia's ffmpeg-dmo_9.1-dmo1.dsc, PUBLISHED15_DSC the published ffmpeg-dmo_9.0.2-dmo1+stereo3d15+lc1.dsc;
both are checked against media/ffmpeg/stereo3d18/sources.sha256 and dpkg-source checks every file they name, so the
source is made from inputs named by their sums, never from a work tree. Steps:
  1. deb-multimedia's 9.1-dmo1 tree, its patches not applied (its packaging taken whole);
  2. the edition's changes to debian/control and debian/rules, each applied exactly once or the script stops:
     libstereo-dibr on amd64, Fraunhofer's non-free libfdk-aac and libfdk-xhe-aac only under the pkg.ffmpeg-dmo.fdk
     profile (no --enable-nonfree in the packages that are shipped), x265 ABI 30219, no libnvidia-glvkspirv,
     and the xfade easing header copied again;
  3. the recipe's series (deb-multimedia's 01_clean-output.patch, then the edition's 116 patches, HandBrake's included);
  4. the changelog: the +stereo3d18 entry, deb-multimedia's stanzas newer than 9.0.2-dmo1, the +stereo3d17 entry (the
     wording of build commit 48b7c24f, its date as built), the published +15's own entries down to +stereo3d1, then
     deb-multimedia's history from 9.0.2-dmo1 down;
  5. the published +15's Lean Code preserve plan carried by lean.debian_prepare, then dpkg-source -b next to the orig
     tarball and its signature, dated by the recipe's commit (ORDER 421).
"""
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SPARKY_OS = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(SPARKY_OS.parent))
sys.path.insert(0, str(SPARKY_OS))
sys.path.insert(0, str(SPARKY_OS / 'repo'))
from lean import debian_prepare
import reproducible
from patch_authors import sanitize_patches

RECIPE = SPARKY_OS / 'media/ffmpeg/stereo3d18'
NEXT = '10:9.1-dmo1+stereo3d18'
DMO = '10:9.1-dmo1'
PLAIN15 = '10:9.0.2-dmo1+stereo3d15'
SPLIT = '10:9.0.2-dmo1'

CONTROL = [
    ('debhelper-compat (= 14), libmp3lame-dev,', 'debhelper-compat (= 14), libstereo-dibr-dev (>= 1.7.0) [amd64], libmp3lame-dev,'),
    ('libfdk-aac-dev,', 'libfdk-aac-dev <pkg.ffmpeg-dmo.fdk>,'),
    ('libfdk-xhe-aac-dev,', 'libfdk-xhe-aac-dev <pkg.ffmpeg-dmo.fdk>,'),
    ('libx265-dev (>= 1:3.5)', 'libx265-dev (>= 1:4.3-dmo1+stereo3d2+lc1)'),
    (' libnvidia-glvkspirv [amd64 i386],', ''),
]
RULES = [
    ('\t--enable-libfdk-aac \\\n', ''),
    ('\t--enable-libfdk-xhe-aac \\\n', ''),
    ('\t--enable-nonfree \\\n', ''),
    ('\tCONFIG_ALL += --disable-optimizations\nendif\n', '''\tCONFIG_ALL += --disable-optimizations
endif

# Depth-image-based rendering (the dibr filter) through libstereo-dibr of stereo-layer, which the
# edition builds for amd64.
ifeq ($(DEB_HOST_ARCH),amd64)
\tCONFIG_ALL += --enable-libstereodibr
endif

# Fraunhofer's AAC encoder (libfdk-aac) and xHE-AAC library (libfdk-xhe-aac) are non-free: FFmpeg's
# LICENSE.md calls a GPL build that enables them unredistributable. They stay out of the packages that
# are shipped; the build profile pkg.ffmpeg-dmo.fdk (sparky-stereo-ffmpeg-fdk) turns them on for a
# build on one machine.
ifneq (,$(filter pkg.ffmpeg-dmo.fdk,$(DEB_BUILD_PROFILES)))
\tCONFIG_ALL += --enable-libfdk-aac --enable-libfdk-xhe-aac --enable-nonfree
endif
'''),
    ('#\tcp debian/xfade-easing.h libavfilter/\n', '\tcp debian/xfade-easing.h libavfilter/\n'),
]


def once(text, old, new, what):
    if text.count(old) != 1:
        sys.exit(f'make-source-stereo3d18: {what}: expected exactly one {old!r}, found {text.count(old)}')
    return text.replace(old, new)


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def stanzas(changelog):
    """[(version, text)] of a Debian changelog, in order."""
    parts = re.split(r'(?m)^(?=ffmpeg-dmo \()', changelog)
    out = []
    for part in parts:
        if part.strip():
            m = re.match(r'ffmpeg-dmo \(([^)]+)\)', part)
            if not m:
                sys.exit('make-source-stereo3d18: a changelog stanza without a version')
            out.append((m.group(1), part))
    return out


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    dmo_dsc, p15_dsc, out = (Path(a).resolve() for a in sys.argv[1:4])
    wanted = dict(line.split()[::-1] for line in (RECIPE / 'sources.sha256').read_text().splitlines() if line.strip())
    for dsc in (dmo_dsc, p15_dsc):
        if wanted.get(dsc.name) != sha256(dsc):
            sys.exit(f'make-source-stereo3d18: {dsc.name} does not have the sum the recipe names')
    try:
        stamp = reproducible.epoch([RECIPE, Path(__file__)])
    except reproducible.NoRecipeDate as error:
        sys.exit(f'make-source-stereo3d18: {error}')
    os.environ.update(DEBFULLNAME='Daniel Ramos (Capitain Jack)', DEBEMAIL='Capitain_Jack@yahoo.com', TZ='UTC',
                      SOURCE_DATE_EPOCH=str(stamp))
    out.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='mk18-', dir=out))
    new, p15 = work / 'new', work / 'p15'
    subprocess.run(['dpkg-source', '--skip-patches', '-x', str(dmo_dsc), str(new)], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(['dpkg-source', '--skip-patches', '-x', str(p15_dsc), str(p15)], check=True, stdout=subprocess.DEVNULL)
    plan = work / 'plan.json'
    subprocess.run([sys.executable, str(SPARKY_OS / 'repo/plain-from-lc.py'), '--save-plan', str(plan), str(p15)], check=True)
    version = subprocess.check_output(['dpkg-parsechangelog', '-l', str(new / 'debian/changelog'), '-SVersion'], text=True).strip()
    if version != DMO:
        sys.exit(f'make-source-stereo3d18: {dmo_dsc.name} gives {version}, not {DMO}')
    control = (new / 'debian/control').read_text()
    for old, repl in CONTROL:
        control = once(control, old, repl, 'debian/control')
    (new / 'debian/control').write_text(control)
    rules = (new / 'debian/rules').read_text()
    for old, repl in RULES:
        rules = once(rules, old, repl, 'debian/rules')
    (new / 'debian/rules').write_text(rules)
    pd = new / 'debian/patches'
    for stale in ('02_vf_xfade-3.6.6.patch', '03_fix-padding-in-mp3.patch'):
        if (pd / stale).exists():
            (pd / stale).unlink()
    for p in sorted((RECIPE / 'patches').glob('*.patch')):
        shutil.copy2(p, pd / p.name)
    shutil.copy2(RECIPE / 'patches/series', pd / 'series')
    listed = [l for l in (pd / 'series').read_text().split('\n') if l]
    missing = [p for p in listed if not (pd / p).is_file()]
    if missing:
        sys.exit(f'make-source-stereo3d18: the series names patches the tree lacks: {missing}')
    sanitize_patches(pd)
    dmo_st = stanzas((new / 'debian/changelog').read_text())
    p15_st = stanzas((p15 / 'debian/changelog').read_text())
    if p15_st[0][0] != PLAIN15:
        sys.exit(f'make-source-stereo3d18: the published source\'s plain changelog starts at {p15_st[0][0]}, not {PLAIN15}')
    di = next(i for i, (v, _) in enumerate(dmo_st) if v == SPLIT)
    pi = next(i for i, (v, _) in enumerate(p15_st) if v == SPLIT)
    if [t for _, t in dmo_st[di:di + 1]] != [t for _, t in p15_st[pi:pi + 1]]:
        sys.exit(f'make-source-stereo3d18: deb-multimedia\'s {SPLIT} stanza differs from the published source\'s')
    entry = (RECIPE / 'changelog.entry').read_text().replace('@VERSION@', NEXT).replace('@DATE@', reproducible.rfc2822(stamp))
    history = (RECIPE / 'history-stereo3d17.entry').read_text()
    parts = [entry, *[t for _, t in dmo_st[:di]], history, *[t for _, t in p15_st[:pi]], *[t for _, t in dmo_st[di:]]]
    text = ''
    for part in parts:
        text += part.rstrip('\n') + '\n\n'
    (new / 'debian/changelog').write_text(text.rstrip('\n') + '\n')
    # the published plan (libswscale/aarch64/ops_entries.c, which FATE compares byte for byte) is carried as it is
    debian_prepare.prepare(new, NEXT + '+lc1', SPARKY_OS, carried_plan=plan)
    for f in dmo_dsc.parent.glob('ffmpeg-dmo_9.1.orig.tar.xz*'):
        if not (work / f.name).exists():    # dpkg-source -x links them beside the tree it unpacks
            os.symlink(f, work / f.name)
    reproducible.pack(work, 'new', stamp)
    for f in work.glob('ffmpeg-dmo_9.1-dmo1+*'):
        shutil.copyfile(f, out / f.name)
    for f in dmo_dsc.parent.glob('ffmpeg-dmo_9.1.orig.tar.xz*'):
        shutil.copyfile(f, out / f.name)
    shutil.rmtree(work)
    print(sorted(p.name for p in out.iterdir()))


if __name__ == '__main__':
    main()
