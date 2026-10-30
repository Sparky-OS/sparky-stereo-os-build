sparky-stereo-grub-l10n

GRUB's menu in the system's language.

Copyright (C) 2026 Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack)

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

-------------

Why:

grub-mkconfig (update-grub) writes the menu entries in the language of its environment, through GRUB's catalogue (/usr/share/locale/LANG/LC_MESSAGES/grub.mo).
Debian's catalogues, from grub2-common, leave out every message of GRUB's shell scripts (po/POTFILES-shell.in upstream: grub-mkconfig, the /etc/grub.d scripts and the other util/*.in tools).
Checked 2026-10-16: German has 1447 messages in Debian 13's grub-common 2.12-9+deb13u2 and 1662 in 2.14-4, against 1738 in GNU GRUB 2.14's po/de.po; "Advanced options for %s" is in none of Debian's.
So an installed system in German shows "Advanced options for ...", "UEFI Firmware Settings" and "Windows Boot Manager (on ...)" in English, under GRUB's own help text in German.

How:

The package carries those messages, and only those, from GNU GRUB 2.14's translations, for every language upstream translates (usr/share/sparky-stereo-grub-l10n/LANG.mo).
At install, and whenever grub2-common updates a catalogue (a dpkg trigger), Debian's grub.mo is diverted to grub.mo.debian and grub.mo becomes Debian's messages plus the missing ones; Debian's translation wins where both have one.
Removing the package gives Debian's files back.

After every merge, at install and whenever grub2-common updates a catalogue, the package runs update-grub where /boot/grub/grub.cfg exists, so the translated entries reach the menu at once.
It does not in a live session, a chroot or a container, where the image build or the installer writes the menu.

Build: OUT=/path/to/output ./build.sh (dpkg-deb, gettext; GRUB_TARBALL=/path/to/grub-2.14.tar.xz, else it is downloaded and checked)
