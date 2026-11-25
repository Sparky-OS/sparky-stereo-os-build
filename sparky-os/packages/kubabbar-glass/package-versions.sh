# Versions for this recipe; builders must not invent dependency versions.
GTK_VERSION=20261125~sparky9~0+lc1   # the GTK themes take the looks' corrected colours (row 68), built with Kubabbar Glass
GLASS_VERSION=20261125~sparky9~0+lc1   # every text at 4.5:1 or more, the close pairs apart (row 68)
# The original GTK package introduced Kubabbar-Glass's unchanged gtk-3.0/4.0
# themes and the kubabbar-glass colour-scheme mapping used by both looks.
# They consume those names, not a version-specific ABI, so equality is unnecessary; since row 68 the Glass look's
# colours and its GTK theme's are corrected together, so the minimum is the GTK build that carries them.
GTK_MIN_VERSION=20261125~sparky9~0
