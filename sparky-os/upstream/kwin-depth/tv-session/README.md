# A second session for trying KWin's stereo depth

This starts a separate desktop session on the display, from a text console, with the depth build of KWin.
Nothing is installed and your own session is not touched: the packages are unpacked in `prefix/`, the
session has its own D-Bus session bus, its own configuration, cache, state and data folders in `home/`
(not your `~/.config`), and its own Wayland socket.

1. Press Ctrl+Alt+F3 to switch to the text console on tty3 (your desktop keeps running on its own console).
2. Log in there with your user name and password.
3. Run `./start.sh` from this folder.
4. After a few seconds the screens come up in the modes you last chose (a copy of your `kwinoutputconfig.json`), with the Oxygen look: the wallpaper and the panel from Plasma, and Konsole, Dolphin, KWrite and System Settings open. The active window is at the screen's level, the other windows are a little behind it, menus and tooltips of the active window a little in front of it, the wallpaper at the back, the panel at the screen's level. A window's shadow lies on what it falls on, and the pointer takes the depth of what it is over.
5. If the televisions come up in 2D (no depth visible), choose the display's 3D mode yourself in System Settings, Display, which is open in the session. The session never does that for you.
6. To change the depth while you look: in System Settings, Display, the page "3D Depth" has the two limits as sliders (move them and press Apply). Or from another console or over ssh, run: `./tune.sh SUNK POPPED` (for example `tune.sh 12 5`; the numbers are pixels at 1920 wide, 0 switches that side off; it starts at 10 and 4).
7. To go back to your desktop at any time: press Ctrl+Alt+F2 (your desktop is on tty2). The test session keeps running on tty3 until you stop it.
8. To stop it: close Konsole's last window, or run `./stop.sh`. The session ends by itself and you are back at the text console; log out there with `exit`.
9. The logs are in `log/` (`session.log` is KWin's).

What it does not do: it does not install anything, does not change your display modes (it never runs kscreen-doctor and sets no mode; the displays take the modes of the copy of `kwinoutputconfig.json`), does not read or write your desktop's configuration, does not use your D-Bus session bus, does not replace your KWin, and does not log you out. It starts no kded, and if a program asks for it, its display module is switched off in the session's own settings, so there is no KScreen daemon. It has no screen locker, no sound or network applets and no login or splash screen, and its programs keep their settings in `home/`, not in your own. Its Plasma shell, helper programs and system libraries are the ones installed on the host; only KWin comes from `prefix/`.
