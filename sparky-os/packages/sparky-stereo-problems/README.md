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

`sparky-stereo-problems list` shows every problem; the session's notifier (sparky-stereo-problems-plasma) shows each as a notification, with Show details, Repair, the record's own actions and Hide.
Hide is the person's: the problem stays listed with its evidence and comes back when its message changes or a repair fails; `show` undoes it.
Repairing the machine's problems runs through `pkexec` and the polkit action `org.sparkylinux.sparkystereo.problems.repair`, which runs only `repair` of what root kept.

## Every failed system service

`/usr/lib/systemd/system/service.d/50-sparky-stereo-problems.conf` names `sparky-stereo-problems-failed@%N.service` in `OnFailure=` for every service (systemd.unit(5), "Top level drop-ins with template units"; the handler's own instances have the drop-in masked).
The handler keeps the failure for this boot with the service's last lines and `systemctl restart` as its repair; the problem is over when systemd no longer has the unit as failed.
