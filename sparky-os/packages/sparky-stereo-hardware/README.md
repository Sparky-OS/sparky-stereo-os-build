sparky-stereo-hardware
Detect and configure matched hardware for Sparky Stereo OS.

Copyright (C) 2026 Paweł Pijanowski, Daniel Ramos (Capitain Jack) and others, see copyright file.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.

Dependencies:
-------------
apt
bash
ca-certificates
coreutils
curl
grep
isenkram-cli
kmod
laptop-detect
lm-sensors
nvidia-detect
pciutils
python3
sed
sparky-remsu
sparky-xterm
udev
usbutils
util-linux
yad

Build:
-------------
OUT=/path/to/workspace/out ./build.sh (inside debian:testing)

Install:
-------------
su
./install.sh

Uninstall:
-------------
su
./install.sh uninstall

Use:
-------------
Start Hardware Setup from the menu, or run `sparky-stereo-hardware --auto` as root from the installer/first-boot workflow. No boot service or desktop autostart is enabled by this package. Repeat the command when hardware changes.

`--dry-run` prints matched packages and actions without installing, editing configuration, or probing sensors. To reproduce the supplied example inside a container: `sparky-stereo-hardware --auto --dry-run --fixture tests/fixtures/creative-nvidia-laptop`. Fixtures are plain text and require every fact file; `laptop` contains laptop-detect's exit code, 0 for laptop or 1 for desktop. Fixture mode cannot apply changes. Container execution without fixtures is rejected.

The GUI previews the plan and runs installation visibly in sparky-xterm. GUI labels are provided in English, Polish and Brazilian Portuguese. Diagnostic logs use English and include command output; automatic mode logs under `/var/log/sparky-stereo-hardware/`.

NVIDIA open support follows NVIDIA's 615.71.09 PCI table, including subsystem restrictions. Unknown cards and mixed supported/unsupported NVIDIA systems keep nouveau. Before the optional CUDA transaction, firmware-nvidia-graphics is installed for nouveau. A missing edition module, unavailable key, checksum mismatch or failed apt preflight leaves the previous repository policy in place. A failed actual apt transaction is an error requiring inspection; the tool does not pretend it rolled back partially installed drivers. Existing NVIDIA installations are not removed automatically.

The CUDA keyring archive is pinned by SHA-256 and only its public key is extracted. The repository has Signed-By and priority 1002. The install names both nvidia-driver=615.71.09-2 and nvidia-kernel-open-dkms-stereo3d. A changed upstream archive requires reviewing its key and updating the checksum in a new package release.

Creative support preserves the four original blobs in `/usr/lib/firmware/updates/` and uses `snd_hda_intel enable_msi=1`. It does not unload active audio. Reboot after driver/firmware changes. Xbox USB matches preinstall xpadneo for later Bluetooth pairing; xpadneo itself handles Bluetooth, not the USB transport. DisplayLink installs evdi-dkms; a working dock also needs its userspace DisplayLink component supplied by the edition.

Purging the setup tool removes its executable and menu files. It deliberately retains hardware packages, logs and generated sensor/audio/APT configuration so removing the UI does not disable installed hardware. Purge the individual firmware/DKMS package to remove its payload. Driver readiness, sensor readings and audio output on real hardware remain separate from container fixture proof.

Tests:
-------------
In a disposable Debian testing container, install the built packages and run `python3 tests/detection.py` and `bash tests/actions.sh`. The latter uses command doubles and a fake root for module loading and NVIDIA transactions. The test never loads a real module. See REPORT.md for the full build/install/use/purge transcript and limitations.
