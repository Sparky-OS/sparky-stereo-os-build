#!/bin/bash
export HOME=/tmp/mh XDG_CURRENT_DESKTOP=KDE LC_ALL=C; mkdir -p $HOME/.config
cp /k/kde-mimeapps.list /usr/share/applications/kde-mimeapps.list    # as the Sparky KDE ISO ships it (package plasma-desktop)
q() { for t in video/mp4 video/x-matroska video/webm video/mp2t audio/mpeg; do printf "  %-18s gio: %-26s\n" $t "$(gio mime $t 2>/dev/null | grep -i '^Default application' | sed 's/.*: //')"; done; }
echo "installed: $(dpkg -l vlc vlc-stereo haruna 2>/dev/null | grep ^ii | awk '{print $2}' | tr '\n' ' ')"
echo "== before (KDE's own list, Haruna and Elisa)"; q
dpkg -i --force-depends /l/sparky-stereo-look_20261005.1~sparky9~0_all.deb >/dev/null 2>&1
echo "== with sparky-stereo-look 20261005.1 (/etc/xdg/kde-mimeapps.list, $(grep -c '=vlc-stereo' /etc/xdg/kde-mimeapps.list) video types)"; q
echo "== a user's own choice (~/.config/mimeapps.list: video/mp4=org.kde.haruna.desktop)"
printf '[Default Applications]\nvideo/mp4=org.kde.haruna.desktop\n' > $HOME/.config/mimeapps.list; q
rm $HOME/.config/mimeapps.list
xq() { for t in video/mp4 video/x-matroska video/webm video/mp2t audio/mpeg; do printf "  %-18s xdg-mime: %s\n" $t "$(env XDG_CURRENT_DESKTOP=KDE KDE_SESSION_VERSION=6 xdg-mime query default $t 2>&1 | tail -n 1)"; done; }
echo "== xdg-mime query default (XDG_CURRENT_DESKTOP=KDE KDE_SESSION_VERSION=6), edition defaults installed"; xq
printf '[Default Applications]\nvideo/mp4=org.kde.haruna.desktop\n' > $HOME/.config/mimeapps.list
echo "== xdg-mime, user's own choice for video/mp4"; xq; rm $HOME/.config/mimeapps.list
echo "== xdg-mime, same session without the edition's file"; rm -f /etc/xdg/kde-mimeapps.list; xq
echo "== both VLCs installed: $(ls /usr/share/applications/vlc.desktop /usr/share/applications/vlc-stereo.desktop | tr '\n' ' ')"
