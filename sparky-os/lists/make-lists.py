#!/usr/bin/env python3
# Sparky Stereo OS: the edition's package lists, checked against what apt offers.
# Writes one <name>.list per group (one package per line, comments for context) and
# MISSING.md for every wanted package apt does not have (to package, or for APTus).
# Run on a system with the edition's apt sources (Debian testing, Sparky, deb-multimedia).
import glob, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, '..', 'data')
sys.path.insert(0, os.path.join(HERE, '..', 'config'))
import local_config

# Every package the edition's sources offer (Debian testing, Sparky, deb-multimedia; not the
# vendor repositories of this system), by architecture (amd64, all, i386 when multiarch is on).
SOURCES = ('deb.debian.org_', 'repo.sparkylinux.org_', 'www.deb-multimedia.org_', 'deb-multimedia.org_')
available = set()
for f in glob.glob('/var/lib/apt/lists/*_Packages'):
    if not os.path.basename(f).startswith(SOURCES):
        continue
    arch = 'i386' if 'binary-i386' in f else ''
    for line in open(f, errors='replace'):
        if line.startswith('Package: '):
            p = line[9:].strip()
            available.add(p + (':i386' if arch else ''))

groups = {}
missing = {}

def group(name, title, wanted):
    have, lack = [], []
    for p in wanted:
        (have if p in available else lack).append(p)
    groups[name] = (title, sorted(set(have)))
    if lack:
        missing[name] = sorted(set(lack))

# The KDE edition's ISO (the base we build on).
base = set()
for l in open(os.path.join(DATA, 'sparkylinux-2026.09-x86_64-kde.txt'), errors='replace'):
    if l.startswith('ii'):
        base.add(l.split()[1].split(':')[0])

# Dedup (Daniel, 2026-10-02): one tool per task, KDE's where it covers the task
# (data/dedup.tsv says, for each package taken out, what does its task instead).
dedup = {}
for l in open(os.path.join(DATA, 'dedup.tsv')):
    if l.startswith('#') or not l.strip():
        continue
    p, action, instead, why = l.rstrip('\n').split('\t')
    dedup[p] = (action, instead, why)

# Packages of the KDE edition replaced by the dedup.
# systemd-timesyncd: the edition keeps time with chrony (sparky-stereo-time)
# vlc, vlc-bin, vlc-plugin-qt, vlc-plugin-skins2: the regular player; VLC Stereo (Provides: vlc) is the edition's VLC
#   (Daniel, 2026-10-16: "swap current vlc for the stereo version"); libvlc5, libvlccore9 and the plugins stay for
#   the programs that use them (Phonon's VLC backends, kalarm, freetuxtv)
base_remove = ['thunderbird', 'skanlite', 'blueman', 'systemd-timesyncd', 'vlc', 'vlc-bin', 'vlc-plugin-qt', 'vlc-plugin-skins2'] + sorted(p for p in base if p.startswith('thunderbird-l10n-'))

# 1. Applications beyond the KDE edition, chosen from Daniel's system: those from Debian or
# Sparky (vendor and local ones go through APTus), deduplicated, plus the KDE tools the dedup
# chose that neither has. The edition's selection is data/apps-selection.list. The system's own
# application list (package<TAB>origin) stays private: when SPARKY_PERSONAL_APPS in the local
# configuration names it, the selection is made from it again and data/apps-selection.list is
# rewritten.
SELECTION = os.path.join(DATA, 'apps-selection.list')
personal = local_config.VALUES.get('SPARKY_PERSONAL_APPS')
if personal:
    apps = [l.split('\t')[0] for l in open(personal)
            if l.rstrip('\n').split('\t')[1] in ('debian', 'sparky')]
    apps = [p for p in apps if p not in dedup]
    with open(SELECTION, 'w') as f:
        f.write('# Applications the edition adds beyond the KDE edition, chosen from Daniel\'s system and\n'
                '# deduplicated (' + str(len(set(apps))) + ' packages; written by lists/make-lists.py)\n')
        f.write('\n'.join(sorted(set(apps))) + '\n')
else:
    apps = [l.strip() for l in open(SELECTION) if l.strip() and not l.startswith('#')]
