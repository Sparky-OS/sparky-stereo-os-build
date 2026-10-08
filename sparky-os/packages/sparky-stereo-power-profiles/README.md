sparky-stereo-power-profiles
KDE power profile defaults for Sparky Stereo OS.

Copyright (C) 2026 Daniel Ramos (Capitain Jack), see copyright file.

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later version.

Dependencies:
-------------
power-profiles-daemon >= 0.30
powerdevil >= 6.7

Build:
-------------
OUT=/path/in/workspace/pending-pack ./build.sh (inside a container)

Install:
-------------
su
OUT=/path/to/packages ./install.sh

Uninstall:
-------------
su
./install.sh uninstall

The package owns /etc/xdg/powerdevilrc as a conffile. It contains only the
three Performance groups: AC selects performance, Battery balanced and
LowBattery power-saver. User settings take precedence. It changes no idle,
button, lid or automatic-sleep setting. The remaining milestone 1 defaults
must extend this one owner after Daniel's sleep decision and their tests.

The profile mapping is Daniel's brief. The group and key come from Plasma's
PowerDevilProfileSettings.kcfg and PowerProfile::onProfileLoad(). PPD owns
the CPU and GPU behavior; this package writes no governor or GPU sysfs file.
PPD may omit performance on unsupported hardware. Plasma keeps that native
limitation, and this package does not substitute a second power controller.

The real PPD and settings tests, sources and limits are in
../../power-idle/REPORT.md and ../../power-idle/probe/.
