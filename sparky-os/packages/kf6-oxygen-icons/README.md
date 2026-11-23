# kf6-oxygen-icons: the Oxygen icon theme with its icon cache

Debian's `oxygen-icon-theme` 5:6.32.0-1 (source `kf6-oxygen-icons`) installs with no `icon-theme.cache` in `/usr/share/icons/oxygen`.
`gtk-update-icon-cache` rejects the cache it generates ("The generated cache was invalid") while three entries whose names contain a space are present: `simbolicActions/22x22/actions/go-first copy.svg`, the same at 24x24, and a symlink to it at 48x48.
Without the cache every GTK program, and KIconThemes since it reads GTK's cache, looks the theme's icons up folder by folder.

KDE removed the three entries after the 6.32.0 tag: commit [5bfe4322](https://invent.kde.org/frameworks/oxygen-icons/-/commit/5bfe432258fff393d65442ae275f3126df90de8c) by Nuno Pinheiro, 2026-11-16, "Remove duplicate go-first icons that invalidate GTK cache" ([KDE bug 528955](https://bugs.kde.org/528955); [Debian bug 1154120](https://bugs.debian.org/1154120), where the cause and this patch are recorded).
This recipe is Debian's source with that one commit, carried unchanged (`patches/upstream-01-5bfe4322.patch`), at `5:6.32.0-1+sparky1+lc1`.

## When it is retired

When Debian's own fix reaches testing: a Debian `kf6-oxygen-icons` above 5:6.32.0-1 (an upload carrying the patch, or a Frameworks release with upstream's commit) sorts above ours, and the edition's repository drops this source at the next round.
Check before each round: `apt-cache policy oxygen-icon-theme` on Debian testing, and `/usr/share/icons/oxygen/icon-theme.cache` present after installing Debian's build.

## Build

`build.sh` runs inside a clean Debian testing container at an instant that has 5:6.32.0-1 (the stage of queue row 850b used snapshot.debian.org 20261121T150000Z), with Debian's unmodified `.dsc` named by `SOURCE_DSC` (its SHA-256 is checked) and the Lean Code toolkit, as the other carried recipes run.
