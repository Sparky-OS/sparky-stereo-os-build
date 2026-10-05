#!/bin/bash
# Generates deb/vs/patches/vlc-stereo-side-by-side.patch (after make-source.sh and make-branding): VLC Stereo's own settings, names and window class
set -eux
cd /w/deb/src/vlc-3.0.24
export QUILT_PATCHES=debian/patches
quilt new vlc-stereo-side-by-side.patch
python3 - <<'PY'
import subprocess
def edit(path, fn):
    s = open(path, encoding='utf-8').read(); t = fn(s)
    assert s != t, path
    subprocess.check_call(['quilt', 'add', path]); open(path, 'w', encoding='utf-8').write(t)
# user directories: ~/.config/vlc-stereo, ~/.local/share/vlc-stereo, ~/.cache/vlc-stereo
edit('src/posix/dirs.c', lambda s: s.replace('"%s/vlc"', '"%s/vlc-stereo"').replace('"%s/%s/vlc"', '"%s/%s/vlc-stereo"'))
# the interface's own settings file, and its window class
edit('modules/gui/qt/qt.cpp', lambda s: s.replace('char vlc_name[] = "vlc";', 'char vlc_name[] = "vlc-stereo";').replace('QSettings::UserScope, "vlc", "vlc-qt-interface"', 'QSettings::UserScope, "vlc-stereo", "vlc-qt-interface"'))
edit('modules/gui/qt/components/sout/profile_selector.cpp', lambda s: s.replace('QSettings::UserScope, "vlc", "vlc-qt-interface"', 'QSettings::UserScope, "vlc-stereo", "vlc-qt-interface"'))
# the video window's class
edit('modules/video_output/xcb/window.c', lambda s: s.replace('XA_STRING, 8, 8, "vlc\\0Vlc");', 'XA_STRING, 8, 22, "vlc-stereo\\0Vlc-stereo");'))
# the session bus: MPRIS name and desktop entry
edit('modules/control/dbus/dbus.c', lambda s: s.replace('"org.mpris.MediaPlayer2.vlc"', '"org.mpris.MediaPlayer2.vlc-stereo"'))
edit('modules/control/dbus/dbus_root.c', lambda s: s.replace('const char* psz_ret = PACKAGE;', 'const char* psz_ret = "vlc-stereo";'))
# application id (Wayland app_id, PipeWire application id)
edit('src/libvlc.c', lambda s: s.replace('"app-id", "org.VideoLAN.VLC"', '"app-id", "vlc-stereo"'))
PY
quilt refresh
cp debian/patches/vlc-stereo-side-by-side.patch /w/deb/vs/patches/
