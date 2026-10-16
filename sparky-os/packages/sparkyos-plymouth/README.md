sparkyos-plymouth
The SparkyOS boot splash of Sparky Stereo OS, packaged from the artwork repository's plymouth/ folder.

Sparky Stereo OS, Daniel Ramos's edition of SparkyLinux (by Paweł "pavroo" Pijanowski).
Copyright: see the artwork's copyright file, installed as /usr/share/doc/sparkyos-plymouth/copyright.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 2 of the License, or (at your option) any later version.

Dependencies:
-------------
plymouth, plymouth-themes

Build:
-------------
ART=/path/to/artwork-repo/plymouth OUT=/path/to/output ./build.sh

The other theme, for a 3D display in side-by-side mode:
plymouth-set-default-theme -R sparkyos-stereo
