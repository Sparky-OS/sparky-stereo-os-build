# Patches to offer upstream (nothing is sent)

Our packages never modify Pawel's files in place. Each fix below ships as our own copy under our own name, and the look selects it. These patches are the same fixes against the originals, to offer to the owner later (2026-10-02, Daniel's call whether and when).

| Patch | Original | Owner | Our copy |
|---|---|---|---|
| `sddm-sparky-black-qt6.patch` | the SDDM theme `sparky-black` (`-p1`, run inside `/usr/share/sddm/themes/`) | Pawel "pavroo" Pijanowski and Daniel Campos (its `metadata.desktop` credits David Edmundson, pavroo, Daniel Campos; Breeze Qt 5 base) | `/usr/share/sddm/themes/sparky-stereo-black` (package `sparky-stereo-look-sparkyblack`) |
| `sparkyblack-splash-bottomrect.patch` | `org.kde.sparkyblack.desktop/contents/splash/Splash.qml` (`-p1`, run inside the look-and-feel folder) | Daniel's own Sparky black (his Sparky-OS organisation); the file is Marco Martin's KDE splash | same global theme, fixed file inside our package |
| `oxygen-splash-bottomrect.patch` | `org.kde.oxygen/contents/splash/Splash.qml` | KDE, Debian package `plasma-theme-oxygen` (confirmed with `dpkg -S` in a debian:testing container); this one is for KDE, not for Pawel | `org.sparkystereo.desktop` carries the fixed file (our default look) |

## How the owners were found

The host's `/var/lib/dpkg/info/*.list` has no entry for the Sparky black SDDM theme, global theme, Plasma style or Plymouth theme: they were installed by hand on Daniel's build host, so `dpkg -S` cannot name a Sparky package for them. The ownership above comes from the files' own credits. If Pawel's repository ships `sparky-black` inside one of his packages, the patch applies there unchanged.

## What the patches change

- **SDDM sparky-black, Qt 6:** `QtQuick.Controls 1.1` does not exist on Debian testing's Qt 6 SDDM, so the greeter fell back to the embedded theme. Imports lose their versions; `Controls.StackView` and its attached `StackView.status` (Controls 2); `PlasmaCore.ColorScope` and the global `units` become `Kirigami.Theme` and `Kirigami.Units`; `IconItem` becomes `Kirigami.Icon`; `FrameSvgItem` comes from `org.kde.ksvg`; `ButtonRow` becomes a `RowLayout`; `Controls.Action` becomes `Shortcut`; `ProgressBar` uses `from`/`to`; the Caps Lock data engine becomes `KeyboardIndicator.KeyState`; the clock comes from a `Timer`; handlers use `function onLoginFailed()`; the background path is resolved against Main.qml (Qt 6's `SddmComponents` resolves it against itself); anchors inside layouts become `Layout.alignment`; `metadata.desktop` gains `QtVersion=6`. Dropped: the battery line (Plasma 6 has no `powermanagement` data engine).
- **Splashes:** the intro animation also animated a `bottomRect` that the file never defines (the two-rectangle design was reduced to one). Plasma 6 logs `ReferenceError: bottomRect is not defined`. The unused animation is removed.
