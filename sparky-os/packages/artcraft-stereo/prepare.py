#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright 2026 Daniel Campos Ramos
"""Prepare a retained ArtCraft source snapshot for the edition's Debian build.

Inputs: exported edition commit with SOURCE.edition.json and locked vendor/,
plus the accepted mkdeb.sh recipe. Never operates on the development checkout.
"""
import argparse
import email.utils
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1]))
from lean.debian_prepare import prepare


def main(root, legacy):
    root = root.resolve()
    origin = json.loads((root / 'SOURCE.edition.json').read_text())
    name = root.name
    if name not in ('filmcraft', 'photocraft') or not (root / 'vendor').is_dir():
        raise ValueError('Expected a FilmCraft or PhotoCraft snapshot with locked vendor inputs')
    version = origin['version']
    if (not re.fullmatch(r'[0-9][0-9A-Za-z.+:~\-]*\+lc1', version)
            or not re.fullmatch(r'[0-9a-f]{40}', origin['commit'])
            or (root / 'debian').exists()):
        raise ValueError('Expected a fresh disposable source and a version ending in +lc1')
    import yaml
    nfpm = yaml.safe_load((root / 'packaging/linux/nfpm.yaml').read_text())
    dependencies = ', '.join(nfpm['overrides']['deb']['depends'] + ['${shlibs:Depends}', '${misc:Depends}'])
    recommends = ', '.join(nfpm['overrides']['deb'].get('recommends', []))
    description = nfpm['description'].strip().splitlines()
    description = description[0] + '\n' + '\n'.join(' ' + (line or '.') for line in description[1:])
    debian = root / 'debian'
    (debian / 'source').mkdir(parents=True)
    maintainer = 'Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>'
    section = 'video' if name == 'filmcraft' else 'graphics'
    (debian / 'control').write_text(
        f'Source: {name}\nSection: {section}\nPriority: optional\nMaintainer: {maintainer}\n'
        'Build-Depends: debhelper-compat (= 13), cargo (>= 1.95), rustc (>= 1.95), '
        'pkgconf, cmake, nasm, libxkbcommon-dev, libwayland-dev, libx11-dev, libxrandr-dev, '
        'libxi-dev, libgl-dev, libgtk-3-dev, libasound2-dev, libfontconfig-dev, libfreetype-dev, '
        'libudev-dev, libssl-dev, libheif-dev, python3-yaml\n'
        'Standards-Version: 4.7.4\nRules-Requires-Root: no\nHomepage: https://sparkylinux.org\n\n'
        f'Package: {name}\nArchitecture: amd64\nDepends: {dependencies}\n'
        + (f'Recommends: {recommends}\n' if recommends else '')
        + f'Description: {description}\n .\n Edition build from committed stereo integration {origin["commit"]}.\n')
    (debian / 'changelog').write_text(
        f'{name} ({version.removesuffix("+lc1")}) unstable; urgency=medium\n\n'
        f'  * Retain the currently shipped source revision {origin["commit"]}.\n\n'
        f' -- {maintainer}  {email.utils.formatdate(localtime=False)}\n')
    (debian / 'source/format').write_text('3.0 (quilt)\n')
    (debian / 'source/options').write_text('extend-diff-ignore = (^|/)(target|dist|\\.sparky-lc)(/|$)\n')
    shutil.copy2(root / 'LICENSE-MIT', debian / 'copyright')
    shutil.copy2(HERE / 'cargo-checksums.py', debian / 'cargo-checksums.py')
    if name == 'filmcraft':
        patches = debian / 'patches'
        patches.mkdir()
        filename = 'filmcraft-test-frame-baseline.patch'
        shutil.copy2(HERE / filename, patches / filename)
        (patches / 'series').write_text(filename + '\n')
    shutil.copy2(root / 'packaging/linux/postinst.sh', debian / f'{name}.postinst')
    shutil.copy2(root / 'packaging/linux/postinst.sh', debian / f'{name}.postrm')
    stage = legacy.read_text().split('mkdir -p $STAGE/DEBIAN\n')[0]
    replacements = {
        'SRC=/lane/work/src/$APP': 'SRC=$PWD',
        'CARGO_TARGET_DIR=/tgt/target-$APP': 'CARGO_TARGET_DIR=$PWD/target',
        'V=/tgt/vendor-$APP': 'V=$PWD/vendor',
        "SHA=$(git config --global --add safe.directory '*' ; git rev-parse HEAD)":
            'SHA=$(python3 -c \'import json; print(json.load(open("SOURCE.edition.json"))["commit"])\')',
        'if [ ! -d $V ]; then cargo vendor --locked $V >/dev/null; fi': 'test -d "$V"',
        'export DIST=/tgt/dist-$APP': 'export DIST=$PWD/dist',
    }
    for old, new in replacements.items():
        if stage.count(old) != 1:
            raise ValueError(f'Accepted staging recipe changed: {old}')
        stage = stage.replace(old, new)
    stage = '\n'.join(line for line in stage.splitlines()
                      if not line.startswith('cargo "${CFG[@]}" build')) + '\n'
    stage += 'mkdir -p "debian/$APP"\ncp -a "$STAGE/usr" "debian/$APP/"\n'
    (debian / 'stage.sh').write_text(stage)
    (debian / 'accepted-mkdeb.sh').write_bytes(legacy.read_bytes())
    features = '--features heif' if name == 'photocraft' else ''
    test = 'stereo_view_ui' if name == 'photocraft' else 'stereo_monitor_ui'
    (debian / 'rules').write_text(f'''#!/usr/bin/make -f
export CARGO_HOME := $(CURDIR)/debian/cargo-home
export CARGO_TARGET_DIR := $(CURDIR)/target
export CARGO_BUILD_JOBS := 4
export CARGO_PROFILE_RELEASE_DEBUG := 0
export {name.upper()}_BUILD_SHA := {origin['commit']}
export {name.upper()}_BUILD_DATE = $(shell date -u -d @$(SOURCE_DATE_EPOCH) +%Y-%m-%d)
CARGO_FLAGS = --locked --offline --config "source.crates-io.replace-with='vendored-sources'" --config "source.vendored-sources.directory='$(CURDIR)/vendor'"

%:
\tdh $@

override_dh_auto_configure:
\tpython3 debian/cargo-checksums.py refresh

override_dh_auto_build:
\tcargo $(CARGO_FLAGS) build --release -p {name} -p {name}-cli {features}

override_dh_auto_test:
\tcargo $(CARGO_FLAGS) test --release -p {name}-stereo-window
\tcargo $(CARGO_FLAGS) test --release -p {name}-ui-egui --test {test}

override_dh_auto_install:
\tbash debian/stage.sh {name} {section} {'heif' if features else 'none'}

override_dh_auto_clean:
\trm -rf target dist debian/cargo-home

# Cargo.toml.orig is a checksum-covered member of a published crate, not a
# patch backup. Keep the complete vendor set through debhelper's cleanup.
override_dh_clean:
\tdh_clean -Xvendor/
''')
    (debian / 'rules').chmod(0o755)
    os.environ['DEBFULLNAME'] = 'Daniel Ramos (Capitain Jack)'
    os.environ['DEBEMAIL'] = 'Capitain_Jack@yahoo.com'
    prepare(root, version, HERE.parents[1])
    rules = (debian / 'rules').read_text()
    old = '\trm -rf .sparky-lc\n'
    if rules.count(old) != 1:
        raise ValueError('Review changed Lean Code recovery hook')
    (debian / 'rules').write_text(rules.replace(old, '\tpython3 debian/cargo-checksums.py restore\n' + old))
    # No local vendor path belongs in the published source snapshot.
    config = root / 'vendor-config.toml'
    if config.exists():
        config.write_text(config.read_text().replace(str(root / 'vendor'), 'vendor'))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('accepted_recipe', type=Path)
    args = parser.parse_args()
    main(args.source, args.accepted_recipe)