apps = [p for p in apps if p not in dedup]
group('apps', "Applications beyond the KDE edition (Daniel's, deduplicated)", apps + [
    'dolphin', 'konsole', 'kdenlive', 'skanpage', 'subtitlecomposer', 'neochat', 'qpwgraph',
    'libreoffice-kf6', 'libreoffice-draw', 'kdenetwork-filesharing', 'kio-fuse',
    'coolercontrol',   # fans and pumps (GPL-3; its repository is the vendor's: to package)
    # stereo editing and 3D work (Daniel, 2026-10-02): ours to package first, then Debian's
    'stereophotoview', 'sview', 'blender', 'freecad', 'paraview', 'hugin-tools', 'libimage-exiftool-perl',
    'showfoto',   # digiKam's photo editor, stereo (2026-10-10); the digikam package does not pull it in
    'handbrake',   # the video transcoder (Daniel, 2026-10-11: "it will be included, of course"); deb-multimedia's, stereo version planned
])

# 1b. Film and visual effects: the studios' own open projects (Daniel, 2026-10-14: "follow those that have repos, orgs
# and star the open initiatives - map and add to our to include in the distro"). Disney Animation (Ptex, Partio, SeExpr via
# Krita's KSeExpr), Pixar (OpenUSD, OpenSubdiv) and the Academy Software Foundation (OpenEXR, OpenColorIO, OpenImageIO,
# OpenVDB, OpenShadingLanguage, MaterialX, OpenTimelineIO, OpenRV, xSTUDIO). OpenRV first: RV, the industry's review
# player, shows stereo (anaglyph, side by side, scanline, checker, quad-buffered).
group('film', 'Film and visual-effects open stack', [
    'openexr', 'openimageio-tools', 'opencolorio-tools', 'opensubdiv-tools', 'libopenvdb-tools',
    'openrv', 'xstudio', 'openusd', 'materialx', 'opentimelineio', 'openshadinglanguage', 'ptex', 'partio',
])

# 2. Games: SteamOS-like, the chosen GameOver games, KDE's games, three well-known additions.
group('games', 'Games', [
    'extremetuxracer', 'warzone2100', 'widelands', 'luanti', 'openarena', 'ioquake3',
    'armagetronad', 'gl-117', 'billard-gl', 'xmoto', 'teeworlds', 'chromium-bsu', 'blobby',
    'lbreakouthd', 'liquidwar', 'netpanzer', 'freedroid',
    'supertuxkart', '0ad', 'openttd',
    'kdegames', 'knights', 'gnuchess',
    # Daniel's, from his applications (the dedup sent them here)
    'flightgear', 'torcs', 'ufoai', 'd1x-rebirth', 'd2x-rebirth', 'quake3',
    'game-data-packager-runtime',
])

# 3. Gaming tools (Steam Gaming Mode and gamescope come from the stereo package).
group('gaming', 'Gaming tools', [
    'steam-installer', 'steam-devices', 'gamemode', 'mangohud', 'goverlay', 'lutris',
    'heroic', 'wine', 'wine64', 'winetricks',
    # wine32:i386 is not in Debian testing (2026-10-02): check by running a 32-bit Windows
    # program whether Wine 10's WoW64 mode covers it before adding anything
])

# 4. 3D emulation (APTus section "3D emulation": users install it from APTus Stereo AppCenter; the development VM installs it for testing and prepack.sh --final purges it, so it never reaches the ISO): emulators with a
# stereo output, which KWin shows in the display's 3D mode.
group('emulation-3d', '3D emulation', [
    'dolphin-emu', 'mame', 'mednafen', 'retroarch', 'libretro-beetle-vb',
    'azahar', 'rpcs3',
])

# 5. Runtimes third-party programs and games expect, as Windows ships its own.
boost = sorted(p for p in available if p.startswith('libboost') and '1.90.0' in p
               and not p.endswith('-dev') and ':i386' not in p)
