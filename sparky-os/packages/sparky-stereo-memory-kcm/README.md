sparky-stereo-memory-kcm
The Memory page of System Settings: compressed RAM swap and the Cushion Swap File.

Copyright (C) 2026 Daniel Ramos (Capitain Jack), see copyright file.

This program is free software: you can redistribute it and/or modify it
under the GNU General Public License, version 3 or any later version.

Dependencies:
-------------
KDE Frameworks 6 (KAuth, KCMUtils, KI18n, Kirigami)
sparky-stereo-kernel-settings (zram-auto)
sparky-stereo-cushion-swap (recommended)

Build:
-------------
OUT=/path/in/workspace/pending-pack bash ./build.sh (inside a Debian container with KF6 development packages)

Install:
-------------
su
apt-get install ./sparky-stereo-memory-kcm_0.1.0_amd64.deb

Uninstall:
-------------
su
apt-get purge sparky-stereo-memory-kcm

What the page shows and changes
-------------
- Compressed RAM swap (zram): Automatic, On or Off, written as ZRAM= in
  /etc/default/sparky-stereo-zram. Under the switch: what Automatic decides
  for this computer and why (zram-auto --explain, the program zram-generator
  runs at boot), and whether zram is in use now. A change applies at the
  next start.
- Cushion Swap File: on or off, written as CUSHION_SWAP= in
  /etc/default/cushion-swap; the daemon restarts and reads it. Switching it
  off never switches the swap area off. Its state (off, deployed, retracting,
  switched off, no area) and how it is woken (PSI, or compatibility mode
  without PSI) come from /run/cushion-swap/status.
The page reads and writes only those files, so a hand edit shows in the page
and the page's change shows in the file. The write goes through KAuth (action
org.sparkylinux.sparkystereo.memory.save, administrator authentication kept
for the session); the helper accepts only auto/on/off and on/off and keeps
every other line of both files.

Tests
-------------
autotests/run-tests.sh (as a user): hand edits show in the page, the daemon's
status shows, Automatic is explained for a 96 GB NVMe and a 4 GB eMMC fixture
by the real zram-auto. autotests/run-kauth-test.sh (as root in a disposable
container): a private system bus activates the installed helper, a test double
answers for polkit, and the page saves through KAuth: allowed, both files
change; denied, both stay byte for byte and the page shows why.
