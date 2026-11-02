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
sparky-stereo-problems (>= 0.1.0), pkexec

Build:
-------------
OUT=/path/in/workspace/pending-pack bash ./build.sh (inside a Debian container with KF6 development packages)

Install:
-------------
su
apt-get install ./sparky-stereo-memory-kcm_0.1.4_amd64.deb

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
  next start. RAM and storage fields supply the translated explanation for
  automatic decisions and configuration overrides. Unrecognized decisions
  retain the helper's raw words under an explicit label.
- Cushion Swap File: on or off, written as CUSHION_SWAP= in
  /etc/default/cushion-swap; the daemon restarts and reads it. Switching it
  off never switches the swap area off. Its state (off, deployed, retracting,
  switched off, no area) and how it is woken (PSI, or compatibility mode
  without PSI) come from /run/cushion-swap/status.
- Memory protection: protected, protected with a kept problem, not protected,
  daemon not running, or status unreadable with the read error.
  The protection result, problem keys and reason come from the status file;
  the swap area's state remains a separate line.
- Kept problems: their text and next steps come from the shared engine in the
  person's language. Problems with an engine repair offer a Repair button.
  Machine repairs use pkexec and org.sparkylinux.sparkystereo.problems.repair;
  the engine runs the commands kept with the record, never a page-supplied command.
  A matching engine record replaces the raw daemon reason. Without a matching
  record, the raw reason is labelled as the daemon's own words.
  Repair appears below its problem text and before Refresh status in every
  language. Refresh status and repairs preserve unsaved choices in the page.
The page reads and writes those settings files, so a hand edit shows in the page
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

The cushionstatustest target exercises all five status outcomes, stale and
invalid PIDs, unreadable and malformed files, the engine's Portuguese text and
kept English text when its catalog is absent, and refresh with unsaved edits.
It requires sparky-stereo-problems and Cushion Swap catalogs, supplied through
SPARKY_STEREO_PROBLEMS_CATALOG in the test container.
The authorization script runs its clients as uid 1000 (TEST_UID/TEST_GID can
select another test account), with root confined to container setup and helpers.
It also checks the engine's real pkexec repair with fakepolkit allowing and
denying the installed policy's action. The container must have a passwd entry
for the test uid, pkexec and Cushion Swap's catalogs installed.

The memorykcmtest data rows cover every structured zram decision and an unknown
result. memorypagetest loads the real KCM plugin in English and Portuguese and
checks reason visibility, the translated automatic explanation and button order.
