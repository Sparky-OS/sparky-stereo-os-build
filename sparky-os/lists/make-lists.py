#!/usr/bin/env python3
# Sparky Stereo OS: the edition's package lists, checked against what apt offers.
# Writes one <name>.list per group (one package per line, comments for context) and
# MISSING.md for every wanted package apt does not have (to package, or for APTus).
# Run on a system with the edition's apt sources (Debian testing, Sparky, deb-multimedia).
import glob, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, '..', 'data')

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
base_remove = ['thunderbird', 'skanlite', 'blueman'] + sorted(p for p in base if p.startswith('thunderbird-l10n-'))

# 1. Applications from Daniel's system beyond the KDE edition, from Debian or Sparky
# (vendor and local ones go through APTus), deduplicated, plus the KDE tools the dedup
# chose that neither has.
apps = [l.split('\t')[0] for l in open(os.path.join(DATA, 'daniel_only_apps.origin.tsv'))
        if l.rstrip('\n').split('\t')[1] in ('debian', 'sparky')]
apps = [p for p in apps if p not in dedup]
group('apps', "Applications beyond the KDE edition (Daniel's, deduplicated)", apps + [
    'kdenlive', 'skanpage', 'subtitlecomposer', 'neochat', 'qpwgraph',
    'libreoffice-kf6', 'libreoffice-draw', 'kdenetwork-filesharing', 'kio-fuse',
    'coolercontrol',   # fans and pumps (GPL-3; its repository is the vendor's: to package)
    # stereo editing and 3D work (Daniel, 2026-10-02): ours to package first, then Debian's
    'stereophotoview', 'sview', 'blender', 'freecad', 'paraview', 'hugin-tools', 'libimage-exiftool-perl',
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
    'it': ['it'], 'ja': ['ja'], 'ko': ['ko'], 'ms': ['ms'], 'no': ['nb', 'nb-no', 'nn', 'nn-no', 'no'],
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

# 8. System: apps from Flathub, containers, Android, snapshots, zram.
group('system', 'System', [
    'flatpak', 'plasma-discover-backend-flatpak', 'distrobox', 'waydroid', 'btrfs-progs',
    'timeshift', 'systemd-zram-generator', 'synaptic',   # snapshots: Timeshift (with grub-btrfs)
    'grub-btrfs', 'scx-scheds', 'ananicy-cpp', 'sunshine', 'protonup-qt', 'hhd', 'decky-loader',
])

# 9. Look: Oxygen dark default (Daniel's QPlatinum and Sparky black come as packages of ours).
group('look', 'Look', [
    'plasma-theme-oxygen', 'oxygen-icon-theme', 'oxygencursors', 'kde-style-oxygen-qt6',
    'kwin-decoration-oxygen', 'qt6ct',
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
    f.write('# Packages of the KDE edition the dedup replaced (Thunderbird by Kontact, Skanlite by Skanpage, Blueman by Bluedevil)\n')
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
