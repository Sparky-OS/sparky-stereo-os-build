# Plasma leave-screen recovery actions

Rebuild Debian testing's plasma-workspace 4:6.7.4-2 with two actions in the
Ctrl+Alt+Del leave screen. Task manager launches KDE System Monitor through
KDE's application launcher. Close a frozen window dismisses the greeter and
uses KWin's existing interactive window selection. Power and session actions
are retained. New text uses KDE's translation mechanism.

The patch is from the owning v6.7.4 clone, branch
`partner/kde-desktop-defaults`, commit `398f332ed4`. KDE's package, components
and greeter own the interface; no separate helper is added to the desktop.

Run `build.sh` inside a freshly updated Debian testing container, as the
invoking user. Set `OUT` to the pending package directory and `BUILD_ROOT` to
scratch. Debian's control, rules and existing patches are retained. It builds
source archives and all binaries at `4:6.7.4-2+stereo3d1`. Its nocheck profile
remains separate from kde-ci-local and the frozen-client integration checks.
Apply the edition's existing provenance helper before staging binaries.

The lane uses an owned Debian filesystem and fakeroot for package-manager
identity while the kernel UID remains 1000. Services are blocked by
policy-rc.d. No package is installed on the host.

The edition's look package separately supplies Ctrl+Shift+Esc through a desktop
entry in KDE's supported global-shortcut directory. It retains the upstream
shortcut and the daemon's user override. No application menu entry is added.
