# sparky-stereo-problems

One engine for the whole edition: when a step cannot do what it is for, it says what failed, why and what to do, and the problem stays kept until it is repaired (Daniel, 2026-11-01: "either it works or not and the user must know").
A package hands its failure to the engine; it keeps no store, status, repair or notifier of its own (Daniel, 2026-11-02: "Why machinery to keep a failure for each?").

## Where problems are kept

- `/var/lib/sparky-stereo-problems`: the machine's, kept until repaired (`--machine`, the default for root).
- `/run/sparky-stereo-problems`: this boot's, such as a failed system service (`--boot`).
- `$XDG_STATE_HOME/sparky-stereo-problems` (`~/.local/state/...`): the person's own (`--person`, the default for a person).

One record per file, `PACKAGE_KEY.json`, written through a dot-file and renamed under a lock of the store's `.lock`.
A problem kept again with the same message keeps its first time, its id and its hide.

## From a package

Shell and maintainer scripts:

    sparky-stereo-problems run sparky-stereo-boot update-grub LOCAL3 -- update-grub
    sparky-stereo-problems keep --repair '["sparky-stereo-boot","repair"]' sparky-stereo-boot esp LOCAL7 /boot/efi
    sparky-stereo-problems clear sparky-stereo-boot esp
    sparky-stereo-problems say sparky-stereo-boot LOCAL9 nvidia

`run` shows the command's output as it comes; a success clears the key, a failure keeps it with the command, its exit status and the end of its output, and the message's first two `%s` are the command and its status.
Python: `import sparky_stereo_problems` (the same verbs). C and C++: `#include <sparky-stereo-problems.h>`, `pkg-config --cflags --libs sparky-stereo-problems`.

## Messages in nine languages

Messages are the package's own Sparky language files (`lang/en`, `lang/pl` ...: `KEY="text"`, `%s` per argument).
At package build time

    sparky-stereo-problems catalog PACKAGE lang/ DESTDIR/usr/lib/systemd/catalog --subject LOCAL1

turns them into journal message catalogs, so `journalctl -x` explains each problem too; a language that lacks a message, or has another number of `%s`, fails the build.
The engine reads the catalogs in gettext's order (LANGUAGE, LC_ALL, LC_MESSAGES, LANG, then `/etc/default/locale`; LANGUAGE is not used in the C locale), the whole name, then the bare language, then English.
Each message's MESSAGE_ID is the name-based UUID (version 5, URL namespace) of `https://sparkylinux.org/problems/PACKAGE/KEY` (`sparky-stereo-problems message-id PACKAGE KEY`), and every event is mirrored to the journal with it.

## The person

`sparky-stereo-problems list` shows every problem; the session's notifier (sparky-stereo-problems-plasma) shows each as a notification, with Show details, Repair, the record's own actions and Dismiss, and the Problems page of System Settings lists the current and the dismissed ones.
Dismiss is the engine's `hide` and Bring back its `show` (ORDER 468), the person's own: the problem stays kept and listed with its evidence, and comes back when its message changes or a repair fails; `show` undoes it.
The mark (`$XDG_STATE_HOME/sparky-stereo-problems/.hidden/`) holds a copy of the record and its fingerprint, the message and its arguments.
A problem of this boot, such as a failed service, is a new record at every boot; there the same fingerprint carries the dismissal to the new record, so the same service stays dismissed however it fails (its unit is the fingerprint; for every other problem the message and its arguments), and a repair that failed since shows it again.
`list --over` (C: `ssp_list_over_json`) also lists the dismissed problems of this boot's kind that are not happening now (`"over": true`), which is how the page shows them and how Bring back ends their mark.
Repairing the machine's problems runs through `pkexec` and the polkit action `org.sparkylinux.sparkystereo.problems.repair`, which runs only `repair` of what root kept.

## Every failed system service

