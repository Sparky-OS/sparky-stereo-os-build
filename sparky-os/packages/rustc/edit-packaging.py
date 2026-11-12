#!/usr/bin/env python3
# Sparky Stereo OS: the edition's changes to Debian's rustc packaging, applied to an unpacked Debian source.
# Created by Daniel Ramos (Capitain Jack) 2026/11/12
# Copyright 2026 under the GNU GPL3 License
# Usage: edit-packaging.py TREE VERSION STD_HASH SEED RECIPE_DIR
#   TREE: Debian's rustc source, unpacked; VERSION: the edition's version (Debian's plus +stereo3dN);
#   STD_HASH: the 16 hex digits of libstd-HASH.so, or "discover"; SEED: the compiler that builds it, for the changelog.
# Debian's packaging stays as Debian has it. Added: the runtime package for the standard library's shared object, the
# edition's maintainer fields and its changelog entry. Every replacement is checked to match exactly once, so a new
# Debian revision that moved a line stops here and names it.
import os
import re
import shutil
import sys
from pathlib import Path

tree, version, std_hash, seed, recipe = Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4], Path(sys.argv[5])
if not re.fullmatch(r'[0-9a-f]{16}|discover', std_hash):
    sys.exit(f'edit-packaging: STD_HASH must be 16 hex digits or "discover", not {std_hash!r}')
debian = tree / 'debian'
runtime = f'libstd-rust-{std_hash}'


def once(text, old, new, what):
    if text.count(old) != 1:
        sys.exit(f'edit-packaging: expected exactly one {what!r} in Debian\'s packaging, found {text.count(old)}: '
                 'Debian changed this part; read its new form and adapt this recipe')
    return text.replace(old, new)


changelog = (debian / 'changelog').read_text()
debian_version = re.match(r'rustc \(([^)]+)\) ', changelog).group(1)
if not version.startswith(debian_version + '+stereo3d'):
    sys.exit(f'edit-packaging: {version} is not Debian\'s {debian_version} plus +stereo3dN')
short = re.match(r'(\d+\.\d+)\.', debian_version).group(1)
libstd = f'libstd-rust-{short}'

# control: maintainer fields, the runtime package, libstd-rust-dev's dependency on it
control = (debian / 'control').read_text()
maintainer = next(line for line in control.splitlines() if line.startswith('Maintainer: ')) + '\n'
control = once(control, maintainer, 'Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>\nXSBC-Original-'
               + maintainer + 'Bugs: https://github.com/Sparky-OS/sparky-stereo-os/issues\n', 'Maintainer')
control = once(control, f' {libstd} (= ${{binary:Version}}),\nConflicts: rustup\nDescription: Rust standard libraries - development files\n',
               f' {libstd} (= ${{binary:Version}}),\n {runtime} (= ${{binary:Version}}),\nConflicts: rustup\n'
               'Description: Rust standard libraries - development files\n', 'libstd-rust-dev dependency')
stanza = f'''Package: {runtime}
Section: libs
Architecture: any
Multi-Arch: same
Pre-Depends: ${{misc:Pre-Depends}}
Depends: ${{shlibs:Depends}}, ${{misc:Depends}}
Description: Rust standard library - shared library for dynamically linked programs
 This package contains the Rust standard library as a shared object,
 libstd-{std_hash}.so, which programs built with -C prefer-dynamic and Rust
 dynamic libraries load when they start.
 .
 The library has no stable interface: a program loads only the library of
 the compiler that built it. The package is therefore named after the
 library's own name, and the libraries of two compilers install side by
 side.

'''
control = once(control, 'Package: libstd-rust-dev\n', stanza + 'Package: libstd-rust-dev\n', 'libstd-rust-dev stanza')
(debian / 'control').write_text(control)

# the files of the two library packages
install = debian / f'{libstd}.install'
if install.read_text() != 'usr/lib/${DEB_HOST_MULTIARCH}/\n':
    sys.exit(f'edit-packaging: {install.name} is not the one line this recipe replaces')
