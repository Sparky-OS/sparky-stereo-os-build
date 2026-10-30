# Plasma leave-screen recovery actions

Rebuild Debian testing's plasma-workspace 4:6.7.4-2 with two actions in the
Ctrl+Alt+Del leave screen. Task manager launches KDE System Monitor through
KDE's application launcher. Close a frozen window dismisses the greeter and
uses KWin's existing interactive window selection. Power and session actions
are retained. New text uses KDE's translation mechanism.

The patch is from the owning v6.7.4 clone, branch
`partner/kde-desktop-defaults`, commit `398f332ed4`. KDE's package, components
and greeter own the interface; no separate helper is added to the desktop.

Run `build-stereo3d2-from-debian.sh` inside a freshly updated Debian testing container, as the
invoking user. Set `OUT` to the pending package directory and `BUILD_ROOT` to
scratch. Debian's control, rules and existing patches are retained. It builds
source archives and all binaries at `4:6.7.4-2+stereo3d2`. Its nocheck profile
remains separate from kde-ci-local and the frozen-client integration checks.
Apply the edition's existing provenance helper before staging binaries.

The second patch is Nicolas Fella's exact three-line Qt QML linkage fix from
Plasma/6.7, upstream aa326ad917ab59a84f47ca60d3a319acb07b0019. The bare tag
fails to find qqml.h with current KDE CI Frameworks. This fix is identical in
the CI comparison branch and the recovery-action branch (a2b6d4fc62).

The lane uses an owned Debian filesystem and fakeroot for package-manager
identity while the kernel UID remains 1000. Services are blocked by
policy-rc.d. No package is installed on the host.

The edition's look package separately supplies Ctrl+Shift+Esc through a desktop
entry in KDE's supported global-shortcut directory. It retains the upstream
shortcut and the daemon's user override. No application menu entry is added.

The third patch is Tobias Fella's exact QFileInfo include from upstream
08383f4b1df0451480ec68ccf78713bc56507ad4 (bug 526210). The Qt 6.13 control
fails in unchanged iconsmodel.cpp without this include. It is shared by
the control and recovery branches.

## 4:6.7.4-2+stereo3d3 (ORDER 291)

`build.sh WORK PREVIOUS_DIR SOURCE_DIR` builds 4:6.7.4-2+stereo3d3+lc1 through Lean Code, as the kwin recipe does:
the plain +stereo3d2 source (`sparky-os/repo/plain-from-lc.py --no-build-depends --edition-entry` on the published
+stereo3d2+lc1 source, whose single changelog entry also lists the edition's changes) plus `patches/s3-*`, then the
link and start gate against the published +stereo3d2+lc1 builds. The three patches above are in that source already.

`patches/s3-0001` is invent danielcamposramos/plasma-workspace `lock-wallpaper-below-291` (on v6.7.4): the image
wallpaper's TransientImage reads its image again when its texture is released, so that it shows in a new window (the
lock screen moves its wallpaper into a window of its own below the prompt). Test: `testtransientimage`.
