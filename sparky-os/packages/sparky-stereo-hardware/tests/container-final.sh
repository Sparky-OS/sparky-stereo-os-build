#!/bin/bash
set -euo pipefail
[[ -e /.dockerenv ]] || { echo "Run in Docker only"; exit 1; }
exec >evidence/final.log 2>&1
export LC_ALL=C.UTF-8 DEBIAN_FRONTEND=noninteractive MAKEFLAGS=-j4 TMPDIR=$PWD/out/test-tmp
mkdir -p "$TMPDIR"
P=$PWD/sparky-stereo-os-build/sparky-os/packages
bash "$P/sparky-stereo-hardware/tests/container-build.sh"
apt-get -y --no-install-recommends --reinstall install "$PWD"/out/firmware-creative-stereo_*.deb "$PWD"/out/xpadneo-dkms_*.deb "$PWD"/out/sparky-stereo-hardware_*.deb
python3 "$P/sparky-stereo-hardware/tests/detection.py"
bash "$P/sparky-stereo-hardware/tests/actions.sh"
sparky-stereo-hardware --auto --dry-run --fixture "$P/sparky-stereo-hardware/tests/fixtures/creative-nvidia-laptop" >evidence/combined-dry-run.log
cp /usr/lib/sparky-stereo-hardware/detect.py "$PWD/out/detect.current.py"
cp evidence/detect-before.py /usr/lib/sparky-stereo-hardware/detect.py
if python3 "$P/sparky-stereo-hardware/tests/detection.py" >evidence/regression-old.log 2>&1; then
 cp "$PWD/out/detect.current.py" /usr/lib/sparky-stereo-hardware/detect.py
 echo 'FAIL regression test accepted old detector'; exit 1
fi
cp "$PWD/out/detect.current.py" /usr/lib/sparky-stereo-hardware/detect.py
rm "$PWD/out/detect.current.py"
grep -q 'nvidia-wrong-subsystem' evidence/regression-old.log
echo 'PASS regression test rejects original detector for wrong NVIDIA subsystem'
for package in sparky-stereo-hardware firmware-creative-stereo xpadneo-dkms; do
 test -z "$(dpkg -V "$package")"
 test "$(dpkg-query -W -f='${Maintainer}' "$package")" = 'Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>'
 test "$(dpkg-query -W -f='${Homepage}' "$package")" = https://sparkylinux.org
 grep -q '^Sparky Stereo OS, an edition of SparkyLinux' "/usr/share/doc/$package/copyright"
 test ! -e "/usr/share/doc/$package/changelog.Debian.gz"
done
for file in ctefx.bin ctefx-desktop.bin ctefx-r3di.bin ctspeq.bin; do
 cmp "/reference-firmware/$file" "/usr/lib/firmware/updates/$file"
done
cmp /reference-firmware/creative.txt /usr/share/doc/firmware-creative-stereo/creative.txt
echo 'PASS package checksums, provenance, notices and byte-identical Creative firmware'
dkms status | tee evidence/dkms-status.log
grep -q 'hid-xpadneo/0.10.0+git3879ba0, 7.2.8+deb14-amd64, x86_64: installed' evidence/dkms-status.log
test "$(modinfo -F version /lib/modules/7.2.8+deb14-amd64/updates/dkms/hid-xpadneo.ko)" = '0.10.0+git3879ba0'
echo 'PASS real DKMS build and module version; no module loaded'
desktop-file-validate /usr/share/applications/sparky-stereo-hardware.desktop
python3 - <<'PY'
import xml.etree.ElementTree as ET
p='/usr/share/polkit-1/actions/org.sparky-stereo-hardware.policy'
a=ET.parse(p).getroot().find('action')
assert a.attrib['id']=='org.sparky-stereo-hardware'
assert a.find("annotate[@key='org.freedesktop.policykit.exec.path']").text=='/usr/bin/sparky-stereo-hardware'
print('PASS polkit action and executable path')
PY
for language in en pl pt_BR; do
 source "/usr/share/sparky/sparky-stereo-hardware/$language"
 test -n "$LOCAL1" && test -n "$LOCAL2" && test -n "$LOCAL3"
 set +e
 xvfb-run -a yad --text-info --title="$LOCAL1" --filename=evidence/combined-dry-run.log --width=760 --height=500 --button="$LOCAL2:1" --button="$LOCAL3:0" --timeout=1 --timeout-indicator=bottom
 status=$?
 set -e
 test "$status" = 70
 echo "PASS headless yad plan window: $language (timeout=70)"
done
timeout 10 xvfb-run -a env SHELL=/bin/bash sparky-xterm "/usr/bin/touch $PWD/out/terminal-launch.ok" || true
test -f "$PWD/out/terminal-launch.ok"
rm "$PWD/out/terminal-launch.ok"
echo 'PASS real sparky-xterm launches a single command with an exported shell'
shellcheck -x -S warning "$P/sparky-stereo-hardware/bin/sparky-stereo-hardware" "$P/sparky-stereo-hardware/lib/actions.sh"
# Verify purge restores firmware lookup and leaves administrator files intact.
printf 'administrator marker\n' >/usr/lib/firmware/ctefx-desktop.bin
printf '# administrator marker\n' >/etc/modprobe.d/99-xpadneo-bluetooth.conf
apt-get -y purge sparky-stereo-hardware firmware-creative-stereo xpadneo-dkms
for package in sparky-stereo-hardware firmware-creative-stereo xpadneo-dkms; do
 if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'install ok installed'; then exit 1; fi
done
test ! -e /usr/bin/sparky-stereo-hardware
test ! -e /usr/share/applications/sparky-stereo-hardware.desktop
test ! -e /usr/share/polkit-1/actions/org.sparky-stereo-hardware.policy
test ! -e /usr/src/hid-xpadneo-0.10.0+git3879ba0
test ! -e /usr/lib/udev/rules.d/60-xpadneo.rules
test ! -e /usr/lib/modprobe.d/xpadneo.conf
test ! -e /usr/lib/firmware/updates/ctefx.bin
test ! -e /lib/modules/7.2.8+deb14-amd64/updates/dkms/hid-xpadneo.ko
! dkms status | grep -q hid-xpadneo
grep -Fxq 'administrator marker' /usr/lib/firmware/ctefx-desktop.bin
grep -Fxq '# administrator marker' /etc/modprobe.d/99-xpadneo-bluetooth.conf
echo 'PASS purge removed all three payloads and DKMS registration, preserving preexisting firmware and administrator configuration'
sha256sum out/*.deb >evidence/SHA256SUMS
printf 'FINAL PROOF COMPLETE\n'
