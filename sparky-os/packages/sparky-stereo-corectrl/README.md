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

`sparky-stereo-knob-owner.service` runs while CoreCtrl or LACT is installed (its conditions) and follows CoreCtrl's helper on the system bus, lactd, LACT's settings (`/etc/lact/config.yaml`) and power-profiles-daemon's state file.

| Setting | Held by | Kept off it |
| --- | --- | --- |
| The processor's governor and energy preference | CoreCtrl, from the moment its helper is started until it stops | power-profiles-daemon's amd_pstate and intel_pstate drivers (`--block-driver`, a runtime drop-in in `/run`); tuned's cpu plugin (a runtime cpu instance of ours takes the processors) |
| An AMD card's power level | CoreCtrl while its helper runs (every AMD card); LACT for each card its current settings name | power-profiles-daemon's amdgpu_dpm action (`--block-action`), when the person turned it on |

Nothing changes where the daemon would not have written the setting anyway: power-profiles-daemon has no processor driver on processors without amd_pstate or intel_pstate in active mode, and its amdgpu_dpm action is off unless turned on.
The person is told once, through the edition's problems engine (a notice, until dismissed), which program holds the setting; a notice ends when its program is removed.
When the program lets go, the daemon gets the setting back (power-profiles-daemon is restarted with its own command line, tuned's instance is removed).
`knob-owner status` prints what is held, by whom, and what each daemon is kept off.

Known limits, said where they apply:
- tuned's video plugin has no runtime instances, so a radeon-driven card's power method cannot be taken from tuned: said (LOCAL6).
- At a tuned profile switch tuned writes the governor once before the processors are taken again.
- CoreCtrl's per-profile switch for a component is not read: while CoreCtrl runs it holds the processor and every AMD card.
- CoreCtrl and LACT on the same card: both write; said (LOCAL4), and the card is left to the person.

## Tests

`tests/run.sh` (decisions from recorded machines, the rule's code, the drop-in's text, the catalogues).
