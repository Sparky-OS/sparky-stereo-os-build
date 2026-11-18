sparky-stereo-headset
The Headset page of System Settings, the Headset entry of the panel and a user service, over HeadsetControl.

Copyright (C) 2026 Daniel Ramos (Capitain Jack), see copyright file.

This program is free software: you can redistribute it and/or modify it
under the GNU General Public License, version 3 or any later version.

What it does:
-------------
- A Headset page in System Settings, under Multimedia beside Sound: the battery, the chat mix, sidetone, lights, voice prompts, the time after which the headset switches itself off, and the equalizer presets, only for what the connected headset reports (HeadsetControl's capabilities). A setting the headset lacks is not shown, not even as a dead control. With no headset the page says so, and says what to do.
- A Headset entry in the panel's system tray, there only while a headset is connected: its icon with the battery level, a pop-up with the battery and the same click actions, and a menu (lights, voice prompts, sidetone off, low, medium and high, one entry for each equalizer preset the headset has, and the settings page).
- The person's choices are kept by KConfig, in ~/.config/sparky-stereo-headsetrc, one group per headset (its vendor and product numbers), and only for the settings the person changed: the headset keeps every setting that was never touched here. A user service (sparky-stereo-headset watch, wanted by default.target and started by udev when a listed headset appears) sends the saved choices to the headset when it appears again, as KDE does for a screen, and tells the person when the battery is at or below the level PowerDevil keeps for peripherals (powerdevilrc, BatteryManagement, PeripheralBatteryLowLevel, 10 when unset).
- Ten languages (de, en, es, fr, ja, ko, pl, pt_BR, zh_CN, zh_TW).

The command: sparky-stereo-headset status [--json] | apply | watch (man sparky-stereo-headset).

The headsets and what each one can do come from HeadsetControl (package headsetcontrol, which this package depends on). The list of the udev rules (data/71-sparky-stereo-headset.rules) is written by tools/make-rules.sh from the program's own `headsetcontrol -u`; tests/udev-proof.sh checks that the two lists are the same.

Tests (no headset needed):
- tests/engine-proof.sh: the command against a stand-in of the program for the HyperX Cloud II Wireless dongle (03f0:018b, only battery and inactive time) and against the real program on its own test device (every capability).
- tests/udev-proof.sh: the package installed by apt, the rules for the recorded headset (umockdev) and for no other device, an upgrade, a removal and a purge.
- tests/plasma-login/: a Plasma login in a container (KWin on a virtual output, plasmashell with a panel), the tray entry, its pop-up and menu and the page captured through KWin's own screenshot interface, clicks sent through KWin's fake input.

Credits: HeadsetControl, Denis Arnst "Sapd" and the contributors (github.com/Sapd/HeadsetControl, GPL-3.0), whose command line this package drives. Read for what a front end shows, no code copied: HeadsetKontrol, TheBill2001 (gitlab.com/TheBill2001/HeadsetKontrol, GPL-3.0; a Kirigami program, not in Debian, in KDE's Arch user repository only); headset-plasmoid, gort818; plasmoid-headsetcontrol, lazy-stripes; and Plasma's own camera indicator, whose Passive-until-used entry this one follows.
