#!/bin/bash
# Generates deb/branding/vlc-stereo-name.patch: run after make-source.sh (the 3d patches pushed) inside vlc-deb-testing:1 as the user.
set -eux
cd /w/deb/src/vlc-3.0.24
export QUILT_PATCHES=debian/patches
quilt new vlc-stereo-name.patch
python3 - <<'PY'
import re, glob, subprocess
def edit(path, fn):
    s = open(path, encoding='utf-8').read(); t = fn(s)
    assert s != t, path
    subprocess.check_call(['quilt', 'add', path]); open(path, 'w', encoding='utf-8').write(t)
# 1. menu entries (vlc.desktop and the entries for discs, Solid actions)
def desk(s):
    s = re.sub(r'^(Name(?:\[[^\]]+\])?)=.*$', r'\1=VLC Stereo', s, flags=re.M) if False else s
    return s
for f in ['share/vlc.desktop.in']:
    edit(f, lambda s: re.sub(r'^(Name(?:\[[^\]]+\])?)=.*$', r'\1=VLC Stereo', s, flags=re.M))
for f in glob.glob('share/vlc-open*.desktop.in'):
    edit(f, lambda s: s.replace('VLC media player', 'VLC Stereo'))
for f in glob.glob('share/solid/vlc-open*.desktop'):
    edit(f, lambda s: s.replace('VLC media player', 'VLC Stereo'))
# 2. window title of the interface, tray, taskbar menu entries
edit('modules/gui/qt/main_interface.cpp', lambda s: s.replace('qtr( "VLC media player" )', 'qtr( "VLC Stereo" )'))
edit('modules/gui/qt/menus.cpp', lambda s: s.replace('qtr( "&Hide VLC media player in taskbar" )', 'qtr( "&Hide VLC Stereo in taskbar" )').replace('qtr( "Sho&w VLC media player" )', 'qtr( "Sho&w VLC Stereo" )'))
# 3. window title of the video window
edit('modules/video_output/xcb/window.c', lambda s: s.replace('vlc_pgettext ("ASCII", "VLC media player")', '"VLC Stereo"').replace('set_string (conn, window, utf8, net_wm_name, _("VLC media player"))', 'set_string (conn, window, utf8, net_wm_name, "VLC Stereo")'))
edit('modules/video_output/wayland/xdg-shell.c', lambda s: s.replace('_("VLC media player")', '"VLC Stereo"'))
edit('modules/video_output/wayland/shell.c', lambda s: s.replace('_("VLC media player")', '"VLC Stereo"'))
# 4. name the media player announces on the session bus (MPRIS)
edit('modules/control/dbus/dbus_root.c', lambda s: s.replace('_("VLC media player")', '"VLC Stereo"'))
# 5. About dialog: the title and a credit to VideoLAN and VLC before VideoLAN's own text, which stays
def about(s):
    s = s.replace('qtr( "VLC media player" ) + " </span></p></body></html>");', 'qtr( "VLC Stereo" ) + " </span></p></body></html>");')
    a = 'ui.MainBlabla->setText("<html><head/><body>" + translatedString + "</p></body> </html>");'
    b = 'ui.MainBlabla->setText("<html><head/><body><p>" + qtr( "VLC Stereo is a stereo edition of VLC media player by VideoLAN, for Sparky Stereo OS." ) + "</p>" + translatedString + "</p></body> </html>");'
    assert a in s
    return s.replace(a, b)
edit('modules/gui/qt/dialogs/help.cpp', about)
PY
quilt refresh
cp debian/patches/vlc-stereo-name.patch /w/deb/branding/