group('runtimes', 'Runtimes', boost + [
    'mono-runtime', 'mono-devel', 'default-jre', 'python3',   # mono-complete is gone from Debian
    'libsdl2-2.0-0', 'libsdl3-0', 'libopenal1', 'libvulkan1', 'vulkan-tools',
    'libqt5widgets5t64', 'libqt6widgets6',
    'gstreamer1.0-plugins-good', 'gstreamer1.0-plugins-bad', 'gstreamer1.0-plugins-ugly',
    'gstreamer1.0-libav', 'ffmpeg',
    'imagemagick',   # the convert/magick command that scripts and programs look for (ImageMagick 7; Daniel's 6.q16 is gone from forky)
    'libc6:i386', 'libgl1:i386', 'libvulkan1:i386', 'mesa-vulkan-drivers:i386', 'libsdl2-2.0-0:i386',
])

# 6. Languages: everything Steam supports, for the applications the edition ships.
steam = {
    'ar': ['ar'], 'bg': ['bg'], 'zh-CN': ['zh-cn'], 'zh-TW': ['zh-tw'], 'cs': ['cs'],
    'da': ['da'], 'nl': ['nl'], 'en': ['en-gb', 'en-za', 'en-us'], 'fi': ['fi'],
    'fr': ['fr'], 'de': ['de', 'de-de'], 'el': ['el'], 'hu': ['hu'], 'id': ['id'],
    'it': ['it'], 'ja': ['ja'], 'ko': ['ko'], 'ms': ['ms'], 'no': ['nb', 'nb-no', 'nn', 'nn-no', 'no'], 'pl': ['pl'],
    'pt': ['pt', 'pt-pt'], 'pt-BR': ['pt-br'], 'ro': ['ro'], 'ru': ['ru'], 'es': ['es', 'es-es'],
    'es-419': ['es-mx', 'es-ar', 'es-cl', 'es-419'], 'sv': ['sv', 'sv-se'], 'th': ['th'],
    'tr': ['tr'], 'uk': ['uk'], 'vi': ['vi'],
}
# (KDE programs carry their translations in their own packages; Thunderbird is not shipped)
prefixes = ['firefox-esr-l10n-', 'libreoffice-l10n-', 'libreoffice-help-',
            'hunspell-', 'hyphen-', 'mythes-']
langs = []
for codes in steam.values():
    for c in codes:
        for pre in prefixes:
            if pre + c in available:
                langs.append(pre + c)
group('languages', 'Languages (all of Steam\'s)', langs + [
    'locales-all', 'fonts-noto-core', 'fonts-noto-cjk', 'fonts-noto-cjk-extra', 'fonts-thai-tlwg',
    # input methods: Fcitx 5, KDE's recommendation on Wayland
    'fcitx5', 'kde-config-fcitx5', 'fcitx5-frontend-gtk3', 'fcitx5-frontend-gtk4', 'fcitx5-frontend-qt6',
    'fcitx5-mozc', 'fcitx5-hangul', 'fcitx5-chinese-addons', 'fcitx5-chewing', 'fcitx5-unikey', 'fcitx5-m17n',
])

