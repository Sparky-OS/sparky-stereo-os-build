#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Write the source package linux-stereo-libc-dev-cross: Debian's 30 linux-libc-dev-ARCH-cross packages for an
already published linux-libc-dev of ours, until the kernel source builds them itself (ORDER 256).

    prepare.py OUT-DIR --libc-dev-version VERSION --counter N

Debian's linux source builds linux-libc-dev-ARCH-cross next to linux-libc-dev, from the same headers and at the
same version (debian/templates/libc-dev-cross.control.j2: "Depends: linux-libc-dev (= ${binary:Version})"), and
the cross toolchains need them (libc6-dev-armhf-cross Depends linux-libc-dev-armhf-cross). Debian's packages of
that name depend on Debian's linux-libc-dev at Debian's version, so they cannot be installed beside ours. The
kernel recipe makes them from build 14 on (kernel/lean/libc-dev.py, prepare.py); for a kernel build already
published, this source makes the same links from the linux-libc-dev installed at build time, the way
cross-toolchain-base made these packages before Debian's kernel team took them over: a separately versioned
source whose binaries carry the headers' version with "crossN" (cross-toolchain-base 80 built
linux-libc-dev-armhf-cross 6.18.9-1cross1).

- Build-Depends linux-libc-dev (= VERSION) and the binaries Depend on exactly that version: the links point into
  its files, so another linux-libc-dev must not satisfy them.
- Binary version: VERSION without its "+lc1", then "cross" and this source's version (N, "N+lc1" once Lean Code
  has prepared it): 7.3.0-13+lc1 with N 1 gives 7.3.0-13cross1+lc1, above Debian's 7.2.x and below the kernel's
  next build (7.3.0-14+lc1), whose own packages of these names replace them.
- /usr/share/doc/PACKAGE is a directory with its own copyright and changelog, not Debian's link to linux-libc-dev:
  Debian Policy 12.3 allows that link only when "the two packages both come from the same source". Upgrading from
  Debian's packages, where it is that link, dpkg-maintscript-helper symlink_to_dir turns it into a directory.

