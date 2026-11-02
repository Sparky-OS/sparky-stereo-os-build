# Transition rebuilds

A package of ours can stop being installable without any change on our side.
Debian testing moves a library to a new soname, the old library leaves the archive, and our published build still depends on it.
On 31 October 2026 kdenlive 26.08.1-1+stereo3d5+lc1 depended on `libkddockwidgets-qt6-3 (>= 2.2.5)`, which kddockwidgets 2.5.1 replaced with `libkddockwidgets-qt6-4`, so no fresh system, the image included, could install Kdenlive (ORDER 317).
`sparky-os/repo/check-installable.py` finds such packages, and the publisher runs it before signing.

This folder is the edition's binNMU: the published source, rebuilt unchanged against today's testing, with a new `+stereo3dN` and one changelog entry that names the order and the transition.

1. Download the published `.dsc` and every file it names into a folder of your own, and check them against the signed tree's `Sources` (`build.sh` checks the `.dsc` again).
2. Put the earlier `+lc1` builds in a previous folder, with the old library the transition removed, fetched from snapshot.debian.org and checked against the signed index of a day it was still in testing.
   The link and start gate then qualifies the predecessor too and compares the new build with it; without the old library the predecessor no longer resolves and the gate stops.
3. Write `entries/NAME_VERSION.txt`: the first line `NAME (VERSION) unstable; urgency=medium`, then the items; `build-in-container.sh` adds the signature line.
4. Run `build.sh WORK SOURCE_DIR DSC PREVIOUS_DIR ENTRY [PLAIN_OPTION]` with `SPARKY_PUBLISHED_TREE`, `SPARKY_LC_ARCHIVE_DIR` and `SPARKY_BUILD_IMAGE` set, as its header says.
   `PLAIN_OPTION` is the `plain-from-lc.py` option the published source's shape needs: none, `--edition-entry`, `--no-build-depends` or `--lc-successor`.

The container turns the published source back into its plain source (`plain-from-lc.py`), adds the entry, builds the plain source package, prepares the `+lc1` source with the build tree's own toolkit (`lean.debian_prepare`), installs the build dependencies from Debian testing, deb-multimedia and the published tree at the edition's priority, and builds it with the in-build link and start gate; `check-debs` follows.
`depends.tsv` lists the new dependencies, so the library the build now links is visible.

A package whose source must change for the new library (an API break, a removed package with no successor) is not a transition rebuild: give it a change of its own in its recipe.
