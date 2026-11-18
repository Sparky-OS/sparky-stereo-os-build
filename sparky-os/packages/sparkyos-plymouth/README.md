sparkyos-plymouth
The SparkyOS boot splash of Sparky Stereo OS, packaged from the artwork repository's plymouth/ folder.

Sparky Stereo OS, Daniel Ramos's edition of SparkyLinux (by Paweł "pavroo" Pijanowski).
Copyright: see the artwork's copyright file, installed as /usr/share/doc/sparkyos-plymouth/copyright.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 2 of the License, or (at your option) any later version.

Dependencies:
-------------
plymouth (>= 26.134.222-1+stereo3d4), plymouth-themes

Build:
-------------
ART_REPO=/path/to/artwork-repo SPARKY_BUILD_IMAGE=IMAGE OUT=/path/to/output ./build.sh

The artwork is read from the repository's object store at the commit and plymouth/ tree hash written in build.sh, never from a work tree.
The image holds python3, python3-yaml, dpkg-dev, fakeroot, debhelper, git, gcc, nodejs, node-acorn and perl.

The default theme is sparkyos-stereo: both eyes on a stereo output, one picture on a 2D screen.
The 2D theme:
plymouth-set-default-theme -R sparkyos
