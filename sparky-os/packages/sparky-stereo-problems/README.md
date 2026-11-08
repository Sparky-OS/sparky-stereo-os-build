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
A problem of this boot, such as a failed service, is a new record at every boot; there the same fingerprint carries the dismissal to the new record, so the same unit failing the same way stays dismissed and another exit status shows again.
`list --over` (C: `ssp_list_over_json`) also lists the dismissed problems of this boot's kind that are not happening now (`"over": true`), which is how the page shows them and how Bring back ends their mark.
Repairing the machine's problems runs through `pkexec` and the polkit action `org.sparkylinux.sparkystereo.problems.repair`, which runs only `repair` of what root kept.

## Every failed system service

`/usr/lib/systemd/system/service.d/50-sparky-stereo-problems.conf` names `sparky-stereo-problems-failed@%N.service` in `OnFailure=` for every service (systemd.unit(5), "Top level drop-ins with template units"; the handler's own instances have the drop-in masked).
The handler keeps the failure for this boot with the service's last lines and `systemctl restart` as its repair; the problem is over when systemd no longer has the unit as failed.

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
