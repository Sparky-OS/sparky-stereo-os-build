#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Add a reproducible source recipe to a disposable, patched Linux export.

The export must identify its pinned tag, applied patch hashes and flavour in
SOURCE.edition.json. This does not operate on a development checkout.
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
sys.path.insert(0, str(HERE.parents[1] / 'sparky-os'))
from lean.debian_prepare import prepare


def main(root, recipe, counter, smoke):
    root, recipe = root.resolve(), recipe.resolve()
    source = json.loads((root / 'SOURCE.edition.json').read_text())
    flavour = source['flavour']
    if (flavour not in ('base', 'v3', 'rt') or not re.fullmatch(r'[0-9]+', counter)
            or source['tag'] != 'v7.3-rc6'
            or source['commit'] != 'a90ee4305c4a5df72c11b31dacfdc76e00fcf78a'
            or (root / '.git').exists() or (root / 'debian').exists()):
        raise ValueError('Expected a fresh, pinned Linux export and a new release counter')
    suffix = ('-rt' if flavour == 'rt' else '') + '-stereo3d' + counter
    if flavour == 'v3':
        suffix += '-v3'
    release = '7.3.0-rc6' + suffix
    version = '7.3.0~rc6-' + counter
    name = 'linux-stereo-' + flavour
    maintainer = 'Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>'
    debian = root / 'debian'
    (debian / 'source').mkdir(parents=True)
    (debian / 'source/format').write_text('3.0 (quilt)\n')
    (debian / 'source/options').write_text(
        'extend-diff-ignore = (^|/)(build|\\.sparky-lc)(/|$)|\\.(deb|buildinfo|changes)$\n')
    control = (
        f'Source: {name}\nSection: kernel\nPriority: optional\nMaintainer: {maintainer}\n'
        'Build-Depends: debhelper-compat (= 13), build-essential, bc, bison, flex, '
        'libssl-dev, libelf-dev, libdw-dev, dwarves, cpio, kmod, rsync, python3, '
        'xz-utils, zstd, rustc, rust-src, bindgen, libclang-dev, sbsigntool\n'
        'Standards-Version: 4.7.4\nRules-Requires-Root: no\nHomepage: https://sparkylinux.org\n\n')
    for kind, depends in (
        ('image', 'kmod, initramfs-tools (>= 0.120+deb8u2) | linux-initramfs-tool'),
        ('headers', 'gcc, make, kmod, libelf1t64, libssl3t64, dwarves, libc6-dev'),
    ):
        control += (f'Package: linux-{kind}-{release}\nArchitecture: amd64\n'
                    f'Depends: {depends}, ${{misc:Depends}}\n'
                    f'Description: Sparky Stereo Linux {kind}, version {release}\n'
                    ' Edition kernel built from the retained patched source.\n\n')
    (debian / 'control').write_text(control)
    (debian / 'changelog').write_text(
        f'{name} ({version}) unstable; urgency=medium\n\n'
        '  * Retain the accepted kernel source and configuration for Lean Code migration.\n\n'
        f' -- {maintainer}  {email.utils.formatdate(localtime=False)}\n')
    shutil.copy2(root / 'COPYING', debian / 'copyright')
    target = debian / 'kernel-recipe'
    target.mkdir()
    for directory in ['config', 'tests']:
        shutil.copytree(recipe / directory, target / directory)
    for filename in ['configure.sh', 'headers-postinst.sh']:
        shutil.copy2(recipe / filename, target / filename)
    for filename in ['build.sh', 'stage.sh', 'check-module-signature.py', 'check-source-consumers.py']:
        shutil.copy2(HERE / filename, debian / filename)
    subprocess.run([sys.executable, str(debian / 'check-source-consumers.py'),
                    'record', str(root)], check=True)
    (debian / 'sparky-lean-payload-sources.json').write_text(
        json.dumps({f'/usr/src/linux-headers-{release}': '.'}, indent=2) + '\n')
    timestamp = int(source['timestamp'])
    (debian / 'kernel-build.env').write_text(
        f'FLAVOUR={flavour}\nRELEASE={release}\nLOCALVERSION={suffix}\n'
        f'PACKAGE_VERSION={version}+lc1\nUPSTREAM_TIMESTAMP={timestamp}\nSMOKE={int(smoke)}\n')
    (debian / 'rules').write_text('''#!/usr/bin/make -f
%:
\tdh $@

override_dh_auto_configure:
\tpython3 debian/check-source-consumers.py check .

override_dh_auto_build:
\tbash debian/build.sh

override_dh_auto_test:
\ttest -s debian/built.config

override_dh_auto_install:
\tbash debian/stage.sh

# Kbuild already processed and signed modules and generated BTF. Generic
# stripping, dwz and ELF dependency scans do not apply to these kernel objects.
override_dh_strip:
override_dh_dwz:
override_dh_shlibdeps:
override_dh_makeshlibs:

override_dh_auto_clean:
\trm -rf build
\trm -f linux-*.deb linux-*.buildinfo linux-*.changes debian/built.config
''')
    (debian / 'rules').chmod(0o755)
    preserve = [
        ('tools/*', 'Tools including objtool have separate build rules and textual consumers; their source projection needs separate qualification'),
        ('Documentation/*', 'Documentation sources and examples belong to their own textual consumers'),
        ('include/uapi/*', 'headers_install exports these userspace API inputs with a textual filter; retain its exact input'),
        ('arch/*/include/uapi/*', 'Architecture userspace headers are input to headers_install textual processing'),
        ('fs/smb/client/nterr.h', 'gen_smb1_mapping reads NT status to DOS error mappings from trailing comments'),
        ('fs/smb/client/smberr.h', 'gen_smb1_mapping reads error-class section comments and trailing POSIX error mappings'),
        ('fs/smb/common/smb2status.h', 'gen_smb2_mapping reads POSIX error mappings from trailing comments'),
        ('include/linux/oid_registry.h', 'build_OID_registry reads cryptographic OID values from trailing comments'),
        ('arch/x86/include/asm/cpufeatures.h', 'mkcapflags.sh reads CPU capability and bug names from quoted comments'),
        ('arch/x86/include/asm/vmxfeatures.h', 'mkcapflags.sh reads VMX capability names from quoted comments'),
    ]
    for path in sorted((root / 'arch').iterdir()):
        if path.is_dir() and path.name != 'x86':
            preserve.append((f'arch/{path.name}/*',
                             'Non-x86 architecture source is not compiled by this x86 kernel; target-specific qualification is separate'))
    for directory in ('arch/x86', 'include'):
        for path in sorted((root / directory).rglob('*.h')):
            if re.search(rb'^\s*\.macro\b', path.read_bytes(), re.M):
                preserve.append((path.relative_to(root).as_posix(),
                                 'Header contains assembly-language macros; the C-only checker cannot qualify its assembler consumer'))
    os.environ['DEBFULLNAME'] = 'Daniel Ramos (Capitain Jack)'
    os.environ['DEBEMAIL'] = 'Capitain_Jack@yahoo.com'
    prepare(root, version + '+lc1', HERE.parents[1] / 'sparky-os', preserve_sources=preserve)
    print(name, version + '+lc1', release)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('recipe', type=Path)
    parser.add_argument('--counter', required=True)
    parser.add_argument('--smoke', action='store_true')
    args = parser.parse_args()
    main(args.source, args.recipe, args.counter, args.smoke)
