# Versions for this recipe; builders must not invent dependency versions.
GTK_VERSION=20261123.1~sparky9~0+lc1   # the Sparky-Stereo-Oxygen themes gain their GTK 2 part (row 59), built with Kubabbar Glass
GLASS_VERSION=20261123~sparky9~0+lc1   # with the GTK successor, so the published Glass pin (= 20261104.1) stops holding it back (row 59)
# The original GTK package introduced Kubabbar-Glass's unchanged gtk-3.0/4.0
# themes and the kubabbar-glass colour-scheme mapping used by both looks.
# They consume those names, not a version-specific ABI, so equality is unnecessary.
GTK_MIN_VERSION=20261014.6~sparky9~0
