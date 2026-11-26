# Versions for this recipe; builders must not invent dependency versions.
GTK_VERSION=20261125~sparky9~0+lc1   # the GTK themes take the looks' corrected colours (row 68), built with Kubabbar Glass
GLASS_VERSION=20261126~sparky9~0+lc1   # the loading screen and Sparky Black's translucency (row 125); also the menu bar package
# The original GTK package introduced Kubabbar-Glass's unchanged gtk-3.0/4.0
# themes and the kubabbar-glass colour-scheme mapping used by both looks.
# They consume those names, not a version-specific ABI, so equality is unnecessary; since row 68 the Glass look's
# colours and its GTK theme's are corrected together, so the minimum is the GTK build that carries them.
GTK_MIN_VERSION=20261125~sparky9~0
GLASS9_VERSION=20261126~sparky9~0+lc1   # Kubabbar Glass 9, the classic controls of the family (queue row 147)
KVANTUM_MIN_VERSION=1.1.8-1+stereo3d1~   # the edition's Kvantum, which knows scroll_arrows_together (sparky-os/packages/kvantum)
