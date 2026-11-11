# Exercise the actual Calamares font job without a disk installation

Use a private KWin Wayland session and an already copied disposable target made from the published-repository live root.
The test-only `targetproof` job registers `CORE_FONTS_TEST_TARGET` as rootMountPoint and `CORE_FONTS_TEST_LOCALE` as localeConf.LANG, the values the omitted mount/locale jobs normally supply. It supplies no font licence answer.

Use an isolated Calamares data/config directory with the installed qml and branding directories, a modules-search entry pointing here plus `local`, and the installed `shellprocess-corefonts.conf` copied byte for byte.
An abbreviated exec sequence of `targetproof`, `shellprocess@corefonts` and a shellprocess that writes a completion marker runs the actual production font step. A final `finished` page must set restartNowMode to never.
Start `calamares -d -c CONFIG_DIRECTORY`; beginning at the exec phase starts this narrow job sequence automatically.
Drive the real KDE dialogs with Wayland input, retain the compositor captures and Calamares log, check the following completion marker, target Arial and dpkg state, and recheck that the live root has no font installer or font data.
This proves the font job join, not partitioning, filesystem extraction, bootloader, kernel or a complete installation wizard.