`/usr/lib/systemd/system/service.d/50-sparky-stereo-problems.conf` names `sparky-stereo-problems-failed@%N.service` in `OnFailure=` for every service (systemd.unit(5), "Top level drop-ins with template units"; the handler's own instances have the drop-in masked).
The handler keeps the failure for this boot with the service's last lines and `systemctl restart` as its repair; the problem is over when systemd no longer has the unit as failed.

## A failed hibernation says why (0.2.1, ORDER 446)

systemd-hibernate, systemd-suspend-then-hibernate and systemd-hybrid-sleep are failed services like any other, but "it stopped with exit status 1, Repair starts it again" is wrong for them: Repair hibernates again, and a device that cannot freeze refuses every time.
For these three units the handler reads the attempt's own journal and keeps `The computer could not hibernate: REASON.` with what to do.

What is read, in this order (the first that applies is the reason):

- systemd-sleep's lines of the unit's invocation (`SYSLOG_IDENTIFIER=systemd-sleep`, matched by `INVOCATION_ID` or `_SYSTEMD_INVOCATION_ID`): its SLEEP_STOP message (`MESSAGE_ID=8811e6df2a8e40f58a94cea26f8ebf14`, `SD_MESSAGE_SLEEP_STOP`, with `ERRNO=` and `SLEEP=`) and any other line of priority error or worse (systemd v262 `src/sleep/sleep.c`: "Failed to put system to sleep. System resumed again: %m", "Failed to find location to hibernate to: %m", "No valid 'resume=' option found, refusing to hibernate.", "Failed to write mode to /sys/power/disk: %m").
- the kernel's lines (`_TRANSPORT=kernel`) between the invocation's first line and five seconds after its last, so an earlier or later attempt is never read as this one's.
  The device comes from the line itself (`virtio-pci 0000:00:05.0: PM: failed to freeze async: error -95`, which `_KERNEL_DEVICE=+pci:0000:00:05.0` carries as a field too).

| Kind (message) | The kernel or systemd line that says it (source in v7.3.1 and systemd v262) | Repair |
| --- | --- | --- |
| lockdown (LOCAL80, fix LOCAL90) | `Lockdown: COMM: hibernation is restricted; see man kernel_lockdown.7`, security/lockdown/lockdown.c `lockdown_is_locked_down` (the check is `hibernation_available()`, kernel/power/hibernate.c) | none |
| a virtio-fs share (LOCAL77, fix LOCAL86 with the share's mount points from `/proc/self/mountinfo`, LOCAL87 without) | `virtio-fs: suspend/resume not yet supported`, fs/fuse/virtio_fs.c `virtio_fs_freeze` (returns -EOPNOTSUPP), with the device lines below | none |
| a device that refused (LOCAL76, fix LOCAL88) | `DEVICE: PM: failed to freeze|suspend|hibernate|quiesce|poweroff[ async| early| late| noirq]: error N`, drivers/base/power/main.c `pm_dev_err`; the driver's callback from `PM: bus_pm_freeze(): driver_freeze returns N` (`dpm_run_callback`) | none |
| programs that would not freeze (LOCAL78 with their names from the `task:NAME state:` lines of `sched_show_task`, or LOCAL79; fix LOCAL89) | `Freezing user space processes failed after N seconds (N tasks refusing to freeze, wq_busy=N):`, kernel/power/process.c `try_to_freeze_tasks` (also "Freezing remaining freezable tasks" and "aborted") | retry, said as such |
| no swap area big enough (LOCAL81, fix LOCAL91) | `Not enough free swap`, `Cannot find swap device, try swapon -a`, `Cannot get swap writer` (kernel/power/swap.c `swap_write_page`, `swsusp_write`), or systemd-sleep's `Failed to find location to hibernate to: %m` (ENOSPC is "No swap space available for hibernation", src/shared/hibernate-util.c) | none |
| no resume device (LOCAL82, fix LOCAL92) | `No valid 'resume=' option found, refusing to hibernate.`, systemd v262 src/sleep/sleep.c | none |
| the kernel's own error line (LOCAL83, fix LOCAL93) | any error line of the power code: `PM: hibernation: Some devices failed to power down, aborting` (kernel/power/hibernate.c `create_image`), `Some system devices failed to power down, aborting`, and the other `PM:` lines | retry, said as such |
| systemd-sleep's line only (LOCAL84, fix LOCAL93) | its SLEEP_STOP message or another error line, with nothing from the kernel | retry, said as such |
| nothing found (LOCAL85, fix LOCAL93) | the journal of that attempt holds no reason | retry, said as such |
| the journal cannot be read (LOCAL94, fix LOCAL93) | `sd_journal_open` failed | retry, said as such |

The retry (`systemctl restart UNIT`) is kept only where the cause can pass or is unknown; it puts the computer to sleep again, and the text says so.
For a cause that stays, no repair is offered and the problem ends when systemd no longer has the unit as failed, which is the next hibernation that works.
In `journalctl -x` the catalog's nested parts (the operation's name, the reason) are the journal's English fields: the sentence is in the reader's language, those parts are not.
`SPARKY_STEREO_PROBLEMS_JOURNAL=DIR` makes the engine read a journal folder instead of the system's (tests keep fixtures there).

suspend-then-hibernate and hybrid sleep suspend instead when the hibernation fails, and the service then ends well (systemd-sleep.c: "Couldn't hibernate, will try to suspend again."), so no `OnFailure=` runs.
The package's drop-ins (`systemd-suspend-then-hibernate.service.d`, `systemd-hybrid-sleep.service.d`) run `sparky-stereo-problems sleep-attempt UNIT` in `ExecStopPost=`: it keeps the failed hibernation for this boot under the unit's key (no unit field, so no unit state ends it early), and ends it when a later attempt of that unit worked.
A service that failed is left to its `OnFailure=` handler.

## Failures that outlive removal (0.1.1)

A maintainer script at remove, purge or abort-install can keep an unresolved
restoration even after its package disappears:

    sparky-stereo-problems keep --machine --after-removal \
      --command '["cp","/usr/share/base-files/motd","/etc/motd"]' \
      --repair '["cp","/usr/share/base-files/motd","/etc/motd"]' \
      --status "$status" --output "$error" sparky-stereo-console motd \
      'cp /usr/share/base-files/motd /etc/motd'

This form requires machine scope, a nonzero status, nonempty command and error,
a repair, and exactly PACKAGE KEY STEP. Use the failed operation as STEP (a
command needs no translation); the engine owns the translated explanation.
The record belongs to `sparky-stereo-problems`, with key
`after-removal:PACKAGE:KEY`; its data names the original package, step, operation,
command and error. Clearing the removed package's ordinary records cannot clear
it. Successful repair, or an explicit clear of the engine-owned key, ends it.
A unit state cannot automatically finish this record.

Postrm cannot assume this dependency is still installed (Debian Policy 6.5).
If it is absent, the maintainer script must print its embedded diagnostic and
attempt to journal it itself, including saying if the journal cannot be reached.
Packages using this flag Depend on sparky-stereo-problems (>= 0.1.1).

## Before installation and after removal (0.1.2)

A failure is kept even before dpkg has unpacked the package or its catalogs.
Without a catalog, the engine saves literal English supplied as MESSAGE (or `text_en` in the details), or an English explanation naming the package, step and exit status.
Once its catalog arrives, the package's translated message is used.
`run` says the record it just kept without running collection.

Each record remembers whether dpkg's file list has been observed since this failure was kept.
A dpkg post-invoke hook collects after package operations in the running system’s standard database, so a first installation is observed before a later removal.
Collection removes a package's stale record only after that observed presence is gone; an active dpkg state with a missing file list is not removal.
Old records without that observation and records in an unreadable database are kept until presence is observed, they are repaired, or they are explicitly cleared.
A new failure kept after removal starts a new observation, so it too is retained.
A reader unable to delete a record continues to show it, including a recovered service until a privileged collection clears its boot record.
A package's `postrm remove` should still call `clear --all PACKAGE`; use `--after-removal` for a restoration failure that must outlive that clear.
