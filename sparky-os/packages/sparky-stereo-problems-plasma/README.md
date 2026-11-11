# sparky-stereo-problems-plasma

The session's side of [sparky-stereo-problems](../sparky-stereo-problems/README.md): every problem the computer keeps (the machine's, this boot's and the person's own) as a KDE notification, for every package of the edition.

- At login, one notification per open problem, or one summary when several are open; Show details on the summary opens one notification for each.
- Then one notification for each new problem, and for each problem whose message changed or whose repair failed.
- A failed problem is Critical and stays until it is closed; a degraded one or a notice is Normal.
- Each offers Show details (what failed, why, what to do, the command, its exit status and output, the repair and the last repair), Repair, the record's own actions and Dismiss; the summary at login offers Dismiss all.
- Repair runs `sparky-stereo-problems repair`; for the machine's and this boot's problems through `pkexec` and the polkit action `org.sparkylinux.sparkystereo.problems.repair`.
- Dismiss is the person's own (the engine's `hide`): it takes effect at once, is told once with where the problem stays (the Problems page) and Open Problems, and the problem stays listed (`sparky-stereo-problems list`); it comes back when its message changes or a repair fails. A failed service that fails the same way at a later boot stays dismissed.
- A notification closes when its problem is over or dismissed, on the notification or on the page; a problem brought back on the page is told again.

## The Problems page

`kcm_sparkystereo_problems` is the Problems page of System Settings (System Administration): the current problems and the dismissed ones, each with its title, text, since when, severity, the last failed repair, Repair where there is one, the record's own actions, Dismiss, and Bring back for a dismissed one; a dismissed problem that is not happening now (a failed service that works again) says so. It follows the stores and systemd's unit states, so a problem that appears or ends is listed or goes at once, and shows a plain empty state. It is ordinary Qt Quick (Kirigami), with no stereo-specific code. Its strings are the domain `kcm_sparkystereo_problems`, the notifier's `sparky-stereo-problems-plasma`.


`sparky-stereo-problems-notifier.service` runs for the whole session (graphical-session.target); `sparky-stereo-problems-notifier.path` starts it when a store changes while it is not running.
The events are in `sparky-stereo-problems.notifyrc`, so System Settings' Notifications page lists them.
