#!/usr/bin/env python3
# Turns Debian's vlc debian/ directory into the packaging of VLC Stereo (vlc-stereo, vlc-stereo-plugin-pipewire) in the current source tree.
import re, os, glob, shutil, sys
PK = os.environ['PK']      # this folder
PW = os.environ['PW']      # the unpacked, patched source of Debian's vlc-plugin-pipewire
ctl = open('debian/control').read()
m = re.search(r'^Build-Depends:\n((?: .*\n)+)', ctl, re.M)
bd = m.group(1)
if 'libpipewire-0.3-dev' not in bd: bd += ' libpipewire-0.3-dev (>= 0.3.50),\n pkgconf,\n'
if 'libstereo-declare-dev' not in bd: bd += ' libstereo-declare-dev,\n'
if 'libstereo-policy-dev' not in bd: bd += ' libstereo-policy-dev (>= 1.5.0),\n'
new = f'''Source: vlc
Section: video
Priority: optional
Maintainer: Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
XSBC-Original-Maintainer: Debian Multimedia Maintainers <debian-multimedia@lists.debian.org>
Build-Depends:
{bd}Standards-Version: 4.7.2
Rules-Requires-Root: no
Homepage: https://sparkylinux.org

Package: vlc-stereo
Architecture: any
Depends: ${{shlibs:Depends}}, ${{misc:Depends}}, qtwayland5
Recommends: vlc-stereo-plugin-pipewire (= ${{binary:Version}}), fonts-freefont-ttf
Provides: vlc
Description: stereo edition of the VLC multimedia player and streamer
 VLC Stereo is a stereo edition of VLC media player by VideoLAN, for Sparky
 Stereo OS. It shows 3D videos in both eyes and declares them to the
 compositor, and it sends floating point samples at 48 kHz to the audio
 hardware that offers them.
 .
 It is installed beside the VLC of the distribution and shares no file with
 it: its program is vlc-stereo, its libraries and plugins are in a private
 directory, and its settings are in ~/.config/vlc-stereo.
 .
 VLC is the VideoLAN project's media player. It plays MPEG, MPEG-2, MPEG-4,
 DivX, MOV, WMV, QuickTime, WebM, FLAC, MP3, Ogg/Vorbis files, DVDs, VCDs,
 podcasts, and multimedia streams from various network sources.

Package: vlc-stereo-plugin-pipewire
Architecture: any
Depends: vlc-stereo (= ${{binary:Version}}), ${{shlibs:Depends}}, ${{misc:Depends}}
Description: PipeWire audio output for VLC Stereo
 The PipeWire audio output plugin for VLC, by Rémi Denis-Courmont (the
 vlc-plugin-pipewire source of Debian), copied for VLC Stereo and installed in
 its plugin directory. It sends floating point samples and resamples them
 once, with the player's own resampler at its highest quality, to the rate
 that the graph runs at, or does not resample when the rates agree.
'''
open('debian/control', 'w').write(new)

