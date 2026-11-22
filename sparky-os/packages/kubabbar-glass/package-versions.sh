# Versions for this recipe; builders must not invent dependency versions.
GTK_VERSION=20261119.1~sparky9~0+lc1
GLASS_VERSION=20261122.1~sparky9~0+lc1
# The original GTK package introduced Kubabbar-Glass's unchanged gtk-3.0/4.0
# themes and the kubabbar-glass colour-scheme mapping used by both looks.
# They consume those names, not a version-specific ABI, so equality is unnecessary.
GTK_MIN_VERSION=20261014.6~sparky9~0
