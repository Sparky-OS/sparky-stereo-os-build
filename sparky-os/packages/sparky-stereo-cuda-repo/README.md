sparky-stereo-cuda-repo
NVIDIA's CUDA repository for Sparky Stereo OS, with the edition's pins.

Copyright (C) 2026 Paweł Pijanowski, Daniel Ramos (Capitain Jack) and others, see copyright file.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.

Files:
-------------
/etc/apt/sources.list.d/sparky-stereo-cuda.sources: NVIDIA's repository for Debian 13, https://developer.download.nvidia.com/compute/cuda/repos/debian13/x86_64/, read for amd64. The package's postinst writes it from /usr/share/sparky-stereo-cuda-repo/sparky-stereo-cuda.sources, only when no other source of apt names this repository, and says so.
/usr/share/keyrings/cuda-archive-keyring.gpg: NVIDIA's key for it, the same file NVIDIA's cuda-keyring package installs.
/etc/apt/preferences.d/91sparky-stereo-cuda: the pins.

The edition's rule: NVIDIA's repository may update compute, never the display driver, which is the edition's, with HDMI 3D.
The pins say it in apt's terms:
- CUDA, the CUDA-X libraries and GPUDirect Storage come from NVIDIA and keep updating (1002).
- NVIDIA's EGL platform libraries come from NVIDIA too (1002): NVIDIA's driver needs NVIDIA's versions of them.
- NVIDIA's driver stays at the version of the edition's stereo 3D module: sparky-stereo-nvidia-driver-lock decides it, and this package depends on it.
- Everything else NVIDIA publishes there is never chosen over another archive's build (100). NVIDIA also publishes its own builds of some of Debian's tools, dkms among them; the edition's own dkms (with the overlay from /etc/dkms/<module>/ that sparky-stereo-dkms-compat needs) and Debian's other tools stay the ones installed.
  A package that only NVIDIA publishes still installs from there, and a package installed from there keeps getting NVIDIA's newer versions, as Debian's backports do.

A source of your own for this repository is kept as it is, and the pins apply to it all the same, since they go by origin, not by source file: the install prints "keeping your NVIDIA source at PATH; the edition's pins apply" and writes no source of its own.
Two sources for one repository with different Signed-By would stop apt ("Conflicting values set for option Signed-By").
A pin file of your own for NVIDIA's origin decides where it also pins what 91sparky-stereo-cuda pins only when it sorts before it (such as /etc/apt/preferences.d/00-cuda, or /etc/apt/preferences): apt reads the files in name order, "The first specific-form record matching an available package version determines the priority of the package version" (apt_preferences(5); the edition names CUDA and NVIDIA's EGL platform libraries this way), and for Package: * records of the same origin it also takes the first that matches, not the highest (measured with apt 3.3.3; the manual speaks of the maximum). A record of yours that names a package the edition does not name, in any file, still beats the edition's Package: * record (measured: sparky-stereo-gpu-nvidia's records for NVIDIA's container toolkit at 990 and egl-wayland at 500 apply though that file sorts after). The install says which of your files decide.
The pin file is a conffile: an upgrade keeps your changes to it and asks what to do.
Before this package, the image and the hardware setup wrote the same two files themselves; the first install takes them over without a question when nobody changed them; a changed pin file gets dpkg's question (the default keeps yours), and a changed source is kept as your own.

Choices:
-------------
Remove NVIDIA's repository:

    apt remove sparky-stereo-cuda-repo

Removing the package removes the source it wrote (a source of your own stays); purging it removes the pin file too.
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
It is not needed: this package installs the same key and, where you have none, a source for the same repository.
Where cuda-keyring is installed already, this package takes over its key file (the same bytes; Debian Policy 7.6.1) and keeps its source, /etc/apt/sources.list.d/cuda-debian13-x86_64.list, as a source of your own; cuda-keyring stays installed.
Installing cuda-keyring after this package fails, since both ship that key file; nothing changes then.

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
apt remove sparky-stereo-cuda-repo   (apt purge also removes the pin file)
