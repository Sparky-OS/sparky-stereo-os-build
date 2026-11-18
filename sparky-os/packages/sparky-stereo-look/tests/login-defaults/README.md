# ORDER 668 installed login probe

Run `probe.sh` as `DESKTOP_PROBE` in the `stereo-proof-rig/scripts/login-splash` fresh-login fixture.
Mount this folder read-only at `/defaults-probe`, then use `DESKTOP_PROBE=/defaults-probe/probe.sh`, `MODES=2d`, `NOSHOT=1` and `SETTLE=6`.
The fixture still starts `startplasma-wayland`, KWin and plasmashell.
The probe reads the real panel over D-Bus and all changed settings from the installed KConfig layers.
It writes `defaults.json`, the D-Bus response and a snapshot of the person's configuration under `CASE`.

Run first on the predecessor package image and require a nonzero exit with failed expectations.
Run with the successor packages and require every expectation to pass.
For personalisation, extract the predecessor's `user-config.tar`, write these explicit choices with `kwriteconfig6` and pass that home as `CONFIG_SEED` to a fresh successor login with `EXPECT_USER=1`:

| File | Group | Key | Value |
| --- | --- | --- | --- |
| ksmserverrc | General | loginMode | restorePreviousLogout |
| ksmserverrc | General | confirmLogout | true |
| kdeglobals | Sounds | Theme | ocean |
| powerdevilrc | BatteryManagement | BatteryLowLevel | 10 |
| powerdevilrc | BatteryManagement | BatteryCriticalLevel | 5 |
| powerdevilrc | BatteryManagement | BatteryCriticalAction | 1 |
| powerdevilrc | AC/Display | DisplayBrightness | 80 |
| powerdevilrc | AC/Display | UseProfileSpecificDisplayBrightness | false |
| powerdevilrc | Battery/Display | UseProfileSpecificDisplayBrightness | false |
| powerdevilrc | AC/Keyboard | KeyboardBrightness | 20 |
| powerdevilrc | LowBattery/Keyboard | KeyboardBrightness | 25 |
| powerdevilrc | AC/Keyboard | UseProfileSpecificKeyboardBrightness | false |
| powerdevilrc | Battery/Keyboard | UseProfileSpecificKeyboardBrightness | false |
| powerdevilrc | LowBattery/Keyboard | UseProfileSpecificKeyboardBrightness | false |

Keep the predecessor's Kickoff panel in this seed.
The upgrade case expects that panel to remain Kickoff.
Compare saved configuration hashes immediately before and after package installation too.

These checks establish live panel creation and effective settings inside a real login.
They do not establish battery-triggered shutdown, physical brightness changes, audible sound playback, application restoration or the logout confirmation dialog.
Those require separate behavioral probes.
