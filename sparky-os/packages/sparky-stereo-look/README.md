Sparky Stereo Look

The default desktop uses Stereo Oxygen in dark colours.
Ctrl+Alt+Del, Ctrl+Shift+Esc and Ctrl+Esc open System Monitor through KDE’s global-shortcut desktop entry.
Meta+Esc remains System Monitor’s upstream launch shortcut; Meta+Ctrl+Esc remains KWin’s Kill Window shortcut.
The package requires plasma-workspace 4:6.7.4-2+stereo3d6 or later, which makes Ctrl+Alt+Esc open the logout screen.
Your saved assignments take precedence; Reset to defaults in System Settings restores these edition defaults.

The loading screen

Between the login and the desktop KSplash shows the theme's splash on every screen.
It is the boot splash's picture (sparky-stereo-plymouth, theme sparky-stereo-lines), the same pictures placed the same way, so the screen is one picture from power-on to the desktop; `tests/splash-pictures.sh` fails when the two drift apart.
On a screen in a 3D mode each part stands at the boot splash's level, inside the person's own limits for that screen (System Settings, 3D Depth): the background on the screen, the swirl at half the popped limit, the SparkyOS logo at the popped limit, the electrons popping where their curve rises and sinking where it falls.
The depth comes from `StereoDepth` in `org.sparky.stereo` (stereo-layer 1.20.0); on a 2D screen the picture is plain, and when a 3D screen cannot be shown a pair the picture is plain and the session's log says why once.
`/etc/xdg/ksplashrc` names this theme; a person's own choice (another theme, or None) stays, and Oxygen's splash stays selectable.
