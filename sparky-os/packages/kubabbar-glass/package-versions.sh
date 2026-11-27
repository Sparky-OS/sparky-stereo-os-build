# Versions for this recipe; builders must not invent dependency versions.
GTK_VERSION=20261127~sparky9~0+lc1   # Kubabbar Glass 9's GTK 4 scroll arrows and always-visible bars (row 147 milestone 3); before: its GTK 2, 3 and 4 themes
GLASS_VERSION=20261127~sparky9~0+lc1   # the SDDM theme's labels and the dock's Stereo Browser (row 945); also the menu bar package
# The original GTK package introduced Kubabbar-Glass's unchanged gtk-3.0/4.0
# themes and the kubabbar-glass colour-scheme mapping used by both looks.
# They consume those names, not a version-specific ABI, so equality is unnecessary; since row 68 the Glass look's
# colours and its GTK theme's are corrected together, so the minimum is the GTK build that carries them.
GTK_MIN_VERSION=20261125~sparky9~0
GLASS9_VERSION=20261127~sparky9~0+lc1   # Kubabbar Glass 9 milestone 3: GTK 4's scroll arrows, GTK's bars always visible, the dock's Stereo Browser (row 147)
GTK9_MIN_VERSION=20261127~sparky9~0   # the sparky-stereo-gtk that carries Kubabbar Glass 9's GTK themes with GTK 4's steppers and the bars always visible
GTK4_STEPPERS_MIN_VERSION=4.24.1+ds-1+stereo3d4~   # the edition's GTK 4 whose scrollbars have steppers a theme can turn on (sparky-os/packages/gtk4)
MENUBAR_MIN_VERSION=20261014.6~sparky9~1   # the menu bar package that carries the family's launcher logo
KVANTUM_MIN_VERSION=1.1.8-1+stereo3d1~   # the edition's Kvantum, which knows scroll_arrows_together (sparky-os/packages/kvantum)