# 7. Hardware: firmware and the tools the hardware setup uses (DKMS drivers only when found).
group('hardware', 'Hardware support', [
    'laptop-detect', 'isenkram-cli', 'discover', 'nvidia-detect', 'lm-sensors',   # fans: CoolerControl
    'thermald', 'power-profiles-daemon', 'fwupd', 'inxi', 'hw-probe', 'bluetooth',
    'firmware-linux', 'firmware-linux-nonfree', 'firmware-misc-nonfree', 'firmware-amd-graphics',
    'firmware-nvidia-graphics',   # nouveau's firmware, GSP included: without it Turing and newer have no GR engine (VM test 2026-10-02); firmware-nvidia-gsp is NVIDIA's own driver firmware, not this
    'firmware-realtek', 'firmware-iwlwifi', 'firmware-atheros', 'firmware-brcm80211',
    # The rest of Debian's live firmware task and forky's desktop and laptop firmware (Daniel,
    # 2026-10-05: the ISO ships drivers and firmware as far as licences allow, since a machine
    # without Wi-Fi cannot download its Wi-Fi driver). firmware-linux does not pull these.
    'firmware-mediatek',   # MT7921, MT7922, MT7902 and others, Wi-Fi and Bluetooth
    'bluez-firmware', 'firmware-ipw2x00',   # Debian's live task (non-free-firmware)
    'firmware-intel-graphics', 'firmware-intel-misc',   # Intel GuC/HuC and Intel Bluetooth and misc
    'firmware-cirrus',   # laptop sound amplifiers
    'firmware-intel-sound', 'firmware-sof-signed', 'amd64-microcode', 'intel-microcode',
    'mesa-vulkan-drivers', 'mesa-va-drivers', 'intel-media-va-driver', 'vainfo', 'vdpauinfo',
    'evdi-dkms', 'displaylink-driver',
    'memtest86+',   # the ISO's Memory Test boot entry (Daniel and Paweł, 2020)
    'debconf-kde-helper',   # apt and dpkg questions as KDE dialogs
    'libfdk-aac2', 'pipewire-bluez5-codec-aac',   # Bluetooth AAC (ours: sparky-os/packages)
    'xpadneo',   # Xbox controllers over Bluetooth (DKMS; ours to package)
    # ACPI and DKMS, which most distributions leave out (Daniel, 2026-10-07; on his own lists since 2020).
    # The kernel's headers come with the stereo stack (linux-headers-sparky-stereo, make-meta.py).
    'dkms',   # out-of-tree drivers rebuilt for every new kernel (NVIDIA open modules, xpadneo, evdi)
    'acpi', 'acpid', 'acpitool',   # battery, thermal and ACPI event tools (kacpimon comes with acpid)
    'acpi-call-dkms',   # ACPI method calls: battery thresholds on older ThinkPads, hybrid-graphics power switching
    'acpi-support',   # hotkey scripts; check in the VM that the power button acts once (logind and PowerDevil handle it too)
])

# 7b. Installed by the hardware setup only when it finds the hardware (not in the base build).
group('hardware-found', 'Hardware support installed when the hardware is found', [
    'nvidia-settings',   # with the NVIDIA driver, when an NVIDIA card is found
    # VA-API decode on NVIDIA through NVDEC, works with DRM, X11 and Wayland displays. Never
    # vdpau-va-driver (VDPAU bridge, X11 only): it segfaults any VA-API probe on a DRM display
    # (Discord's encoder helper, `vainfo --display drm`; measured on Daniel's machine 2026-10-07).
    'nvidia-vaapi-driver',
])

# 8. System: apps from Flathub, containers, Android, snapshots. No zram (Daniel, 2026-10-10): the swap is an emergency swap
# file, on only under memory pressure.
group('system', 'System', [
    'dosfstools', 'exfatprogs', 'ntfs-3g',
    'flatpak', 'plasma-discover-backend-flatpak', 'distrobox', 'waydroid', 'btrfs-progs',
    'timeshift', 'synaptic',   # snapshots: Timeshift (with grub-btrfs)
    'grub-btrfs', 'scx-scheds', 'ananicy-cpp', 'sunshine', 'protonup-qt', 'hhd', 'decky-loader',
])

# 9. Look: Oxygen dark default (Daniel's QPlatinum and Sparky black come as packages of ours).
# The whole Oxygen suite (Daniel, 2026-10-14: "we need the entire oxygen suite from kde", after a Debian update dropped
# Oxygen's Qt5 style configuration on his laptop): the Plasma look, icons, cursors, window decoration, the Qt6 and Qt5
# styles (Qt5 programs still exist), the GTK2 engine, the fonts, the sounds and the wallpapers. KDE's oxygen-gtk for
# GTK3 is not in Debian: ours to package (MISSING.md).
group('look', 'Look', [
    'plasma-theme-oxygen', 'oxygen-icon-theme', 'oxygencursors', 'kde-style-oxygen-qt6',
    'kwin-decoration-oxygen', 'qt6ct',
    'kde-style-oxygen-qt5', 'gtk2-engines-oxygen', 'fonts-oxygen', 'oxygen-sounds', 'oxygen-wallpapers',
    'oxygen-gtk3',
])