The tree is then prepared by the Lean Code toolkit (sparky-os/lean/debian_prepare.py), and dpkg-source -b
retains it as a native source package.
"""
import argparse
import email.utils
import importlib.util
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
KIT = HERE.parents[1]
LIBC_DEV = KIT / 'kernel/lean/libc-dev.py'
MAINTAINER = 'Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>'
NAME = 'linux-stereo-libc-dev-cross'


def load_libc_dev():
    spec = importlib.util.spec_from_file_location('libc_dev', LIBC_DEV)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main(out, libc_dev_version, counter):
    if not re.fullmatch(r'[0-9][0-9a-z.~]*-[0-9][0-9a-z.~]*\+lc1', libc_dev_version):
        raise SystemExit('Expected the version of a published linux-libc-dev of ours, such as 7.3.0-13+lc1')
    if not re.fullmatch(r'[1-9][0-9]*', counter):
        raise SystemExit('Expected a positive counter')
    libc_dev = load_libc_dev()
    root = out.resolve() / NAME
    if root.exists():
        raise SystemExit(f'{root} exists; the source tree must be new')
    prefix = libc_dev_version[:-len('+lc1')] + 'cross'
    debian = root / 'debian'
    (debian / 'source').mkdir(parents=True)
    (debian / 'source/format').write_text('3.0 (native)\n')
    control = (
        f'Source: {NAME}\nSection: devel\nPriority: optional\nMaintainer: {MAINTAINER}\n'
        f'Build-Depends: debhelper-compat (= 13), python3, linux-libc-dev (= {libc_dev_version})\n'
        'Standards-Version: 4.7.4\nRules-Requires-Root: no\nHomepage: https://sparkylinux.org\n')
    for debian_arch, (gnu_type, _kernel_arch) in sorted(libc_dev.CROSS.items()):
        package = libc_dev.cross_package(debian_arch)
        control += (
            f'\nPackage: {package}\nSection: devel\nArchitecture: all\nMulti-Arch: foreign\n'
            f'Depends: linux-libc-dev (= {libc_dev_version}), ${{misc:Depends}}\n'
            'Description: Linux support headers for userspace development (for cross-compiling)\n'
            ' This package provides the userspace headers of the Linux kernel of Sparky Stereo OS\n'
            f' in the layout cross compilers search, /usr/{gnu_type}/include, as links to the\n'
            ' files of linux-libc-dev: a cross toolchain sees the UAPI of the edition\'s patches\n'
            ' (the HDMI 3D metadata of drm_mode.h). These files are used by the installed\n'
            ' headers for GNU libc and other system libraries.\n')
        # Debian's override (debian/templates/libc-dev-cross.lintian-overrides.j2)
        (debian / f'{package}.lintian-overrides').write_text(
            f'# The -cross packages use the sysroot layout\n{package}: non-standard-dir-in-usr [usr/{gnu_type}]\n')
        (debian / f'{package}.maintscript').write_text(
            f'symlink_to_dir /usr/share/doc/{package} linux-libc-dev {prefix}{counter}~ {package}\n')
    (debian / 'control').write_text(control)
    (debian / 'changelog').write_text(
        f'{NAME} ({counter}) unstable; urgency=medium\n\n'
        f'  * Debian\'s linux-libc-dev-ARCH-cross packages, every architecture Debian builds them\n'
        f'    for, as links into linux-libc-dev {libc_dev_version}, so that the cross toolchains\n'
        '    install beside the edition\'s userspace headers.\n\n'
        f' -- {MAINTAINER}  {email.utils.formatdate(localtime=False)}\n')
    (debian / 'copyright').write_text(
        'Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/\n'
        f'Upstream-Name: {NAME}\n'
        'Comment: These packages hold only symbolic links into the files of linux-libc-dev\n'
        ' (source linux-stereo-base), the userspace API headers of the edition\'s kernel;\n'
        ' the copyright of those headers is in /usr/share/doc/linux-libc-dev/copyright.\n\n'
        'Files: *\n'
        f'Copyright: 2026 {MAINTAINER}\n'
        'License: GPL-2\n'
        ' On Debian systems the full text of the GNU General Public License version 2\n'
        ' is in /usr/share/common-licenses/GPL-2.\n')
    shutil.copy2(LIBC_DEV, debian / 'libc-dev.py')
    # The binary version is the headers' version with "cross" and this source's version: the source version
    # carries Lean Code's +lc1 once prepared, so the binaries carry it too.
    (debian / 'rules').write_text(f'''#!/usr/bin/make -f
LIBC_DEV_VERSION = {libc_dev_version}
CROSS_VERSION = {prefix}$(shell dpkg-parsechangelog -S Version)

%:
\tdh $@

override_dh_auto_build:
\ttest "$$(dpkg-query -W -f '$${{Version}}' linux-libc-dev)" = "$(LIBC_DEV_VERSION)"
\tpython3 debian/libc-dev.py --cross-from-installed debian/cross-stage

override_dh_auto_install:
\tset -e; for package in $$(dh_listpackages); do mkdir -p debian/$$package; cp -a debian/cross-stage/$$package/. debian/$$package/; done

override_dh_gencontrol:
\tdh_gencontrol -- -v$(CROSS_VERSION)

override_dh_auto_clean:
\trm -rf debian/cross-stage
''')
    (debian / 'rules').chmod(0o755)
    os.environ['DEBFULLNAME'] = 'Daniel Ramos (Capitain Jack)'
    os.environ['DEBEMAIL'] = 'Capitain_Jack@yahoo.com'
    sys.path.insert(0, str(KIT / 'sparky-os'))
    from lean.debian_prepare import prepare
    prepare(root, counter + '+lc1', KIT / 'sparky-os')
    subprocess.run(['dpkg-source', '-b', root.name], cwd=root.parent, check=True)
    print(NAME, counter + '+lc1', 'binaries', prefix + counter + '+lc1', 'for linux-libc-dev', libc_dev_version)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('out', type=Path)
    parser.add_argument('--libc-dev-version', required=True)
    parser.add_argument('--counter', required=True)
    args = parser.parse_args()
    main(args.out, args.libc_dev_version, args.counter)
