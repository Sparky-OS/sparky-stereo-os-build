#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Prepare an accepted, exported browser tree for a fresh Lean Code build.

The compiler bundle is supplied separately and verified against retained hashes.
This recipe never treats the old browser executable as a native rebuild.
"""
import argparse
import email.utils
import json
import os
from pathlib import Path
import re
import shutil
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1]))
from lean.debian_prepare import prepare


def main(root, accepted, manifest):
    root, accepted = root.resolve(), accepted.resolve()
    origin = json.loads((root / 'SOURCE.edition.json').read_text())
    version = origin['version']
    if (version != '6.7.5-0+stereo3d5+lc1' or (root / 'debian').exists()
            or (root / 'obj-x86_64-pc-linux-gnu').exists()):
        raise ValueError('Expected the fresh accepted M5 export, without build objects')
    debian = root / 'debian'
    shutil.copytree(accepted / 'debian', debian)
    shutil.copy2(accepted / 'mozconfig', debian / 'mozconfig.accepted')
    shutil.copy2(debian / 'rules', debian / 'rules.accepted')
    shutil.copy2(manifest, debian / 'toolchain-manifest.json')
    for filename in ('build.sh', 'verify-toolchains.py', 'fetch-toolchains.py', 'toolchain-downloads.json',
                     'cargo-baseline.py', 'cargo-baseline.json'):
        shutil.copy2(HERE / filename, debian / filename)
    shutil.copy2(HERE.parent / 'artcraft-stereo/cargo-checksums.py', debian / 'cargo-checksums.py')
    (debian / 'source').mkdir(exist_ok=True)
    (debian / 'source/format').write_text('3.0 (quilt)\n')
    (debian / 'source/options').write_text(
        'extend-diff-ignore = (^|/)(obj-x86_64-pc-linux-gnu|\\.sparky-lc)(/|$)\n')
    changelog = debian / 'changelog'
    changelog.write_text(changelog.read_text()
                        .replace('@DEBVERSION@', version.removesuffix('+lc1'))
                        .replace('@VERSION@', '6.7.5')
                        .replace('@GECKO@', (root / 'config/milestone.txt').read_text().strip())
                        .replace('@DATE@', email.utils.formatdate(localtime=False)))
    control = debian / 'control'
    text = control.read_text()
    text = text.replace('Build-Depends: debhelper-compat (= 13),',
                        'Build-Depends: debhelper-compat (= 13), build-essential, '
                        'ca-certificates, curl, file, git, m4, patch, perl, python3-dev, '
                        'python3-venv, unzip, bzip2, xz-utils, zstd,')
    control.write_text(text)
    rules = (debian / 'rules').read_text()
    old = 'override_dh_auto_configure:\noverride_dh_auto_build:\noverride_dh_auto_test:\n'
    if rules.count(old) != 1:
        raise ValueError('Review the changed accepted Debian recipe')
    rules = rules.replace(old, '''override_dh_auto_configure:
	python3 debian/verify-toolchains.py "$(SPARKY_BROWSER_TOOLCHAIN_ROOT)" debian/toolchain-manifest.json
	python3 debian/cargo-checksums.py restore
	python3 debian/cargo-baseline.py apply
	python3 debian/cargo-checksums.py refresh --vendor-dir third_party/rust
	bash debian/build.sh configure

override_dh_auto_build:
	bash debian/build.sh build
	bash debian/build.sh package

override_dh_auto_test:
	obj-x86_64-pc-linux-gnu/dist/bin/sparky-stereo-browser --headless --version

override_dh_auto_clean:
	rm -rf obj-x86_64-pc-linux-gnu debian/mozbuild-state debian/cargo-home

override_dh_clean:
	dh_clean -Xthird_party/rust/
''')
    rules = rules.replace('cp -a $(PKG)/. $(INSTDIR)/',
                          'cp -a obj-x86_64-pc-linux-gnu/dist/$(PKG)/. $(INSTDIR)/')
    (debian / 'rules').write_text(rules)
    mozconfig = (accepted / 'mozconfig').read_text()
    mozconfig = mozconfig.replace('$HOME/.mozbuild', '$SPARKY_BROWSER_TOOLCHAIN_ROOT/.mozbuild')
    mozconfig = mozconfig.replace('ac_add_options --enable-bootstrap=-clang,-sysroot-wasm32-wasi,-sccache',
                                 'ac_add_options --disable-bootstrap\n'
                                 'ac_add_options --with-sysroot="$SPARKY_BROWSER_TOOLCHAIN_ROOT/.mozbuild/sysroot-x86_64-linux-gnu"\n'
                                 'export HOST_SYSROOT="$SPARKY_BROWSER_TOOLCHAIN_ROOT/.mozbuild/sysroot-x86_64-linux-gnu"')
    (debian / 'mozconfig').write_text(mozconfig)
    if not re.fullmatch(r'[0-9a-f]{40}', origin['browser_commit']):
        raise ValueError('Expected the exact accepted browser commit')
    (debian / 'browser-build.env').write_text(
        f'MOZ_BUILD_DATE={origin["build_date"]}\n'
        'MOZ_SOURCE_REPO=https://github.com/Sparky-OS/waterfox\n'
        f'MOZ_SOURCE_CHANGESET={origin["browser_commit"]}\n')
    preserve = []
    for pattern, reason in (
        ('*/test*/*', 'Test fixtures can contain intentionally malformed source and textual expectations'),
        ('testing/*', 'Test harness inputs and samples have additional textual consumers'),
        ('*/templates/*', 'Binding and source generators consume template syntax before a C/C++ compiler'),
        ('build/*', 'Build probes and code-generation fixtures require their exact authored input'),
    ):
        # Every declared pattern must match eligible C/C++ input in this export.
        from fnmatch import fnmatchcase
        from lean.lang_c import EXTS
        from lean.source_tree import EXCLUDED
        if any(p.is_file() and not p.is_symlink() and p.suffix.lower() in EXTS
               and not any(part in EXCLUDED or part.startswith('obj-')
                           for part in p.relative_to(root).parts)
               and fnmatchcase(p.relative_to(root).as_posix(), pattern)
               for p in root.rglob('*')):
            preserve.append((pattern, reason))
    os.environ['DEBFULLNAME'] = 'Daniel Ramos (Capitain Jack)'
    os.environ['DEBEMAIL'] = 'Capitain_Jack@yahoo.com'
    prepare(root, version, HERE.parents[1], preserve_sources=preserve)
    # This is the generated application tree copied by dh_auto_install, not a
    # header installation. Its empty removed-files list must not be mistaken
    # for unrelated C headers that also project to zero bytes.
    from lean.source_tree import PAYLOAD_SOURCE_PLAN
    (root / PAYLOAD_SOURCE_PLAN).write_text(json.dumps({
        '/usr/lib/sparky-stereo-browser':
            'obj-x86_64-pc-linux-gnu/dist/sparky-stereo-browser',
    }, indent=2) + '\n')
    path = debian / 'rules'
    text = path.read_text()
    hook = '\trm -rf .sparky-lc\n'
    if text.count(hook) != 1:
        raise ValueError('Review the changed recovery hook')
    path.write_text(text.replace(hook, '\tpython3 debian/cargo-checksums.py restore\n'
                                     '\tpython3 debian/cargo-baseline.py restore\n' + hook))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('accepted_recipe', type=Path)
    parser.add_argument('toolchain_manifest', type=Path)
    args = parser.parse_args()
    main(args.source, args.accepted_recipe, args.toolchain_manifest)