r = open('debian/rules').read()
r = r.replace('\t--docdir=/usr/share/doc/vlc \\\n', '''\t--docdir=/usr/share/doc/vlc-stereo \\
\t--libdir=/usr/lib/$(DEB_HOST_MULTIARCH)/vlc-stereo \\
\t--datarootdir=/usr/share/vlc-stereo \\
\t--datadir=/usr/share/vlc-stereo \\
\t--includedir=/usr/include/vlc-stereo \\
\t--mandir=/usr/share/vlc-stereo/man \\
\t--program-suffix=-stereo \\
''')
r = r.replace('\t--with-kde-solid=/usr/share/solid/actions/ \\\n', '')
i = r.index('export DEB_BUILD_MAINT_OPTIONS')
r = r[:i] + '''# every object finds the libraries of VLC Stereo before any other: they are in a private directory
DEB_LDFLAGS_MAINT_APPEND += -Wl,-rpath,/usr/lib/$(DEB_HOST_MULTIARCH)/vlc-stereo -Wl,--disable-new-dtags

''' + r[i:]
j = r.index('%:\n\tdh $@')
r = r[:j] + '''include /usr/share/dpkg/buildflags.mk

PRIV = /usr/lib/$(DEB_HOST_MULTIARCH)/vlc-stereo
D = debian/vlc-stereo
P = debian/vlc-stereo-plugin-pipewire

%:
	dh $@

override_dh_auto_configure:
	dh_auto_configure -- $(confflags)

override_dh_auto_test:

# the catalogues of the translations our patches change, made again (the release tarball has older ones)
execute_after_dh_auto_build:
	$(MAKE) -C po update-gmo

override_dh_auto_install:
	dh_auto_install --destdir=$(D)
	# the PipeWire output: the plugin of Debian's vlc-plugin-pipewire, copied and built against this VLC
	VS_PKGCONFIG_PATH=$(CURDIR)/$(D)$(PRIV)/pkgconfig VS_SYSROOT=$(CURDIR)/$(D) \\
	  $(MAKE) -C debian/pw PKG_CONFIG=$(CURDIR)/debian/pw/pkg-config-wrap CC="$(CC)" CFLAGS="$(CFLAGS)" CPPFLAGS="$(CPPFLAGS)" LDFLAGS="$(LDFLAGS)"
	install -D -m 0755 debian/pw/libaout_pipewire_plugin.so $(P)$(PRIV)/vlc/plugins/audio_output/libaout_pipewire_plugin.so

execute_after_dh_auto_install:
	find $(D) -name '*.la' -delete
	find $(D) -name plugins.dat -delete
	rm -rf $(D)/usr/include $(D)$(PRIV)/pkgconfig $(D)/usr/share/vlc-stereo/man
	rm -rf $(D)/usr/share/vlc-stereo/appdata $(D)/usr/share/vlc-stereo/metainfo
	# menu entries, icons: VLC Stereo's own names, nothing of the distribution's VLC
	mkdir -p $(D)/usr/share/applications
	for f in $(D)/usr/share/vlc-stereo/applications/*.desktop; do \\
	  n=$$(basename $$f | sed 's/^vlc/vlc-stereo/'); \\
	  sed -e 's|^Exec=/usr/bin/vlc |Exec=/usr/bin/vlc-stereo |' -e 's/^Exec=vlc /Exec=vlc-stereo /' \\
	      -e 's|^TryExec=/usr/bin/vlc$$|TryExec=/usr/bin/vlc-stereo|' -e 's/^TryExec=vlc$$/TryExec=vlc-stereo/' -e 's/^Icon=vlc$$/Icon=vlc-stereo/' \\
	      -e '/^X-KDE-Protocols/d' $$f > $(D)/usr/share/applications/$$n; \\
	done
	rm -rf $(D)/usr/share/vlc-stereo/applications
	echo 'StartupWMClass=vlc-stereo' >> $(D)/usr/share/applications/vlc-stereo.desktop
	# the current names of AVI and WAVE (shared-mime-info), and MPEG-TS files named .ts, which the glob gives the type of
	# Qt Linguist files, as other players list them
	sed -i '/^MimeType=/s|$$|video/vnd.avi;audio/vnd.wave;text/vnd.trolltech.linguist;|' $(D)/usr/share/applications/vlc-stereo.desktop
	for f in $$(cd $(D)/usr/share/vlc-stereo/icons && find . -name 'vlc*.*' -type f); do \\
	  d=$$(dirname $$f); mkdir -p $(D)/usr/share/icons/$$d; \\
	  cp $(D)/usr/share/vlc-stereo/icons/$$f $(D)/usr/share/icons/$$d/$$(basename $$f | sed 's/^vlc/vlc-stereo/'); \\
	done
	rm -rf $(D)/usr/share/vlc-stereo/icons
	rm -rf $(D)/usr/share/vlc-stereo/vlc/skins2/fonts/*.ttf $(D)$(PRIV)/vlc/libcompat.a $(D)/usr/share/doc/vlc-stereo/libvlc

override_dh_installchangelogs:
	dh_installchangelogs NEWS

override_dh_installdocs:
	dh_installdocs -pvlc-stereo
	dh_installdocs -pvlc-stereo-plugin-pipewire debian/pw/README debian/pw/COPYING

override_dh_makeshlibs:
	dh_makeshlibs -n

override_dh_shlibdeps:
	dh_shlibdeps -- -l$(CURDIR)/$(D)$(PRIV) -l$(CURDIR)/$(D)$(PRIV)/vlc

override_dh_strip:
	dh_strip --no-automatic-dbgsym

execute_before_dh_installdeb:
	sed -i 's/@MULTIARCH@/$(DEB_HOST_MULTIARCH)/g' debian/vlc-stereo.postinst debian/vlc-stereo.postrm
	echo 'interest-noawait /usr/lib/$(DEB_HOST_MULTIARCH)/vlc-stereo/vlc/plugins' > debian/vlc-stereo.triggers

override_dh_gencontrol:
	dh_gencontrol
'''
open('debian/rules', 'w').write(r)

# drop Debian's packaging files of the packages that do not exist here
keep = {'changelog', 'control', 'copyright', 'rules', 'patches', 'source', 'upstream', 'watch', 'gbp.conf'}
for f in os.listdir('debian'):
    if f not in keep:
        p = os.path.join('debian', f)
        shutil.rmtree(p) if os.path.isdir(p) else os.remove(p)
# the plugin copy
shutil.copytree(PW, 'debian/pw')
shutil.copy(PK + '/files/vlc-stereo-plugin-pipewire.copyright', 'debian/vlc-stereo-plugin-pipewire.copyright')
shutil.copy(PK + '/files/pkg-config-wrap', 'debian/pw/pkg-config-wrap'); os.chmod('debian/pw/pkg-config-wrap', 0o755)
for src, dst in (('vlc-stereo.postinst', 'debian/vlc-stereo.postinst'), ('vlc-stereo.postrm', 'debian/vlc-stereo.postrm')):
    shutil.copy(PK + '/files/' + src, dst)
