set -e
export DEBIAN_FRONTEND=noninteractive
apt-get -y update >/dev/null 2>&1; apt-get -y install ca-certificates >/dev/null 2>&1
echo 'deb [trusted=yes] file:/repo ./' > /etc/apt/sources.list.d/zrepo.list
printf 'Package: *\nPin: release o=Sparky Stereo OS\nPin-Priority: 1001\n' > /etc/apt/preferences.d/sparky-stereo
apt-get -y update 2>&1 | tail -2
apt-cache policy | grep -B1 -A2 "Sparky Stereo OS" | head -6
apt-cache policy libqt6gui6 libqt6waylandclient6 qt6-base-dev qt6-qpa-plugins | grep -E "^[a-z]|Installed|Candidate|\*\*\*|^ +[0-9]+ " | head -30
for t in "kde-plasma-desktop" "krita" "kalgebra" "kubrick bino" "qt6-base-dev qt6-base-private-dev qt6-base-examples qt6-base-doc"; do
  echo "=== apt-get install -s $t"; apt-get -s install --no-install-recommends $t > /tmp/sim.out 2>&1; echo rc=$?; grep -E "^E:|Unmet|broken" /tmp/sim.out | head; grep -c "^Inst" /tmp/sim.out; grep -E "^Inst (lib)?qt6-base|^Inst libqt6(core|gui|wayland)|^Inst qt6-(base|qpa)" /tmp/sim.out | cut -c1-120 | head -5
done
echo "=== full recommends kde-plasma-desktop"; apt-get -s install kde-plasma-desktop > /tmp/sim.out 2>&1; echo rc=$?; grep -E "^E:" /tmp/sim.out | head; grep -c "^Inst" /tmp/sim.out; grep -E "^Inst .*qt6-base|^Inst libqt6gui6" /tmp/sim.out | cut -c1-120|head -3
echo "=== any qt6-base source package from Debian chosen?"; apt-cache policy qt6-base-dev | grep -E "Candidate"
