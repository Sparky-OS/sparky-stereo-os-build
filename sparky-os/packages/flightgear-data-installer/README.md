flightgear-data-installer
Fetches FlightGear's own data release, checks it and unpacks it where FlightGear looks for it.

Copyright (C) 2026 Daniel Ramos (Capitain Jack), see copyright file.

This program is free software: you can redistribute it and/or modify it
under the GNU General Public License, version 3 or any later version.

The declaration (ORDER 399b):
-------------
The control file says that installing this package downloads data, before anything is fetched:
  Install-Download-Size: 1883333376 (bytes)
  Install-Download-Source: https://sourceforge.net/projects/flightgear/files/release-2024.1/FlightGear-2024.1.5-data.txz/download
Both come from the recorded file the program reads. They reach the repository's Packages index, so `apt-cache show`, apt in a terminal (sparky-stereo-apt's hook,
on a metered connection and before "Do you want to continue?") and Stereo APTus show the size and the source before the person installs. The package is never on the
image: the games come when the person chooses them while installing.

Why:
-------------
Debian removed flightgear-data from testing on 16 October 2026 (Debian bug #1146394: undocumented font licences).
FlightGear 2024.1 compares the data's major and minor version with its own and refuses older data, so Debian's
2020.3 data does not help. Daniel Ramos's decision of 2026-10-31: "we do not host it", "an older version does not
help", "small downloader is better". The edition's repository never carries FlightGear's data; this package fetches
it from FlightGear's own release page.

What it does:
-------------
The package Provides flightgear-data-all (and -base, -ai and -models) at version 1:2024.1.5, so flightgear's
Depends is met. Its postinst runs flightgear-data-installer, which
  1. says what it needs (about 1.75 GiB to download, the room to unpack it) and stops before fetching if the room is not there;
  2. downloads FlightGear-2024.1.5-data.txz from SourceForge in PARALLEL byte ranges (8 by default, 1 to 16 in /etc/default/flightgear-data-installer), each
     range into its own part file in /var/cache/flightgear-data-installer/parts.N, every part continuing from the bytes it already has; a server that
     does not serve byte ranges stops the run and says so. One connection to SourceForge gives a few hundred kB/s to about 1 MB/s; the ranges multiply it;
  3. checks the SHA-256 recorded in /usr/share/flightgear-data-installer/recorded over the parts in order (no second copy of the file is made); a file that differs is deleted;
  4. unpacks it into a hidden folder beside /usr/share/games/flightgear, checks its version file, and links it into place,
     refusing to overwrite a file that is not its own; permissions are the ones Debian's data package uses;
  5. keeps the list of what it placed in /var/lib/flightgear-data-installer, so a failed run removes exactly that again and
     removing or purging the package removes the data, as Debian's data packages and ttf-mscorefonts-installer do (an upgrade keeps it).
Every failure stops the configuration, says what failed, why and what to do, in en, pl, pt_BR, fr, de, ja, ko, zh_CN and
zh_TW; dpkg keeps the package unconfigured and `sudo dpkg --configure flightgear-data-installer` tries again.

Without internet: download FlightGear-2024.1.5-data.txz elsewhere and run `sudo flightgear-data-installer --file FILE`
(the same SHA-256 check applies; the file is never changed or deleted).
A mirror may be set in /etc/default/flightgear-data-installer (MIRROR_URL, https:// or file:///); the hash is still checked.

The recorded values (published by FlightGear on SourceForge: size and MD5; the SHA-256 is ours, from a first download whose MD5
matched SourceForge's):
  URL     https://sourceforge.net/projects/flightgear/files/release-2024.1/FlightGear-2024.1.5-data.txz/download
  size    1883333376 bytes
  MD5     b93569a88a779d47c20be49b646baafd (SourceForge's)
  SHA-256 a904739192e6f039020da64f5905dc170519e84de6d45cf897e2552cd3f70135 (ours, in recorded)
  unpacked 2797352960 bytes in 24101 entries; the version file reads 2024.1.5

Updating to another FlightGear data release means a new version of this package with new recorded values.

Dependencies:
-------------
bash, ca-certificates, curl, xz-utils (coreutils, findutils, tar and util-linux are Essential)

Build:
-------------
OUT=/path/in/workspace/pending-pack bash ./build.sh (inside a Debian container)
