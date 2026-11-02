# sparky-stereo-problems-plasma

The session's side of [sparky-stereo-problems](../sparky-stereo-problems/README.md): every problem the computer keeps (the machine's, this boot's and the person's own) as a KDE notification, for every package of the edition.

- At login, one notification per open problem, or one summary when several are open; Show details on the summary opens one notification for each.
- Then one notification for each new problem, and for each problem whose message changed or whose repair failed.
- A failed problem is Critical and stays until it is closed; a degraded one or a notice is Normal.
- Each offers Show details (what failed, why, what to do, the command, its exit status and output, the repair and the last repair), Repair, the record's own actions and Hide.
- Repair runs `sparky-stereo-problems repair`; for the machine's and this boot's problems through `pkexec` and the polkit action `org.sparkylinux.problems.repair`.
- Hide is the person's own: the problem stays listed (`sparky-stereo-problems list`) and comes back when its message changes or a repair fails.
- A notification closes when its problem is over.

`sparky-stereo-problems-notifier.service` runs for the whole session (graphical-session.target); `sparky-stereo-problems-notifier.path` starts it when a store changes while it is not running.
The events are in `sparky-stereo-problems.notifyrc`, so System Settings' Notifications page lists them.
