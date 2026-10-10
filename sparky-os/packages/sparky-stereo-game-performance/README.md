sparky-stereo-game-performance
Hold the performance profile while a game runs.

Copyright (C) 2026 Daniel Ramos (Capitain Jack), see copyright file.

This program is free software: you can redistribute it and/or modify it
under the GNU General Public License, version 3 or any later version.

Dependencies:
-------------
bash
power-profiles-daemon (>= 0.30)

Build:
-------------
OUT=/path/in/workspace/pending-pack bash ./build.sh

Install:
-------------
su
OUT=/path/to/packages bash ./install.sh

Uninstall:
-------------
su
bash ./install.sh uninstall

Use:
-------------
game-performance /path/to/game [arguments...]
For Steam's per-game launch options: game-performance %command%

Runs as the user. The daemon owns the profile hold and its cleanup, including
when the client disconnects. Concurrent games each hold their own request.
A power-saver hold takes precedence, as power-profiles-daemon specifies.
An unsupported performance profile runs the game unchanged. A daemon error
while listing profiles also falls back to the command, with the client's error
on stderr. A failure acquiring an available profile is returned by the client.
The command's arguments, exit code and termination signal pass through.
The helper adds no idle inhibitor and runs no screensaver or GPU command.
Before the game starts it touches $XDG_RUNTIME_DIR/cushion-swap-game-opening:
on a kernel without PSI, the Cushion Swap File samples memory faster while
the game loads (sparky-stereo-cushion-swap README).

Sources and measured tests: ../../power-idle/POWER-DEFAULTS.md