# 10. Developer: code and game engines (Daniel, 2026-10-16: "we must start collecting two extra meta packages - dev, for
# code and game engines, and Stereo OS dev - to ease pople that use it and want to migrate, just install the meta and start
# developing"). The whole list goes into task-sparky-stereo-developer (make-meta.py), with our builds from roles.tsv.
# KDE's own tools first; one tool per task where KDE's covers it (Kompare and KDiff3 instead of Meld, KInfoCenter instead
# of GPU Viewer); Karton, KDE's virtual machine manager, is our build and still a pre-alpha, so virt-manager stays beside
# it until Karton covers the task; both container engines, since Docker and Podman give different
# results (a daemon or rootless). Game engines: every general engine and framework Debian testing carries, and the
# moddable engines with a community of standalone games; engines that only run one commercial game's data are the
# gamer's (notes/developer-tasks.md has the survey and each one's stereo state).
kf6_dev = sorted(p for p in available if p.startswith('libkf6') and p.endswith(('-dev', '-dev-bin', '-dev-tools')))
qt6_dev = sorted(p for p in available if p.startswith('qt6-') and p.endswith(('-dev', '-dev-tools', '-private-dev', '-doc'))
                 and ':i386' not in p)
pyside6 = sorted(p for p in available if p.startswith('python3-pyside6.') and ':i386' not in p)
group('developer', 'Developer: code and game engines', kf6_dev + qt6_dev + pyside6 + [
    # KDE's development tools (kdesdk: Kate, Kompare, KCachegrind, Lokalize, Okteta, Umbrello, KAppTemplate and the rest)
    'kdevelop', 'kdevelop-dev', 'kdevelop-php', 'kdevelop-python', 'kdevelop-pg-qt', 'kate', 'kdesdk',
    'kcachegrind-converters', 'massif-visualizer', 'heaptrack', 'heaptrack-gui', 'kdiff3', 'kdesvn', 'kdesvn-kio-plugins',
    'cervisia', 'clazy', 'plasma-sdk', 'kirigami-gallery', 'kapidox6', 'extra-cmake-modules', 'extra-cmake-modules-doc',
    'gammaray', 'gammaray-plugin-quickinspector', 'gammaray-plugin-waylandinspector', 'kdebugsettings',
    'hotspot',   # KDAB's perf front end: in unstable only (2026-10-16)
    'kommit',    # KDE's Git client: not in Debian (2026-10-16)
    # KDE Frameworks and Plasma development files (the KF6 -dev packages come from the pattern above)
    'kpackagetool6', 'kirigami-addons-dev', 'libkirigami-dev', 'libplasma-dev', 'libplasma5support-dev',
    'libplasmaactivities-dev', 'libplasmaactivitiesstats-dev', 'libkdecorations3-dev', 'liblayershellqtinterface-dev',
    'kwayland-dev', 'libkpipewire-dev', 'libkscreen-dev', 'libksysguard-dev', 'plasma-workspace-dev', 'plasma-desktop-dev',
    'plasma-widgets-addons-dev', 'kwin-dev', 'libkdegames6-dev', 'libqaccessibilityclient-qt6-dev',
    'libpolkit-qt6-1-dev', 'libqca-qt6-dev', 'qcoro-qt6-dev', 'qtkeychain-qt6-dev', 'libkf6pulseaudioqt-dev',
    'libkdsoap-dev', 'libkgapi-dev', 'plasma-wayland-protocols',
    # Qt 6 (the -dev, -private-dev, -dev-tools and documentation packages come from the pattern above)
    'qtcreator', 'qtcreator-doc', 'designer-qt6', 'linguist-qt6', 'assistant-qt6', 'qt6-l10n-tools',
    'qt6-documentation-tools', 'qdbus-qt6', 'qmlscene-qt6', 'qt6-qmltooling-plugins', 'python3-pyqt6', 'pyqt6-dev-tools',
    'pyside6-tools',
    # C and C++: compilers, debuggers, build systems, analysers, profilers
    'build-essential', 'gcc', 'g++', 'clang', 'clangd', 'clang-format', 'clang-tidy', 'clang-tools', 'lld', 'lldb',
    'llvm', 'llvm-dev', 'libclang-dev', 'gdb', 'gdb-multiarch', 'gdbserver', 'valgrind', 'cmake', 'cmake-curses-gui',
    'cmake-qt-gui', 'ninja-build', 'meson', 'make', 'autoconf', 'automake', 'libtool', 'pkgconf', 'ccache', 'sccache',
    'mold', 'bear', 'cppcheck', 'iwyu', 'strace', 'ltrace', 'rr', 'linux-perf', 'uftrace', 'doxygen', 'graphviz',
    'cscope', 'universal-ctags', 'global', 'gcovr', 'lcov', 'libgtest-dev', 'libgmock-dev', 'catch2',
    'libbenchmark-dev', 'libboost-all-dev',
    # Rust, Go, Zig
    'rustc', 'cargo', 'rust-src', 'rust-clippy', 'rustfmt', 'rust-gdb', 'rust-lldb', 'rust-analyzer', 'cargo-c',
    'golang', 'gopls', 'delve',
    'zig',   # not in Debian (2026-10-16): ours to package (Daniel's cgm-zig, Zig 0.16.0 with its frontend fix)
    # Python
    'python3-dev', 'python3-venv', 'python3-pip', 'pipx', 'python3-pytest', 'ipython3', 'python3-debugpy', 'black',
    'flake8', 'mypy', 'pylint', 'ruff', 'python3-poetry', 'python3-build', 'python3-setuptools', 'python3-wheel',
    'jupyter-notebook',
    # Java and the JVM languages, JavaScript and TypeScript, .NET (Mono; Microsoft's .NET SDK is not in Debian)
    'default-jdk', 'maven', 'gradle', 'ant', 'kotlin', 'scala', 'groovy', 'clojure', 'leiningen', 'visualvm',
    'nodejs', 'npm', 'node-typescript', 'yarnpkg', 'mono-devel',
    # The other languages Debian carries, with their build tools
    'gfortran', 'gnat', 'gprbuild', 'gdc', 'ldc', 'nim', 'ghc', 'cabal-install', 'haskell-stack', 'ocaml', 'opam',
    'ocaml-dune', 'erlang', 'elixir', 'rebar3', 'ruby', 'ruby-dev', 'bundler', 'php-cli', 'composer', 'lua5.4',
    'liblua5.4-dev', 'luajit', 'luarocks', 'r-base', 'r-base-dev', 'racket', 'sbcl', 'guile-3.0', 'fpc', 'lazarus',
    'tcl', 'tk', 'valac', 'swi-prolog', 'nasm', 'yasm', 'wabt', 'binaryen', 'emscripten', 'haxe', 'crystal',
    'chicken-bin', 'gforth', 'gnucobol', 'gambas3', 'perl-doc', 'cpanminus',
    # Version control and forges
    'git', 'git-lfs', 'gitk', 'git-gui', 'tig', 'git-filter-repo', 'git-crypt', 'git-review', 'mercurial', 'subversion',
    'fossil', 'glab', 'tea', 'pre-commit',
    'gh',   # GitHub's CLI: in unstable only (2026-10-16)
    # Containers and virtual machines (libguestfs-tools: Daniel, 2026-10-16, "you can include that package")
    'docker.io', 'docker-compose', 'docker-buildx', 'podman', 'podman-compose', 'buildah', 'skopeo', 'incus', 'lxc',
    'systemd-container', 'qemu-system', 'qemu-utils', 'libvirt-daemon-system', 'libvirt-clients', 'virt-manager', 'virt-viewer',
    'libguestfs-tools', 'guestfs-tools', 'debootstrap', 'mmdebstrap', 'cloud-image-utils', 'ovmf', 'swtpm',
    'swtpm-tools', 'virtiofsd', 'spice-client-gtk',
    # Graphics and GPU debugging
    'apitrace', 'apitrace-gui', 'vulkan-tools', 'vulkan-validationlayers', 'vulkan-utility-libraries-dev',
    'libvulkan-dev', 'spirv-tools', 'spirv-cross', 'glslang-tools', 'glslc', 'mesa-utils', 'nvtop', 'radeontop',
    'intel-gpu-tools', 'drm-info', 'libdrm-tests', 'wayland-utils', 'clinfo', 'vainfo', 'vdpauinfo', 'mangohud',
    'edid-decode', 'read-edid', 'libegl-dev', 'libgles-dev', 'libgl-dev', 'libglx-dev', 'libwayland-dev',
    'wayland-protocols', 'libdecor-0-dev', 'libxkbcommon-dev',
    'renderdoc',   # not in Debian (2026-10-16): ours to package (MIT)
    'gfxreconstruct',   # LunarG's Vulkan capture and replay: not in Debian (2026-10-16)
    # Window, input and audio libraries (SDL 3, SDL 2 through sdl2-compat, GLFW, freeglut and FLTK are our stereo builds)
    'libsdl3-dev', 'libsdl3-image-dev', 'libsdl3-ttf-dev', 'libsdl3-mixer-dev', 'libsdl3-net-dev', 'libsdl2-dev',
    'libsdl2-image-dev', 'libsdl2-mixer-dev', 'libsdl2-ttf-dev', 'libsdl2-net-dev', 'libsdl2-gfx-dev', 'libsdl1.2-dev',
    'libglfw3-dev', 'libglut-dev', 'libfltk1.4-dev', 'libglew-dev', 'libepoxy-dev', 'libglm-dev', 'python3-glad',
    'libopenal-dev', 'libalure-dev', 'libvorbis-dev', 'libogg-dev', 'libopus-dev', 'libflac-dev', 'libsndfile1-dev',
    # Game libraries: rendering, physics, assets, networking, scripting
    'libraylib-dev', 'liballegro5-dev', 'libsfml-dev', 'libirrlicht-dev', 'libogre-14-dev', 'ogre-14-tools',
    'libopenscenegraph-dev', 'openscenegraph', 'libplib-dev', 'libclanlib-dev', 'libflatzebra-dev', 'libbox2d-dev',
    'libbullet-dev', 'libode-dev', 'libchipmunk-dev', 'libassimp-dev', 'assimp-utils', 'libimgui-dev', 'libcglm-dev',
    'libtcod-dev', 'libenet-dev', 'libgamenetworkingsockets-dev', 'libphysfs-dev', 'libfreetype-dev',
    'libharfbuzz-dev', 'libpng-dev', 'libjpeg-dev', 'libwebp-dev', 'libtinyxml2-dev', 'libyaml-cpp-dev',
    'nlohmann-json3-dev', 'libmeshoptimizer-dev', 'angelscript-dev', 'libsurgescript-dev',
    # OpenXR (Monado is our build: its peek window declares full side by side to Stereo KWin)
    'libopenxr-dev', 'openxr-layer-corevalidation', 'monado-service', 'monado-cli',
    # Game engines and frameworks, with their editors
    'godot', 'godot3', 'godot3-runner', 'godot3-server', 'love', 'renpy', 'renpy-doc', 'renpy-demo', 'luanti',
    'python3-pygame', 'python3-pgzero', 'python3-pyglet', 'python3-moderngl', 'python3-opengl', 'python3-fife',
    'spring', 'flare-engine', 'cube2', 'ioquake3', 'darkplaces', 'dhewm3', 'rbdoom3bfg', 'freespace2', 'openmw',
    'openmw-cs', 'netradiant', 'eureka', 'zdbsp', 'glbsp',
    'tiled',   # the map editor: in unstable only (2026-10-16)
])

