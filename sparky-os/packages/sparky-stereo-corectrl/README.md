# sparky-stereo-corectrl

CoreCtrl and LACT in Sparky Stereo OS (queue rows 168 and 601).
Daniel, 2026-10-17, on CoreCtrl: "maybe integrate and make it run in the background (today it request a root password at every boot)".
The package does nothing until CoreCtrl or LACT is installed; CoreCtrl comes with the gamer role (task-sparky-stereo-gamer) or by hand, LACT by the hardware layer's detection on AMD cards.

## No password at login

`/usr/share/polkit-1/rules.d/90-sparky-stereo-corectrl.rules` is the rule CoreCtrl's setup guide gives ("Don't ask for user password", gitlab.com/corectrl/corectrl/-/wikis/Setup), with the group set to `sudo`, the administrators of Debian's own polkit rule (`50-default.rules`).
Its two actions, `org.corectrl.helper.init` and `org.corectrl.helperkiller.init`, are answered yes for a person in the group sudo at a local, active session; any other person, a remote or inactive session, and every other administrator action keep their own answer.
The rule names CoreCtrl's actions only, so it does nothing where CoreCtrl is not installed (polkit does not know the actions).
A rule made by hand at `/etc/polkit-1/rules.d/90-corectrl.rules` with the same code (comments and spacing aside) is set aside at the install as `/var/backups/sparky-stereo-corectrl/90-corectrl.rules`, said, and put back if the package is removed; any other rule there is the person's and stays.
To be asked again: a rule of your own in `/etc/polkit-1/rules.d` with a name that sorts before this one (polkit reads every rules folder in the order of the file names, `/etc` first on a tie) that returns `polkit.Result.AUTH_ADMIN_KEEP` for the two actions.

## In the system tray at login

`/etc/xdg/autostart/org.corectrl.CoreCtrl.desktop` starts CoreCtrl at login; its `TryExec=corectrl` keeps it from starting where CoreCtrl is not installed (Desktop Application Autostart Specification 0.5, 2.2).
It has the name of CoreCtrl's own entry, so a copy made the way CoreCtrl's guide says (`~/.config/autostart/org.corectrl.CoreCtrl.desktop`) replaces it instead of starting a second CoreCtrl.
`/etc/xdg/corectrl/corectrl.ini` sets CoreCtrl's own "Start minimized on system tray" (`startOnSysTray=true`); Qt reads it after the person's own `~/.config/corectrl/corectrl.ini`, so the box in CoreCtrl's settings stays the person's.
To start without it: System Settings, Autostart (the switch writes `Hidden=true` into a file of the same name in `~/.config/autostart`).
To see the window at login: untick "Start minimized on system tray" in CoreCtrl.

## One writer per setting

`sparky-stereo-knob-owner.service` runs while CoreCtrl or LACT is installed (its conditions) and follows CoreCtrl (its helper on the system bus, the person's saved profiles, the programs it applies a profile for), lactd, LACT's settings (`/etc/lact/config.yaml`), the daemons, and who changes power-profiles-daemon's actions.

| Setting | Held by | Kept off it |
| --- | --- | --- |
| The processor's governor and energy preference | CoreCtrl, while the profile it applies has its processor control on (not "Do not control") | power-profiles-daemon's amd_pstate and intel_pstate drivers (`--block-driver`, a runtime drop-in in `/run`); tuned's cpu plugin (a runtime cpu instance of ours takes the processors) |
| An AMD card's power level | CoreCtrl, while the profile it applies has that card's power control on; LACT for each card its current settings name | power-profiles-daemon's amdgpu_dpm action: turned off through the daemon's own `SetActionEnabled` (no restart) while any card is held (the daemon has one switch for every card), the person's own choice otherwise |

What CoreCtrl manages is read as CoreCtrl builds it (corectrl 1.5.2, `src/core/session.cpp`, `profileview.cpp`): the global profile, then the profile of each program its helper reports starting (its `appExec` and `appExit` signals), each component (CPU, GPU) from the highest profile in which it is on.
The profiles are the ones the person saved (`~/.config/corectrl/profiles/*.ccpro`); a change is followed when CoreCtrl saves it.
CoreCtrl writes a control only while it is on (`Control::sync`), so a processor control or a card's power control set to "Do not control" is the daemons' again.

The person's own choice of the amdgpu_dpm action is kept in `/var/lib/sparky-stereo-corectrl/ppd-actions.json` and given back whenever no card is held.
LACT turns that action off at every start of its daemon and never gives it back (lact 0.10.1, `lact-daemon/src/system/power_profiles_daemon.rs`), and power-profiles-daemon saves the running state as the person's choice at its next profile change; so who changes the action is read from the bus (a monitor of its `SetActionEnabled` calls, for root), and a change by LACT or by this service is never taken as the person's.
The service is ready before lactd starts (`Type=notify`, `Before=lactd.service`).

Nothing changes where the daemon would not have written the setting anyway: power-profiles-daemon has no processor driver on processors without amd_pstate or intel_pstate in active mode, and its amdgpu_dpm action is off unless turned on.
The person is told once, through the edition's problems engine (a notice, until dismissed), which program holds the setting; the notice ends when that program, still running, no longer holds it, or when it is removed.
When the program lets go, the daemon gets the setting back (power-profiles-daemon is restarted with its own command line, its action is the person's again, tuned's instance is removed).
`knob-owner status` prints what is held, by whom, what CoreCtrl's stack is, and what each daemon is kept off.

Known limits, said where they apply:
- A manual profile turned on from CoreCtrl's tray is kept in CoreCtrl's memory only (`Session::manualProfile_`) and told to no other program, so it cannot be followed: when a manual profile would set something nothing keeps the daemons off, that is said (LOCAL13, LOCAL14).
- CoreCtrl's window applies a change at once and writes the profile only at Save; an applied change that is not saved is not seen (CoreCtrl itself drops it when it closes).
- tuned's video plugin has no runtime instances, so a radeon-driven card's power state cannot be taken from tuned: said (LOCAL6).
- At each of tuned's own profile switches tuned writes its profile's governor, and when the processors are taken again (about 60 ms later on the bench) it writes back the value it found, as tuned does whenever a device leaves an instance; between switches it writes nothing. Keeping tuned off at the switch itself needs tuned to know the held devices when it loads a profile.
- CoreCtrl and LACT on the same card: both write; said (LOCAL4), and the card is left to the person.

## Tests

`tests/run.sh` (decisions from recorded machines with CoreCtrl's profiles, the person's choice of an action and who changed it, the rule's code, the drop-in's text, the notices, the unit's ordering, the catalogues).
