Sparky Stereo Look

The default desktop uses Stereo Oxygen in dark colours.
Ctrl+Alt+Del, Ctrl+Shift+Esc and Ctrl+Esc open System Monitor through KDE’s global-shortcut desktop entry.
Meta+Esc remains System Monitor’s upstream launch shortcut; Meta+Ctrl+Esc remains KWin’s Kill Window shortcut.
The package requires plasma-workspace 4:6.7.4-2+stereo3d6 or later, which makes Ctrl+Alt+Esc open the logout screen.
Your saved assignments take precedence; Reset to defaults in System Settings restores these edition defaults.

The loading screen

Between the login and the desktop KSplash shows the theme's splash on every screen.
It is Daniel Campos Ramos's Sparky Black design, with its original background, box, logo and progress bar.
On a screen in a 3D mode the background stands at the person's sunk limit, the box and progress bar at the popped limit, and the original logo at twice that limit.
The explicit artwork multiple is confined to the logo of this splash; ordinary items remain inside the person's limits.
The depth comes from `StereoDepth` in `org.sparky.stereo` (stereo-layer 1.22.0); on a 2D screen the picture is plain, and a renderer unable to draw the pair logs why once.
The former boot-picture splash remains selectable as “Sparky Stereo, boot picture” on System Settings' Splash Screen page, with its original levels.
`/etc/xdg/ksplashrc` still names the default theme; a person's saved splash or None stays.
