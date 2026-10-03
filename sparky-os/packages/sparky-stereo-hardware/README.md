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
