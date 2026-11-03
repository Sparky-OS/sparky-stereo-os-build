sparky-stereo-memory-kcm
The Memory page of System Settings: the Cushion Swap File.

Copyright (C) 2026 Daniel Ramos (Capitain Jack), see copyright file.

This program is free software: you can redistribute it and/or modify it
under the GNU General Public License, version 3 or any later version.

Dependencies:
-------------
KDE Frameworks 6 (KAuth, KCMUtils, KI18n, Kirigami)
sparky-stereo-kernel-settings (>= 20261103.4~)
sparky-stereo-cushion-swap (recommended)
sparky-stereo-problems (>= 0.1.0), pkexec

Build:
-------------
OUT=/path/in/workspace/pending-pack bash ./build.sh (inside a Debian container with KF6 development packages)

Install:
-------------
su
apt-get install ./sparky-stereo-memory-kcm_0.1.6_amd64.deb

Uninstall:
-------------
su
apt-get purge sparky-stereo-memory-kcm

What the page shows and changes
-------------
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
The page reads and writes the Cushion Swap settings file, so hand edits and
the page agree. The write goes through KAuth (action
org.sparkylinux.sparkystereo.memory.savecushion, administrator authentication
kept for the session). The helper accepts only on/off and keeps every other line.

Tests
-------------
autotests/run-tests.sh checks hand edits and daemon status as an ordinary user.
autotests/run-kauth-test.sh checks allowed and denied Cushion Swap saves and
authorized repairs on a private system bus in a disposable container.

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

memorypagetest loads the real KCM plugin in English and Portuguese and
checks reason visibility, translated controls and button order.

Compressed RAM swap (zram) is the person’s package choice.
The old Automatic/On/Off setting and its privileged configuration-writing action are removed.
The page never reads, writes or deletes /etc/default/sparky-stereo-zram.
The zram item reads installation and active-device state through Stereo APTus and invokes the same authorized install/remove action.
Status is refreshed on showing the page, activating its application and requesting Refresh status.
The APTus action supplies the translated labels and kept engine failure; the page does not copy its package-management logic.
