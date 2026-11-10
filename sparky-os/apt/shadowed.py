# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/09
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/10 (ORDER 458b)
"""The deb-multimedia packages that ship files of one of our packages under another name (ORDER 458).

make-only-ours.py blocks every build of ours by NAME, so deb-multimedia's libmlt-data never installs. deb-multimedia ships MLT 7 under the
names libmlt-7-7, libmlt7-data, libmlt7-dev and so on, and FFmpeg 6's development files as libavcodec-6-dev and the like: another name, the
same files. Without a pin of their own they install beside ours (libmlt7-data has Replaces: libmlt-data and no Conflicts, so dpkg lets it
take over our files and `dpkg -S /usr/share/mlt-7` names both) or take ours out (Conflicts: libmlt7).
Debian Policy 7.6.1: "if the overwriting package declares that it Replaces the one containing the file being overwritten, then dpkg will
replace the file from the old package with that from the new. The file will no longer be listed as 'owned' by the old package".

SHADOWED_BY_DMO: deb-multimedia's package -> (our package it shadows, the reason). repo/find-shadowing.py finds the list from the Contents
files of the two repositories and exits 1 for a pair that is in neither list; each entry was found that way and its relation read in
deb-multimedia's Packages index (forky, 9 November 2026). Only the shared PATHS count: a shared directory is not a file.
PROGRAMS_ON_SHADOWED (below): their dependents. NOT_SHADOWS: a pair that shares a path but cannot shadow, with the reason (checked by running apt and dpkg, tests/shadowed).
"""
SHADOWED_BY_DMO = {
    'libmlt7-data': ('libmlt-data', 'Replaces: libmlt-data, no Conflicts: it installs beside ours and owns its 400 files under /usr/share/mlt-7 (MLT 7.42 data under our 7.40)'),
    'libmlt-7-7': ('libmlt7', 'Conflicts and Replaces: libmlt7: apt takes ours out for it when a dmo program (shotcut, flowblade, synfig) asks for it'),
    'libmlt++-7-7': ('libmlt++7', 'Conflicts and Replaces: libmlt++7, the same files under another name'),
    'libmlt7-dev': ('libmlt-dev', 'ships /usr/include/mlt-7/framework and the .so link of our libmlt-dev'),
    'libmlt++7-dev': ('libmlt++-dev', 'ships /usr/include/mlt-7/mlt++ of our libmlt++-dev'),
    'melt7': ('melt', 'Conflicts and Replaces: melt, ships /usr/bin/melt and melt-7'),
    'python3-mlt7': ('python3-mlt', 'ships mlt7.py and _mlt7 of our python3-mlt with no Conflicts: dpkg refuses to unpack it beside ours, apt would still plan it'),
    'libavcodec-6-dev': ('libavcodec-dev', 'FFmpeg 6.1 development files: Conflicts and Replaces libavcodec-dev, the same .so and .a names'),
    'libavdevice-6-dev': ('libavdevice-dev', 'as libavcodec-6-dev'),
    'libavfilter-6-dev': ('libavfilter-dev', 'as libavcodec-6-dev'),
    'libavformat-6-dev': ('libavformat-dev', 'as libavcodec-6-dev'),
    'libavutil-6-dev': ('libavutil-dev', 'as libavcodec-6-dev'),
    'libswresample-6-dev': ('libswresample-dev', 'as libavcodec-6-dev'),
    'libswscale-6-dev': ('libswscale-dev', 'as libavcodec-6-dev'),
}
NOT_SHADOWS = {
    ('libmlt7-perl', 'libmlt-perl'): ('ORDER 458b: our MLT builds the Perl bindings (mlt.pm, mlt.so) that deb-multimedia ships as libmlt7-perl against its libmlt-7-7, which the pins keep out; '
                                      'ours Conflicts with and Replaces it, so apt swaps it for ours and dpkg never meets two owners of the file; it cannot be installed beside ours (tests/shadowed/bindings.sh). '
                                      'Its libmlt7-ruby3.3 shares no path with our libmlt-ruby (mlt.so is in the Ruby archdir there and in the vendor architecture directory here) and is swapped by the same Conflicts and Replaces'),
    ('oss4-dev', 'linux-libc-dev'): 'shares /usr/include/linux/soundcard.h with the kernel headers (ours and Debian\'s alike) and has no Replaces: dpkg refuses the unpack, '
                                    'so it can never own the file; it is deb-multimedia\'s own file overlap, not our files under another name',
}
# deb-multimedia's programs that depend on the shadowing packages (found from their Depends in deb-multimedia's Packages): with those blocked, their
# newer deb-multimedia build (1:26.10.30-dmo1 beats Debian's 26.9.27+ds-1 by its epoch) stays the candidate and cannot be installed, so apt
# says "Unable to satisfy dependencies" instead of taking Debian's build, which links ours (Debian's shotcut Depends: libmlt7 (>= 7.40.0)).
# Blocked too, with every binary of their sources that Debian also has (a Debian program needs its own data and libraries at its exact
# version, which the other build's epoch would outrank). kdenlive and krita are ours already, by name.
PROGRAMS_ON_SHADOWED = {
    'shotcut': 'depends on melt7, libmlt-7-7 and libmlt++-7-7; Debian has it (26.9.27+ds-1, linked to libmlt7)',
    'shotcut-data': 'the data of shotcut: Debian\'s shotcut needs its own at its exact version',
    'flowblade': 'depends on python3-mlt7 and libmlt7-data; Debian has it',
    'synfig': 'the source of synfigstudio and libsynfig0t64, which depend on libmlt++-7-7; Debian has it',
    'synfig-examples': 'as synfig',
    'synfigstudio': 'depends on libmlt++-7-7; Debian has it',
    'libsynfig0t64': 'depends on libmlt++-7-7; Debian has it',
    'libsynfig-dev': 'depends on libmlt++7-dev; Debian has it',
}
