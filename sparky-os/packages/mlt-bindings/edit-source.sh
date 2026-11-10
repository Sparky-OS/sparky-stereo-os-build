#!/bin/bash
# Created by Daniel Ramos (Capitain Jack) 2026/11/10
# Copyright 2026 under the GNU GPL3 License
# ORDER 458b: MLT's Perl and Ruby bindings in our MLT. The edit run on the plain source of the published mlt before the +stereo3d6 source is
# packed (transition-rebuilds/prepare-lc-source.sh runs it in the unpacked tree). Upstream's swig directory builds both with SWIG_PERL and
# SWIG_RUBY (src/swig/perl and src/swig/ruby of MLT 7.40.0); Debian's mlt packages only python3-mlt; deb-multimedia's mlt7-dmo builds
# them as libmlt7-perl and libmlt7-ruby3.3 against its own libmlt-7-7, which the edition's pins keep out (ORDER 458).
# Names that clash with nobody: libmlt-perl and libmlt-ruby (Debian's forky and deb-multimedia's forky have neither). Ours Conflicts with and
# Replaces deb-multimedia's two, which ship the same module files, so apt swaps them for ours and dpkg never meets two owners of one file.
set -euo pipefail
python3 - <<'PY'
import re
from pathlib import Path
c = Path('debian/control')
t = c.read_text()
assert 'swig' in t and 'libperl-dev' not in t and 'Package: libmlt-perl' not in t
t = t.replace(' swig\n', ' swig,\n libperl-dev,\n ruby,\n ruby-dev\n', 1) if re.search(r' swig\n', t) else t.replace(',\n swig', ',\n swig,\n libperl-dev,\n ruby,\n ruby-dev', 1)
assert 'libperl-dev' in t
body = ' MLT is an open source multimedia framework, designed and developed for\n television broadcasting. It provides a toolkit for broadcasters, video\n editors, media players, transcoders, web streamers and many more types of\n applications. The functionality of the system is provided via an assortment\n of ready to use tools, xml authoring components, and an extendible plug-in\n based API.\n .\n'
t = t.rstrip('\n') + '''

Package: libmlt-perl
Architecture: any
Section: perl
Depends: ${perl:Depends},
 ${shlibs:Depends},
 ${misc:Depends},
 libmlt7 (= ${binary:Version}),
 libmlt++7 (= ${binary:Version})
Conflicts: libmlt7-perl
Replaces: libmlt7-perl
Description: multimedia framework (Perl bindings)
''' + body + ''' This package contains the Perl bindings for the mlt package: use mlt;
 They load the edition's libmlt7, never another archive's MLT.

Package: libmlt-ruby
Architecture: any
Section: ruby
Depends: ruby3.3,
 ${shlibs:Depends},
 ${misc:Depends},
 libmlt7 (= ${binary:Version}),
 libmlt++7 (= ${binary:Version})
Conflicts: libmlt7-ruby3.3
Replaces: libmlt7-ruby3.3
Description: multimedia framework (Ruby bindings)
''' + body + ''' This package contains the Ruby bindings for the mlt package: require 'mlt'
 They load the edition's libmlt7, never another archive's MLT.
'''
c.write_text(t)
r = Path('debian/rules')
s = r.read_text()
s = s.replace('\t-DSWIG_PYTHON=ON \\\n', '\t-DSWIG_PYTHON=ON \\\n\t-DSWIG_PERL=ON \\\n\t-DSWIG_RUBY=ON \\\n', 1)
assert 'SWIG_RUBY' in s
s = s.replace('override_dh_install:\n', '''# upstream installs mlt.so in vendor_ruby, which is not on Ruby's load path: it goes to the vendor architecture directory of the Ruby we depend on
RUBY_VENDORARCH := $(shell ruby -rrbconfig -e 'puts RbConfig::CONFIG["vendorarchdir"]')

override_dh_install:
	mkdir -p debian/tmp$(RUBY_VENDORARCH)
	mv debian/tmp/usr/lib/$(DEB_HOST_MULTIARCH)/ruby/vendor_ruby/mlt.so debian/tmp$(RUBY_VENDORARCH)/mlt.so
''', 1)
assert 'RUBY_VENDORARCH' in s
r.write_text(s)
Path('debian/libmlt-perl.install').write_text('usr/lib/*/perl5\n')
Path('debian/libmlt-ruby.install').write_text('usr/lib/*/ruby/vendor_ruby/*/mlt.so\n')
PY
grep -n 'DEB_HOST_MULTIARCH' debian/rules | head -3 || true
grep -q '^include /usr/share/dpkg/architecture.mk' debian/rules || sed -i '0,/^export DEB_BUILD_MAINT_OPTIONS/s//include \/usr\/share\/dpkg\/architecture.mk\nexport DEB_BUILD_MAINT_OPTIONS/' debian/rules
sed -n 1,30p debian/rules
