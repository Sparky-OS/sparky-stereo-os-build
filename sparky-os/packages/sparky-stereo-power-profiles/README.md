sparky-stereo-power-profiles
KDE power and idle defaults for Sparky Stereo OS.

Copyright (C) 2026 Daniel Ramos (Capitain Jack), see copyright file.

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later version.

Dependencies:
-------------
power-profiles-daemon >= 0.30
powerdevil >= 6.7
sparky-stereo-powerdevil-policy >= 1 (provided by our patched PowerDevil)

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

The package owns /etc/xdg/powerdevilrc and /etc/xdg/kscreenlockerrc as
conffiles. User settings take precedence. AC selects performance, Battery
balanced and LowBattery power-saver. Independent idle locking is disabled;
PowerDevil locks at screen-off and Plasma locks on suspend.

AC dims at 900 seconds and switches the screen off at 9900. Its automatic
sleep action is intentionally omitted: the patched PowerDevil uses its
native UPower lid-presence property. A desktop stays awake; a plugged laptop
sleeps at 14400 seconds. Battery dims/off/sleeps at 900/1200/1800 seconds;
LowBattery at 180/300/600. The power button selects Shutdown everywhere.
The lid selects NoAction on AC and Sleep on battery, including with an
external screen. Our KWin patch keeps the closed internal panel dark in
its layout and excludes it from pointer movement and new placement when
another visible output exists. Dimming remains gated by native support.

The package requires the virtual capability sparky-stereo-powerdevil-policy
from the patched PowerDevil package. Stock PowerDevil must not satisfy it:
stock code cannot apply desktop/laptop AC sleep defaults or idle locking.
The GL show and its trigger belong to milestone 3 and are not shipped here.

The profile mapping is Daniel's brief. The group and key come from Plasma's
PowerDevilProfileSettings.kcfg and PowerProfile::onProfileLoad(). PPD owns
the CPU and GPU behavior; this package writes no governor or GPU sysfs file.
PPD may omit performance on unsupported hardware. Plasma keeps that native
limitation, and this package does not substitute a second power controller.

The real PPD and settings tests, sources and limits are in
../../power-idle/REPORT.md and ../../power-idle/probe/.
