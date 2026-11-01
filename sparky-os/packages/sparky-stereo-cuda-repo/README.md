sparky-stereo-cuda-repo
NVIDIA's CUDA repository for Sparky Stereo OS, with the edition's pins.

Copyright (C) 2026 Paweł Pijanowski, Daniel Ramos (Capitain Jack) and others, see copyright file.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.

Files:
-------------
/etc/apt/sources.list.d/sparky-stereo-cuda.sources: NVIDIA's repository for Debian 13, https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64/, read for amd64.
/usr/share/keyrings/cuda-archive-keyring.gpg: NVIDIA's key for it, the same file NVIDIA's cuda-keyring package installs.
/etc/apt/preferences.d/91sparky-stereo-cuda: the pins.

The edition's rule: NVIDIA's repository may update compute, never the display driver, which is the edition's, with HDMI 3D.
The pins say it in apt's terms:
- CUDA, the CUDA-X libraries and GPUDirect Storage come from NVIDIA and keep updating (1002).
- NVIDIA's EGL platform libraries come from NVIDIA too (1002): NVIDIA's driver needs NVIDIA's versions of them.
- NVIDIA's driver stays at the version of the edition's stereo 3D module: sparky-stereo-nvidia-driver-lock decides it, and this package depends on it.
- Everything else NVIDIA publishes there is never chosen over another archive's build (100). NVIDIA also publishes its own builds of some of Debian's tools, dkms among them; the edition's own dkms (with the overlay from /etc/dkms/<module>/ that sparky-stereo-dkms-compat needs) and Debian's other tools stay the ones installed.
  A package that only NVIDIA publishes still installs from there, and a package installed from there keeps getting NVIDIA's newer versions, as Debian's backports do.

Both /etc files are conffiles: an upgrade keeps your changes to them and asks what to do.
Before this package, the image and the hardware setup wrote the same two files themselves; the first install takes them over without a question when nobody changed them, and asks about a file you changed (the default keeps yours).

Choices:
-------------
Remove NVIDIA's repository:

    apt purge sparky-stereo-cuda-repo

Purge, not remove: a removed package's conffiles stay, so apt would keep reading the source.
The driver lock stays with the NVIDIA module that needs it.

Use NVIDIA's dkms instead of the edition's: the edition's own dkms comes from its repository at 1001, so put these lines in a file of your own, such as /etc/apt/preferences.d/00-local, then run apt install dkms.

    Package: dkms dh-dkms
    Pin: origin developer.download.nvidia.com
    Pin-Priority: 1002

Any file name works, since this package names no record for dkms: apt_preferences(5) says "The first specific-form record matching an available package version determines the priority of the package version", and a record naming packages comes before the Package: * records.
A priority of 1000 or more installs NVIDIA's version even where it is lower than the edition's ("P >= 1000 causes a version to be installed even if this constitutes a downgrade of the package").
Delete your file to go back to the edition's dkms: apt then installs it at the next upgrade.
For another package of NVIDIA's repository that this package does not name and that another archive also has, a record of your own at 990 gives you NVIDIA's build (apt-cache policy NAME shows the priorities).

NVIDIA's own cuda-keyring:
-------------
It is not needed: this package installs the same key and a source for the same repository.
The two packages cannot be installed together (they ship the same key file), so installing this one removes cuda-keyring.
cuda-keyring's own source, /etc/apt/sources.list.d/cuda-debian13-x86_64.list, stays until cuda-keyring is purged; it names the same key, so apt reads the repository from both and only warns that it is configured twice (and reads its i386 packages as well, since that source names no architecture).
A source of your own for this repository with another Signed-By stops apt ("Conflicting values set for option Signed-By"): remove one of the two.

Dependencies:
-------------
apt
sparky-stereo-nvidia-driver-lock

Install:
-------------
apt install sparky-stereo-cuda-repo
apt update

Uninstall:
-------------
apt purge sparky-stereo-cuda-repo
