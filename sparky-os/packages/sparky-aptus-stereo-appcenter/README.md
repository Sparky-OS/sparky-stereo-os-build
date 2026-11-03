Stereo APTus
============

Sparky Stereo OS, Daniel Ramos's edition of SparkyLinux (by Paweł "pavroo" Pijanowski).

This package sits beside Paweł Pijanowski's sparky-aptus-appcenter, on which it depends.
It owns only paths named sparky-aptus-stereo-appcenter and its own polkit actions.
It never replaces or diverts the original's files.
The start page reads the original category links at runtime and shows them below our edition sections.
Unrecognized requests go unchanged to the original handler, from its working directory.

System offers compressed RAM swap (zram), absent and off in the edition by default.
The action /usr/lib/sparky-aptus-stereo-appcenter/actions/zram supports status, install and remove.
Status is unprivileged JSON with dpkg installation state, active zram0 swap state and translated display text.
Install and remove require root through the package's polkit policy.
Both this page and the Memory KCM call this same action.
Install explicitly requests Debian's systemd-zram-generator, including when already installed automatically, so apt records the person's choice.
The package depends on kmod so Debian’s generator can load the kernel module when it is first chosen.
It starts dev-zram0.swap immediately after install, using Debian’s configuration and the edition’s inherited-generator guard.
Removal stops the swap first, then its setup service, before removing the package.
A restart is mentioned only when systemd is not running, with that reason.
Failures remain with the shared problems engine and are read on the next page load.
A failed stop or device reset prevents removal; a failed start is retained with its repair.
Removal checks service Result and zero disksize after stopping, not only systemctl’s exit code.
The engine’s explicit repair retries the failed reset through Debian’s generator after swap is inactive.

The ordered sections offer 3D emulation, stereo players/editors/tools, VR and SteamVR, drivers, then System.
The shipped catalogue comes from the edition's image, emulation and role lists, with the VLC Stereo package selected by make-meta.py.
Install and remove use the shared engine; installation refuses a candidate outside the trusted edition archive.
The system's configured Flathub remote supplies SlimeVR; no remote is added here.
The SlimeVR driver ZIP is downloaded and checked against its pinned SHA-256 before being made available in /var/cache/sparky-aptus-stereo-appcenter.
It is labelled Downloaded; its linked upstream instructions describe registration in SteamVR.
CODESYS 4 links to CODESYS Store; registration and the EULA stay with CODESYS.
Hardware Setup owns driver choices.

Build with OUT=/scratch/output APTUS_SOURCE=/path/to/the/fork bash build.sh inside the package build container.
The default source is the build repository's APTus submodule.
The recipe uses the shared Lean Code standalone pipeline and retains the authored payload in its source package.
