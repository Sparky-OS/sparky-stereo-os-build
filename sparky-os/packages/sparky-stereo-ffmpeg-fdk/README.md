Sparky Stereo FFmpeg with Fraunhofer's AAC
Rebuilds the edition's FFmpeg on your own computer with Fraunhofer's AAC encoder (libfdk_aac), installs it, and builds it again by itself when the edition updates FFmpeg.

Copyright (C) 2026 Paweł Pijanowski, Daniel Ramos (Capitain Jack) and others, see copyright file.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

Why:
-------------
The edition's FFmpeg is deb-multimedia's ffmpeg-dmo with our stereo 3D patches, built as a GPL (version 3) build without `--enable-nonfree` and without `--enable-libfdk-aac`. FFmpeg's `LICENSE.md` says a GPL build that enables libfdk-aac is unredistributable, so the edition cannot ship one. FFmpeg's own `aac` encoder is in the edition's build. This package is for those who want Fraunhofer's encoder as well: it builds that FFmpeg on the user's own computer, where the licence allows it, and the result is for that computer only.

What it does (`sparky-stereo-ffmpeg-fdk`, run as your own user):
-------------
1. Prints the warning (the result may not be passed on; how long the build takes on this computer) and asks. `--yes` does not skip the text.
2. Asks for your password once (sudo, or pkexec), then, as root: installs the build dependencies of `ffmpeg-dmo` (apt shows the list and asks, unless `--yes`).
3. As you, in a temporary folder under `/var/tmp`: fetches the edition's source package with `apt-get source` (from the repository's own source index), adds a changelog entry `VERSION+fdkN` that says the build is for this computer only, and builds with `dpkg-buildpackage -B -Ppkg.ffmpeg-dmo.fdk`. The profile is off by default in the source package; it turns `--enable-libfdk-aac --enable-nonfree` and the build dependency `libfdk-aac-dev` on.
4. Installs `ffmpeg` and the libraries as `VERSION+fdkN`. apt prefers them: `/etc/apt/preferences.d/sparky-stereo-ffmpeg-fdk` pins versions `*+fdk*` at 1002, above the repository's 1001, so an upgrade does not swap them for the build without the encoder.
5. The 32-bit libraries (Steam and Wine need them) are `Multi-Arch: same`: apt and dpkg want one version for both architectures and identical files under `/usr/share/doc`. The helper takes the edition's own 32-bit packages of the same version, changes only their version (and the strict dependencies between them) and copies the four shared documentation files from the 64-bit build. They keep the edition's code; they are not rebuilt with the encoder.
6. Checks that `ffmpeg -encoders` lists `libfdk_aac`, then takes the build dependencies out again (only what this run installed, and only if nothing else needs them).

Updates:
-------------
`/etc/apt/apt.conf.d/99sparky-stereo-ffmpeg-fdk` runs `/usr/lib/sparky-stereo-ffmpeg-fdk/check-update` after every successful `apt update`. If the edition's repository has a newer FFmpeg than the one the local build was made from, the build runs again in the background (a transient systemd service at the lowest priority, or a detached process), with the consent given at the first run. Nothing happens on a computer that never built one; a rebuild that failed is not tried again by itself for the same version; a computer on battery waits for the mains. Until the rebuild is done the old local build stays (the pin), so FFmpeg is never half upgraded.

Other commands:
-------------
- `sparky-stereo-ffmpeg-fdk --status`: what is installed, what the repository has, whether a rebuild is due.
- `sparky-stereo-ffmpeg-fdk --remove`: back to the edition's FFmpeg (apt downgrades the local packages to the repository's, with this package's pin left out).
- `sparky-stereo-ffmpeg-fdk --rebuild`: build again now (also after a failed automatic rebuild).
- `--keep-build-deps`: leave the build tools installed (a later rebuild is quicker).
- Log: `/var/log/sparky-stereo-ffmpeg-fdk.log`; the log of a failed build: `/var/lib/sparky-stereo-ffmpeg-fdk/last-build.log`.

Dependencies:
-------------
sparky-stereo-apt, apt, dpkg-dev, build-essential, fakeroot, util-linux, python3, sudo | policykit-1 (recommended: powermgmt-base). `libfdk-aac-dev` and `libfdk-aac2` come from the user's own apt sources (deb-multimedia, which the edition adds, or Debian non-free).

Build:
-------------
./build.sh   (the package lands in /K3D/temp/sparky-os/repo, or in $OUT)

Test:
-------------
tests/run-tests.sh   (in a debian:testing container with deb-multimedia and a test repository; tests/README.md says how)
