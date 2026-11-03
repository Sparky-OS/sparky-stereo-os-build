Stereo APTus
============

Sparky Stereo OS, Daniel Ramos's edition of SparkyLinux (by Paweł "pavroo" Pijanowski).

This package sits beside Paweł Pijanowski's sparky-aptus-appcenter, on which it depends.
It owns only paths named sparky-aptus-stereo-appcenter and its own polkit actions.
It never replaces or diverts the original's files.
The start page reads the original category links at runtime and shows them below our System section.
Requests outside aptus://stereo_ go unchanged to the original handler, from its working directory.

System offers compressed RAM swap (zram), absent and off in the edition by default.
The action /usr/lib/sparky-aptus-stereo-appcenter/actions/zram supports status, install and remove.
Status is unprivileged JSON with dpkg installation state, active zram0 swap state and translated display text.
Install and remove require root through the package's polkit policy.
Both this page and the Memory KCM call this same action.
Install explicitly requests Debian's systemd-zram-generator, including when already installed automatically, so apt records the person's choice.
It starts dev-zram0.swap immediately after install, using Debian’s configuration and the edition’s inherited-generator guard.
Removal stops the swap first, then its setup service, before removing the package.
A restart is mentioned only when systemd is not running, with that reason.
Failures remain with the shared problems engine and are read on the next page load.
A failed stop prevents removal; a failed start is retained with its repair.

ORDER 104 still owns the other sections and entries: 3D emulation, stereo players, editors and tools, VR and SteamVR, drivers, verified vendor downloads, the pinned launcher, the CODESYS 4 store link and SlimeVR.
This first version neither implements nor claims those entries.

Build with OUT=/scratch/output APTUS_SOURCE=/path/to/the/fork bash build.sh inside the package build container.
The default source is the build repository's APTus submodule.
The recipe uses the shared Lean Code standalone pipeline and retains the authored payload in its source package.