# 11. Stereo OS developer: build, test and package the edition's own stack (task-sparky-stereo-os-developer; it depends on
# the developer task, and our development packages come from roles.tsv). Builds run in throwaway containers, so the
# build dependencies of each source are not listed: Docker comes with the developer task.
group('os-developer', 'Stereo OS developer: build, test and package the edition', [
    # Debian packaging (make-repo.sh runs apt-ftparchive; publish-tree.sh dpkg-scanpackages and gpg)
    'devscripts', 'debhelper', 'dh-make', 'dh-python', 'dpkg-dev', 'fakeroot', 'lintian', 'quilt', 'git-buildpackage',
    'sbuild', 'schroot', 'equivs', 'dput', 'apt-utils', 'dctrl-tools', 'apt-file', 'autopkgtest', 'piuparts',
    'diffoscope', 'strip-nondeterminism', 'licensecheck', 'gnupg', 'rsync', 'curl', 'wget', 'jq',
    # KDE's CI and translations (kde-ci-local: Python with YAML, git and Docker; KDE's lint jobs: reuse, yamllint,
    # xmllint, appstream; the edition's strings: gettext and Lokalize, which kdesdk brings)
    'python3-yaml', 'reuse', 'yamllint', 'libxml2-utils', 'appstream', 'desktop-file-utils', 'gettext',
    'translate-toolkit', 'python3-polib', 'shellcheck', 'bats',
    # The proof rig (headless Stereo KWin, captures, test clips and pictures, analysers, a PipeWire of its own)
    'xvfb', 'xauth', 'dbus-x11', 'libfaketime', 'faketime', 'imagemagick', 'ffmpeg', 'python3-pil', 'python3-numpy',
    'python3-scipy', 'python3-opencv', 'x264', 'mkvtoolnix', 'libimage-exiftool-perl', 'pipewire', 'pipewire-bin',
    'wireplumber', 'socat',
    # The VKMS stereo bench and the hibernation bench (QEMU comes with the developer task), kernel builds, Secure Boot
    'busybox-static', 'edid-decode', 'cpio', 'bc', 'bison', 'flex', 'libelf-dev', 'libssl-dev', 'dwarves', 'kmod',
    'igt-gpu-tools', 'sbsigntool', 'python3-virt-firmware', 'openssl',
    # Mesa's own test suite (the Mesa acceptance in the packaging skill)
    'piglit',
])

