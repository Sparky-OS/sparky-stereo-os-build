#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Add a reproducible source recipe to a disposable, patched Linux export.

The export must identify its pinned tag, applied patch hashes and flavour in
SOURCE.edition.json. This does not operate on a development checkout.
"""
import argparse
import email.utils
import importlib.util
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
sys.path.insert(0, str(HERE))
import upstream


def libc_dev_module():
    spec = importlib.util.spec_from_file_location('libc_dev', HERE / 'libc-dev.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main(root, recipe, counter, smoke, packaging_revision=None):
    root, recipe = root.resolve(), recipe.resolve()
    source = json.loads((root / 'SOURCE.edition.json').read_text())
    flavour = source['flavour']
    if (flavour not in ('base', 'v3', 'rt') or not re.fullmatch(r'[0-9]+', counter)
            or upstream.PINNED.get(source['tag']) != source['commit']
            or (root / '.git').exists() or (root / 'debian').exists()):
        raise ValueError('Expected a fresh, pinned Linux export and a new release counter')
    kernel_version, debian_upstream = upstream.versions(source['tag'])
    suffix = ('-rt' if flavour == 'rt' else '') + '-stereo3d' + counter
    if flavour == 'v3':
        suffix += '-v3'
    release = kernel_version + suffix
    version = debian_upstream + '-' + counter
    if packaging_revision is not None:
        if not re.fullmatch(r'[1-9][0-9]*', packaging_revision):
            raise ValueError('Expected a positive packaging revision')
        version += '.' + packaging_revision
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
    # The fields are Debian's, from linux-image-7.2.11+deb14-amd64 and linux-headers-7.2.11+deb14-amd64 (forky,
    # ORDER 222; the audit is in the lane report of ORDER 212c). Image: the maintainer scripts call linux-base's
    # tools (Pre-Depends, as Debian's), dracut is the first alternative of the initramfs generator as in Debian's
    # own package, and the Recommends, Suggests and Breaks are Debian's. Headers: the compiler the kernel was built
    # with is read from its configuration by stage.sh (${kernel:Compiler}); the toolchain is otherwise ours because
    # our headers carry the tools compiled in (Debian's linux-kbuild package is not needed).
    image_fields = (
        'Pre-Depends: linux-base (>= 4.17~)\n'
        'Depends: kmod, dracut | initramfs-tools (>= 0.120+deb8u2) | linux-initramfs-tool, ${misc:Depends}\n'
        'Recommends: apparmor\n'
        'Suggests: debian-kernel-handbook, firmware-linux-free, grub-pc | grub-efi-amd64 | extlinux\n'
        'Breaks: fwupdate (<< 12-7), initramfs-tools (<< 0.120+deb8u2), wireless-regdb (<< 2019.06.03-1~)\n')
    # The Breaks is ours (build 13): with CONFIG_CGROUP_DMEM=y, NVIDIA's open modules before the edition's
    # 615.71.09-2+stereo3d6 do not compile against Linux 7.3's dmem_cgroup_register_region(), and a DKMS build that
    # fails stops the headers' postinst; the Breaks makes APT take the fixed module source first.
    headers_fields = (
        'Depends: ${kernel:Compiler}, make, kmod, libelf1t64, libssl3t64, pahole | dwarves, libc6-dev, '
        'linux-base (>= 4.17~), ${misc:Depends}\n'
        'Breaks: nvidia-kernel-open-dkms-stereo3d (<< 615.71.09-2+stereo3d6~)\n')
    for kind, fields in (('image', image_fields), ('headers', headers_fields)):
        control += (f'Package: linux-{kind}-{release}\nArchitecture: amd64\n{fields}'
                    f'Description: Sparky Stereo Linux {kind}, version {release}\n'
                    ' Edition kernel built from the retained patched source.\n\n')
    if flavour == 'base':
        # userspace API headers of this tree: Debian's linux-libc-dev layout, from our source (kernel/lean/libc-dev.py)
        control += ('Package: linux-libc-dev\nSection: devel\nArchitecture: all\nMulti-Arch: foreign\n'
                    'Depends: ${misc:Depends}\n'
                    'Description: Linux support headers for userspace development\n'
                    ' This package provides userspace headers from the Linux kernel of Sparky Stereo OS,\n'
                    ' built from the same source as its kernel image: they hold the UAPI of the edition\'s\n'
                    ' patches (the HDMI 3D metadata of drm_mode.h). These files are going to be installed\n'
                    ' into /usr/include, and are used by the installed headers for GNU libc and other\n'
                    ' system libraries.\n\n')
        # Debian's linux-libc-dev-ARCH-cross set (ORDER 256), as src:linux builds it (debian/templates/libc-dev-cross.*):
        # one package per Debian architecture, links into linux-libc-dev in the sysroot layout cross compilers search,
        # Depends linux-libc-dev (= ${binary:Version}), the documentation directory a link to linux-libc-dev's
        # (dh_installdocs --link-doc, Debian Policy 12.3: same source, Depends) and Debian's lintian override.
        # dir_to_symlink turns the directory of an earlier package (cross-toolchain-base's, or the separately built
        # linux-stereo-libc-dev-cross ones) into that link; Debian's own entry names 6.18-1~exp1~, this version covers both.
        for debian_arch, (gnu_type, _kernel_arch) in sorted(libc_dev_module().CROSS.items()):
            package = f'linux-libc-dev-{debian_arch}-cross'
            control += (f'Package: {package}\nSection: devel\nArchitecture: all\nMulti-Arch: foreign\n'
                        'Depends: linux-libc-dev (= ${binary:Version}), ${misc:Depends}\n'
                        'Description: Linux support headers for userspace development (for cross-compiling)\n'
                        ' This package provides the userspace headers of the Linux kernel of Sparky Stereo OS\n'
                        f' in the layout cross compilers search, /usr/{gnu_type}/include, as links to the\n'
                        ' files of linux-libc-dev: a cross toolchain sees the UAPI of the edition\'s patches\n'
                        ' (the HDMI 3D metadata of drm_mode.h). These files are used by the installed\n'
                        ' headers for GNU libc and other system libraries.\n\n')
            (debian / f'{package}.lintian-overrides').write_text(
                f'# The -cross packages use the sysroot layout\n{package}: non-standard-dir-in-usr [usr/{gnu_type}]\n')
            (debian / f'{package}.maintscript').write_text(
                f'dir_to_symlink /usr/share/doc/{package} linux-libc-dev {version}+lc1~ {package}\n')
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
    shutil.copytree(HERE / 'maint', target / 'maint')
    shutil.copy2(HERE / 'libc-dev.py', target / 'libc-dev.py')
    # The recipe's test fixtures include binary files (group 38's EDID, tests/vkms-frame-sequential/dp-fs.bin): the
    # 3.0 (quilt) Debian tarball carries them only when debian/source/include-binaries lists them.
    binaries = sorted(path.relative_to(root).as_posix() for path in target.rglob('*')
                      if path.is_file() and not path.is_symlink() and b'\0' in path.read_bytes())
    if binaries:
        (debian / 'source/include-binaries').write_text(''.join(path + '\n' for path in binaries))
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
    if flavour == 'base':
        cross = ' '.join(f'linux-libc-dev-{arch}-cross' for arch in sorted(libc_dev_module().CROSS))
        with (debian / 'rules').open('a') as rules:
            rules.write('\n# The cross packages share linux-libc-dev\'s documentation, as Debian\'s (INSTALLDOCS_LINK_DOC).\n'
                        f'CROSS_PACKAGES = {cross}\n\n'
                        'override_dh_installdocs:\n'
                        '\tdh_installdocs $(addprefix -N,$(CROSS_PACKAGES))\n'
                        '\t$(if $(filter linux-libc-dev,$(shell dh_listpackages)),'
                        'dh_installdocs --link-doc=linux-libc-dev $(addprefix -p,$(CROSS_PACKAGES)))\n')
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
    parser.add_argument('--packaging-revision', help='Revise packaging without changing the kernel release/ABI')
    args = parser.parse_args()
    main(args.source, args.recipe, args.counter, args.smoke, args.packaging_revision)
