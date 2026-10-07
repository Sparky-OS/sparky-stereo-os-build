export DEBIAN_FRONTEND=noninteractive
apt-get -y update >/dev/null 2>&1; apt-get -y install ca-certificates >/dev/null 2>&1
echo 'deb [trusted=yes] file:/repo ./' > /etc/apt/sources.list.d/zrepo.list
cp /pin /etc/apt/preferences.d/sparky-stereo
apt-get -y update 2>&1 | tail -1
apt-cache policy libqt6gui6 | sed -n 1,3p; apt-cache policy libqt6gui6 | grep -E "^ +[0-9]+ (file|http)" 
for t in kde-plasma-desktop krita kalgebra "kubrick bino" "qt6-base-dev qt6-base-private-dev qt6-base-examples qt6-base-doc-html qt6-gtk-platformtheme qt6-xdgdesktopportal-platformtheme"; do
  apt-get -s install --no-install-recommends "$@" $t > /tmp/s.out 2>&1; rc=$?
  echo "== $t : rc=$rc, $(grep -c '^Inst' /tmp/s.out) packages, qt6-base-family from $(grep -E '^Inst (libqt6(core|gui|widgets|waylandclient)6|qt6-qpa-plugins)' /tmp/s.out | grep -c 'Sparky Stereo OS') ours / $(grep -E '^Inst (libqt6(core|gui|widgets|waylandclient)6|qt6-qpa-plugins)' /tmp/s.out | grep -c 'Debian') Debian"; grep -E '^E:' /tmp/s.out | head -3
done
echo "== kde-plasma-desktop with recommends"; apt-get -s install kde-plasma-desktop > /tmp/s.out 2>&1; echo rc=$? $(grep -c '^Inst' /tmp/s.out) packages; grep '^E:' /tmp/s.out | head -3
dpkg --add-architecture i386; apt-get -y update >/dev/null 2>&1
echo "== steam-installer (i386 enabled)"; apt-get -s install steam-installer > /tmp/s.out 2>&1; echo rc=$?; grep '^E:' /tmp/s.out | head -3