# Coherence: every tool the dedup kept a task for is shipped (in the base or in a list).
shipped = (base - set(base_remove)) | {p for _, pkgs in groups.values() for p in pkgs}
unshipped = sorted({i for a, i, _ in dedup.values() if a in ('drop', 'aptus') and i != '-'} - shipped)

for name, (title, pkgs) in groups.items():
    with open(os.path.join(HERE, name + '.list'), 'w') as f:
        f.write('# ' + title + ' (' + str(len(pkgs)) + ' packages; generated by make-lists.py)\n')
        f.write('\n'.join(pkgs) + '\n')
with open(os.path.join(HERE, 'MISSING.md'), 'w') as f:
    f.write('# Wanted, not in apt: to package ourselves or to offer through APTus\n\n')
    for name, pkgs in missing.items():
        f.write('- **' + name + ':** ' + ', '.join(pkgs) + '\n')
with open(os.path.join(HERE, 'base-remove.list'), 'w') as f:
    f.write('# Packages of the KDE edition the dedup replaced (Thunderbird by Kontact, Skanlite by Skanpage, Blueman by Bluedevil),\n'
            '# systemd-timesyncd (the edition keeps time with chrony) and the regular VLC player (VLC Stereo is the edition\'s VLC)\n')
    f.write('\n'.join(base_remove) + '\n')