install.write_text('usr/lib/${DEB_HOST_MULTIARCH}/librustc_driver-*.so\n')
(debian / f'{runtime}.install').write_text(f'usr/lib/${{DEB_HOST_MULTIARCH}}/libstd-{std_hash}.so\n')
(debian / f'{runtime}.triggers').write_text('# normally added by dh_makeshlibs, which this package skips (see debian/rules)\n'
                                           'activate-noawait ldconfig\n')
(debian / f'{runtime}.lintian-overrides').write_text(
    '# the name follows Debian\'s libstd-rust-N.NN: "libstd" alone seemed too generic\n'
    f'{runtime} binary: package-name-doesnt-match-sonames\n'
    '# rustc names its dynamic libraries by a hash, without a version\n'
    f'{runtime} binary: shlib-without-versioned-soname\n'
    f'{runtime} binary: dev-pkg-without-shlib-symlink\n')
(debian / 'sparky-libstd-hash').write_text(std_hash + '\n')
shutil.copy2(recipe / 'sparky-libstd-runtime', debian / 'sparky-libstd-runtime')
os.chmod(debian / 'sparky-libstd-runtime', 0o755)

# rules: keep libstd's shared object, and give the runtime package its symbols file
rules = (debian / 'rules').read_text()
rules = once(rules, '\trm $(DEB_DESTDIR)/usr/lib/rustlib/$(DEB_HOST_RUST_TYPE)/lib/libstd-*.so\n',
             '\tdebian/sparky-libstd-runtime $(DEB_DESTDIR) $(DEB_HOST_MULTIARCH) $(DEB_HOST_RUST_TYPE)\n', 'rm of libstd-*.so')
rules = once(rules, '\tdh_makeshlibs -V -N $(LIBSTD_PKG)\n',
             '\tdh_makeshlibs -V -N $(LIBSTD_PKG) -N $(SPARKY_STD_PKG)\n'
             '\tif [ -d debian/$(SPARKY_STD_PKG) ]; then mkdir -p debian/$(SPARKY_STD_PKG)/DEBIAN && '
             'printf \'%s %s (= %s)\\n (regex)"^.*$$" 0\\n\' "libstd-$(SPARKY_STD_HASH).so" "$(SPARKY_STD_PKG)" "$(DEB_VERSION)" '
             '> debian/$(SPARKY_STD_PKG)/DEBIAN/symbols; fi\n', 'dh_makeshlibs call')
rules = once(rules, 'LIBSTD_PKG := libstd-rust-$(RUST_VERSION)\n',
             'LIBSTD_PKG := libstd-rust-$(RUST_VERSION)\n'
             'SPARKY_STD_HASH := $(shell cat debian/sparky-libstd-hash)\nSPARKY_STD_PKG := libstd-rust-$(SPARKY_STD_HASH)\n',
             'LIBSTD_PKG definition')
rules = once(rules, '\tdh_shlibdeps -- -x$(LIBSTD_PKG)\n', '\tdh_shlibdeps -- -x$(LIBSTD_PKG) -x$(SPARKY_STD_PKG)\n', 'dh_shlibdeps call')
rules = once(rules, '\t$(RM) -rf $(TEST_LOG) debian/config.toml debian/*.stamp\n',
             '\t$(RM) -rf $(TEST_LOG) debian/config.toml debian/*.stamp debian/sparky-libstd-hash.built\n', 'clean of stamps')
(debian / 'rules').write_text(rules)

# changelog: the edition's entry on top, dated by the recipe
entry = (recipe / ('changelog-' + version.rsplit('+', 1)[1] + '.txt')).read_text()
for key, value in (('@VERSION@', version), ('@DEBIAN_VERSION@', debian_version), ('@STD_HASH@', std_hash), ('@SEED@', seed)):
    entry = entry.replace(key, value)
if '@' in entry:
    sys.exit('edit-packaging: the changelog template has an unknown @KEY@')
(debian / 'changelog').write_text(entry.rstrip('\n') + '\n\n -- Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>  '
                                  + os.environ['SOURCE_DATE_RFC2822'] + '\n\n' + changelog)
print(f'edit-packaging: {debian_version} -> {version}, runtime package {runtime}')
