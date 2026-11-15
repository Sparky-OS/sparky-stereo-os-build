# A convertible and a small dense panel start right (ORDER 567)

Three defaults the edition sets by itself, each with the person's own choice kept:

1. **The first scale of a built-in panel comes from its real size**, and a full HD panel of about 13 to 14 inches starts at 125 % at least: kwin 4:6.7.4-2+stereo3d55 (`../kwin/build-55.sh`, patches `../kwin/patches/s55-*`), kept in every later KWin.
2. **A computer with a touch screen of its own gets KDE's on-screen keyboard as its virtual keyboard**, in the session's language: `../sparky-stereo-hardware` 0.1.27. **It shows only in tablet mode** unless the person switches that off: kwin 4:6.7.4-2+stereo3d57 (`../kwin/prepare-source-57.sh`, `../kwin/overlay-stereo3d57`), on top of ORDER 568's +56; KWin merge request 8592 by Luca Tramonti, open upstream, adapted to 6.7.4.
3. **While in tablet mode every panel is on automatic hide**, and each goes back to the person's own setting afterwards: plasma-workspace 4:6.7.4-2+stereo3d8 and the switch in plasma-desktop 4:6.7.4-1+stereo3d4, built here.

Design followed (Daniel's words, as recorded):
- 2026-10-08: "the default being set not waiting for the user like stock debian/kde".
- 2026-11-14, on the keyboard: "addition to our script is detect this type of thing to enable on screen keyboard on tablet mode".
- 2026-11-14, on the panel: "when in tablet mode only, can we make the taskbar autohide?"; "this is the distro defaults ok?".
- 2026-11-14, on the scale: "it's screen is full hd, but 14' in size, so at least 125% scale as default"; "it should use the correct data".

## Files

- `patches/plasma-workspace-panels-hide-in-tablet-mode.patch`: the shell follows KWin's `org.kde.KWin.TabletModeManager`; a panel keeps the visibility mode in force apart from the person's own choice, which is the one saved and the one scripting reads.
- `patches/plasma-desktop-tablet-mode-panels-switch.patch`: General Behavior, Touch, "In Tablet Mode: Hide panels automatically" (`plasmarc`, `[TabletMode] HidePanels`, on by default).
- `../../translations/plasma-desktop-tablet-mode-panels.po.patch`: the switch in the nine translated languages, last in plasma-desktop's series.
- `changelog/*.items`: the changelog items, one paragraph per item.
- `next-source.sh PACKAGE PUBLISHED.dsc OUT`: the next +lc1 source of plasma-workspace or plasma-desktop (`repo/lc-successor.py --in-place --overlay`): the code patch appended to the published series, the new translation patch last.
- `round.sh WORK PUBLISHED_TREE ARCHIVE_DIR [STEP...]`: both builds through `../depth-source/build.sh` (Lean Code, the link and start gate, `lean.release check-debs`).

## Why each piece is where it is

- The first scale is KWin's (`OutputConfigurationStore::chooseScale`), and so is the screen's physical size (`utils/edid.cpp`). Upstream had already found the largest cause, input devices not yet listed when the first configuration is made (KWin merge request 10327, Xaver Hugl), carried as it is.
- The panel's hiding is the shell's (`PanelView`). A session service that rewrites each panel's saved setting, the hand-made form that was tried first, has to remember what it changed and loses that when the session ends in tablet mode; in the shell nothing is written, so there is nothing to restore.
- The keyboard default is a system default that only some computers get, so it cannot be a file in `/etc/xdg` for everyone, and it must not be a line in the person's own `kwinrc`: KConfig removes a key that is set back to "no value" when no system default exists (`KCoreConfigSkeleton::ItemString::writeConfig`), so a person who chose None in System Settings would get the keyboard back at the next login. A folder in front of `XDG_CONFIG_DIRS`, added by the session's environment script only on a computer with a touch screen of its own, is read below the person's file.
- "A touch screen of its own" is a touch screen and a built-in panel, whatever the chassis type and the switches say: KWin puts such a computer in tablet mode by a switch, by itself when no mouse or touchpad is left beside the touch screen, or by the Touch Mode setting. A slider convertible that reports itself as a notebook, with no tablet-mode switch, is a fixture of the hardware package's test.