with open(os.path.join(HERE, 'aptus.list'), 'w') as f:
    f.write('# Closed programs from Daniel\'s system: offered in APTus, not installed\n')
    f.write('\n'.join(sorted(p for p, (a, _, _) in dedup.items() if a == 'aptus')) + '\n')
with open(os.path.join(HERE, '..', 'DEDUP.md'), 'w') as f:
    f.write('# Dedup of the applications (generated by lists/make-lists.py from data/dedup.tsv)\n\n')
    f.write('One tool per task, KDE\'s where it covers the task (Daniel, 2026-10-02). '
            'Leftovers of tasks and meta-packages go.\n\n')
    titles = {'drop': 'Another tool does the task', 'dep': 'Libraries and data marked manual (they come with their program)',
              'games': 'Decided in the games list', 'aptus': 'Closed: offered in APTus',
              'hardware': 'Installed by the hardware setup'}
    for a, t in titles.items():
        rows = sorted((p, i, w) for p, (aa, i, w) in dedup.items() if aa == a)
        f.write('## ' + t + ' (' + str(len(rows)) + ')\n\n| Package | Instead | Why |\n|---|---|---|\n')
        for p, i, w in rows:
            f.write('| ' + p + ' | ' + (i if i != '-' else '') + ' | ' + w + ' |\n')
        f.write('\n')
    f.write('## Replaced on the KDE edition\n\n' + ', '.join(base_remove) + '\n')
print('instead, not shipped:', ', '.join(unshipped) or '-')
for name, (title, pkgs) in groups.items():
    print(f'{name:14} {len(pkgs):5}  missing: {", ".join(missing.get(name, [])) or "-"}')
