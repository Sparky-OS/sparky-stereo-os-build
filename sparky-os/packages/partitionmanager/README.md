# partitionmanager desktop workflows

Rebuild Debian testing's partitionmanager 26.04.0-1 with the owning KDE changes.
Offer a focused removable-drive format request with plain filesystem names and a preserved label.

Run build.sh in a freshly updated Debian testing container as the invoking
user. Set OUT to pending packages and BUILD_ROOT to disposable scratch.
Debian's package split, control and build rules remain in place. The recipe
retains all binary and source archives at 26.04.0-1+stereo3d1. Apply the
edition's existing provenance helper before staging binaries.

The patch comes from the partner/kde-desktop-defaults branch of the owning
KDE repository. Its tests are kept with the source. KDE CI and the native
regression comparison run separately from Debian's nocheck package build.
No package is installed on the host.
