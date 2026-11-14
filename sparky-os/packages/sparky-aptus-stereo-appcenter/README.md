Stereo APTus
============

Sparky Stereo OS, Daniel Ramos's edition of SparkyLinux (by Paweł "pavroo" Pijanowski).

This package keeps Paweł Pijanowski’s main APTus pages alongside the edition’s stereo tabs.
It depends on sparky-aptus-appcenter for the shared system helper programs.
The main tree is copied from the source checkout’s 9/ directory and its absolute internal paths are relocated into this package’s namespace at build time.
The installed original package is never overwritten.
It owns paths named sparky-aptus-stereo-appcenter and its own polkit actions.
It never replaces or diverts the original's files.
The start page reads its own main/index.html category links and shows them below the unchanged edition sections.
Unrecognized requests go to the copied main handler, from its own working directory.

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
Install and remove use the shared engine.
The installed sparky-stereo-apt only-ours policy determines which names require a trusted edition candidate.
Other entries install APT's candidate from configured signed archives.
Names with no downloadable archive candidate are omitted, except only-ours names whose missing edition build remains a visible problem with Repair.
The system's configured Flathub remote supplies SlimeVR; no remote is added here.
The SlimeVR driver ZIP is downloaded and checked against its pinned SHA-256 before being made available in /var/cache/sparky-aptus-stereo-appcenter.
It is labelled Downloaded; its linked upstream instructions describe registration in SteamVR.
CODESYS 4 links to CODESYS Store; registration and the EULA stay with CODESYS.
Hardware Setup owns driver choices.

Build with OUT=/scratch/output APTUS_SOURCE=/path/to/the/fork bash build.sh inside the package build container.
The default source is the build repository's APTus submodule.
The recipe uses the shared Lean Code standalone pipeline and retains the authored payload in its source package.

An entry that is not installed shows, beside its button, the install-time downloads it brings: the packages apt would install for it whose control file declares Sparky-Install-Download-Size and Sparky-Install-Download-Source, with the size and the source, on a metered connection (NetworkManager says yes or guess-yes) and, said, when NetworkManager cannot be read (ORDER 399b; Daniel, 2026-11-04: "warn the user with current size on stereo aptus interface or apt depending from where the user came").
The declaration, the metered test, the setting Sparky::Install-Downloads::Announce and the nine languages belong to sparky-stereo-apt (its reader, /usr/lib/sparky-stereo-apt/sparky_install_downloads.py), which apt's own notice uses too: one declaration, one reader, two front ends. This package depends on the version that has it.
FlightGear is an entry since 0.1.4; its data downloader, flightgear-data-installer, declares 1.75 GiB from SourceForge.

Vinci belongs to Multimedia, Video tools, alongside Kdenlive.
KamLynk belongs to Accessories, Devices, with the same accdev_kamlynk key as main.
Neither belongs to a stereo tab.
main-entries.json holds their publisher URLs, hashes, sizes and runtime requirements; catalogue.json remains the stereo catalogue.
The main handler and direct entry backends route these two programs to the same verified action and shared download notice.
Every added entry sentence and label is translated in the ten required languages.
A sync compares URI inventories per page against the fetched main source and keeps the existing edition additions and stereo tabs.
The source and installed-payload checks must find every main URI, both new entry keys, and an unchanged published stereo catalogue.

The published sparky-stereo-apt reader has nine language catalogues.
This package supplies the maintained reader's Spanish catalogue in a locale overlay and links the other nine catalogues to their existing owner.
The same installed reader still owns metered detection, settings, formatting and messages; no detector or second message set is implemented here.
An explicit SPARKY_INSTALL_DOWNLOADS_LANG override remains respected.

An entry's tools (ORDER 565).
Daniel, 2026-11-14: "only when someone install vinci - same for anything that needs this sort of dependancy".
A program an entry offers may need packages to run (Vinci: podman, distrobox, fuse3 and bsdextrautils; KamLynk: fuse3; a Flatpak entry: flatpak).
The entry declares them (`tools` in its row, or its kind's list in tools.py), and this package never depends on them.
Before the person installs, the entry's page says which tools are missing, how many packages apt would install for them and their download and disk sizes, read from `apt-get -s`; on a metered connection they join the program's own download in the shared notice.
The action refuses, with apt's reason, a tool that cannot be installed, before anything is downloaded; it downloads the program and verifies it, downloads the tools' archives, and only then installs.
Tools already installed are not reinstalled, upgraded or mentioned.
Removing the entry removes no tool: those the entry brought are marked as automatically installed unless another installed entry declares them, and apt decides from there.
