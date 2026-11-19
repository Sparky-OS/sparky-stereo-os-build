#!/usr/bin/python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
# SPDX-License-Identifier: GPL-3.0-or-later
"""Prepare the pinned, bank-free upstream snapshot and build it through the native LC route.

Run inside the build container: build.py PROJECT UPSTREAM_CHECKOUT EMPTY_WORK.
The checkout is read-only. No download, ROM acquisition or host setting is part of this recipe.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import io

here = Path(__file__).resolve().parent
project, upstream, work = sys.argv[1:]
meta = json.loads((here / 'projects.json').read_text())[project]
upstream, work = Path(upstream), Path(work)
if subprocess.check_output(['git', '-C', str(upstream), 'rev-parse', 'HEAD'], text=True).strip() != meta['commit']:
    raise SystemExit('upstream commit differs from the pinned source')
work.mkdir(parents=True, exist_ok=True)
if list(work.iterdir()):
    raise SystemExit('work directory is not empty')
source = work / 'tree'
source.mkdir()
archive = subprocess.check_output(['git', '-C', str(upstream), 'archive', '--format=tar', meta['commit']])
if hashlib.sha256(archive).hexdigest() != meta['upstream_tree_tar_sha256']:
    raise SystemExit('upstream archive fingerprint differs')
with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
    tar.extractall(source, filter='data')
removed = []
if project == 'libADLMIDI':
    excluded = ['fm_banks', 'fm_banks_new', 'banks.ini', 'banks-no-grey.ini',
                'src/inst_db.cpp', 'src/inst_db_no_grey.cpp', 'test.wopl']
elif project == 'libOPNMIDI':
    excluded = ['fm_banks', 'utils/vlc_codec', 'utils/winmm_drv', 'utils/fmmidi_prog',
                'src/chips/mamefm/fmopn_2608rom.h', 'src/chips/nuked_lle/fmopna_rom.h',
                'src/chips/pmdwin/rhythmdata.c', 'src/chips/pmdwin/rhythmdata.h']
else:
    excluded = []
for path in excluded:
    target = source / path
    if target.exists():
        removed.append(path)
        shutil.rmtree(target) if target.is_dir() else target.unlink()
if project in ('libADLMIDI', 'libOPNMIDI'):
    for target in list(source.rglob('*')):
        if target.is_file() and target.suffix.lower() in ('.wopl', '.wopn', '.mid', '.midi', '.mus', '.imf'):
            removed.append(str(target.relative_to(source))); target.unlink()
# The application consumes the distro's font alternatives and remains individually configurable.
if project == 'dosbox-staging':
    subprocess.run(['patch', '-p1', '-i', str(here / 'patches/dosbox-system-zlib.patch')], cwd=source, check=True)
    p = source / 'src/midi/fluidsynth.cpp'
    before = p.read_text()
    needle = 'AddString("soundfont", WhenIdle, "default.sf2")'
    if before.count(needle) != 1:
        raise SystemExit('upstream soundfont default changed; review the integration')
    p.write_text(before.replace(needle, 'AddString("soundfont", WhenIdle, "default-GM.sf2")'))
    p = source / 'src/midi/midi.cpp'
    text = p.read_text()
    needle = 'static auto DefaultMidiDevicePref = MidiDevicePortPref;'
    if text.count(needle) != 1:
        raise SystemExit('DOSBox MIDI default changed')
    p.write_text(text.replace(needle, 'static auto DefaultMidiDevicePref = "fluidsynth";'))
    p = source / 'src/midi/fluidsynth.cpp'
    text = p.read_text()
    text = '#include <cstdlib>\n' + text.replace('throw std::runtime_error(msg);',
        'std::system("/usr/bin/sparky-stereo-audio midi --emulator-error DOSBox-Staging");\n\t\tthrow std::runtime_error(msg);')
    needle = '\tsynth    = std::move(fluid_synth);'
    if text.count(needle) != 1:
        raise SystemExit('DOSBox successful synth initialization changed')
    text = text.replace(needle, '\tstd::system("/usr/bin/sparky-stereo-audio midi --emulator-ready DOSBox-Staging");\n' + needle)
    p.write_text(text)

# Forward a real missing-ROM failure through the edition's translated problems engine.
if project == 'munt':
    p = source / 'mt32emu_qt/src/QSynth.cpp'
    text = p.read_text().replace('#include <cstring>', '#include <cstring>\n#include <QProcess>')
    needle = '\t\tqDebug() << "Missing ROM files. Can\'t open synth :(";'
    if text.count(needle) != 1:
        raise SystemExit('Munt ROM failure handler changed')
    text = text.replace(needle, needle + '\n\t\tQProcess::execute("/usr/bin/sparky-stereo-audio", {"midi", "--rom-error", "Munt"});')
    p.write_text(text)
if project == 'dosbox-staging':
    p = source / 'src/midi/mt32.cpp'
    text = p.read_text()
    needle = '\tif (!loaded_model_and_dir) {'
    if text.count(needle) != 1:
        raise SystemExit('DOSBox ROM failure handler changed')
    text = '#include <cstdlib>\n' + text.replace(needle, needle + '\n\t\tstd::system("/usr/bin/sparky-stereo-audio midi --rom-error DOSBox-Staging");')
    p.write_text(text)
shutil.copytree(here / 'debian' / project, source / 'debian')
if project == 'dosbox-staging':
    shutil.copytree(here / 'patches', source / 'debian/downstream-patches')
(source / 'debian/upstream-source.json').write_text(json.dumps(dict(meta, excluded=removed), indent=2) + '\n')
(source / 'debian/rules').chmod(0o755)
notices = source / 'debian/upstream-notices'
notices.mkdir()
for p in list(source.rglob('*')):
    if not p.is_file() or 'debian' in p.relative_to(source).parts:
        continue
    rel = p.relative_to(source)
    if any(word in p.name.lower() for word in ('license', 'copying', 'authors')):
        target = notices / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(p, target)
# Include source headers because permissive component notices often live only there.
with (notices / 'source-notices.txt').open('w') as out:
    for p in sorted(source.rglob('*')):
        if not p.is_file() or 'debian' in p.relative_to(source).parts or p.suffix not in ('.c', '.cpp', '.h', '.hpp', '.cc'):
            continue
        text = p.read_text(errors='replace')
        if text.startswith('/*') and '*/' in text:
            out.write(str(p.relative_to(source)) + '\n' + text.split('*/', 1)[0] + '*/\n\n')
for package in [part.split('\n',1)[0] for part in (source / 'debian/control').read_text().split('Package: ')[1:]]:
    with (source / 'debian' / (package + '.docs')).open('a') as out:
        out.write('debian/upstream-notices\n')

# Exclusions precede source assembly. A source fingerprint does not authorize unknown banks.
for p in source.rglob('*'):
    if p.is_file() and p.suffix.lower() in ('.rom', '.sf2', '.sf3', '.wopl', '.wopn'):
        raise SystemExit('unapproved data in source: ' + str(p.relative_to(source)))
root = here.parent.parent
os.environ.update(DEBFULLNAME='Daniel Ramos (Capitain Jack)', DEBEMAIL='Capitain_Jack@yahoo.com')
os.environ['PYTHONPATH'] = str(root)
os.environ['DEB_BUILD_OPTIONS'] = 'parallel=4'
subprocess.run(['python3', '-m', 'lean.debian_prepare', str(source), meta['version'] + '+lc1', '--toolkit', str(root)], check=True)
subprocess.run(['python3', str(root / 'repo/reproducible.py'), 'normalize-tree', os.environ['SOURCE_DATE_EPOCH'], str(source)], check=True)
subprocess.run(['dpkg-buildpackage', '-us', '-uc', '-sa', '-j4'], cwd=source, check=True)
