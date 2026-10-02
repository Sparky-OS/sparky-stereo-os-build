#!/usr/bin/env python3
# Sparky Stereo OS: the edition's package lists, checked against what apt offers.
# Writes one <name>.list per group (one package per line, comments for context) and
# MISSING.md for every wanted package apt does not have (to package, or for APTus).
# Run on a system with the edition's apt sources (Debian testing, Sparky, deb-multimedia).
import glob, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, '..', 'data')

# Every package apt can install, by architecture (amd64, all, i386 when multiarch is on).
available = set()
for f in glob.glob('/var/lib/apt/lists/*_Packages'):
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

# 1. Applications from Daniel's system beyond the KDE edition, from Debian or Sparky
# (vendor and local ones go through APTus).
apps = [l.split('\t')[0] for l in open(os.path.join(DATA, 'daniel_only_apps.origin.tsv'))
        if l.rstrip('\n').split('\t')[1] in ('debian', 'sparky')]
group('apps', "Applications on Daniel's system beyond the KDE edition (Debian and Sparky)", apps)

# 2. Games: SteamOS-like, the chosen GameOver games, KDE's games, three well-known additions.
group('games', 'Games', [
    'extremetuxracer', 'warzone2100', 'widelands', 'luanti', 'openarena', 'ioquake3',
    'armagetronad', 'gl-117', 'billard-gl', 'xmoto', 'teeworlds', 'chromium-bsu', 'blobby',
    'lbreakouthd', 'liquidwar', 'netpanzer', 'freedroid',
    'supertuxkart', '0ad', 'openttd',
    'kdegames', 'knights', 'gnuchess',
])

# 3. Gaming tools (Steam Gaming Mode and gamescope come from the stereo package).
group('gaming', 'Gaming tools', [
    'steam-installer', 'steam-devices', 'gamemode', 'mangohud', 'goverlay', 'lutris',
    'heroic', 'wine', 'wine64', 'winetricks',
    # wine32:i386 is not in Debian testing (2026-10-02): check by running a 32-bit Windows
    # program whether Wine 10's WoW64 mode covers it before adding anything
])

# 4. 3D emulation (APTus section "3D emulation", installed by default): emulators with a
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
prefixes = ['firefox-esr-l10n-', 'thunderbird-l10n-', 'libreoffice-l10n-', 'libreoffice-help-',
            'hunspell-', 'hyphen-', 'mythes-']
langs = []
for codes in steam.values():
    for c in codes:
        for pre in prefixes:
            if pre + c in available:
                langs.append(pre + c)
group('languages', 'Languages (all of Steam\'s)', langs + [
    'locales-all', 'fonts-noto-core', 'fonts-noto-cjk', 'fonts-noto-cjk-extra', 'fonts-thai-tlwg',
    'ibus-mozc', 'ibus-hangul', 'ibus-libpinyin', 'ibus-chewing', 'ibus-unikey', 'ibus-m17n',
])

# 7. Hardware: firmware and the tools the hardware setup uses (DKMS drivers only when found).
group('hardware', 'Hardware support', [
    'laptop-detect', 'isenkram-cli', 'discover', 'nvidia-detect', 'lm-sensors', 'fancontrol',
    'thermald', 'power-profiles-daemon', 'fwupd', 'inxi', 'hw-probe', 'bluetooth',
    'firmware-linux', 'firmware-linux-nonfree', 'firmware-misc-nonfree', 'firmware-amd-graphics',
    'firmware-realtek', 'firmware-iwlwifi', 'firmware-atheros', 'firmware-brcm80211',
    'firmware-intel-sound', 'firmware-sof-signed', 'amd64-microcode', 'intel-microcode',
    'mesa-vulkan-drivers', 'mesa-va-drivers', 'intel-media-va-driver', 'vainfo', 'vdpauinfo',
    'evdi-dkms', 'displaylink-driver',
])

# 8. System: apps from Flathub, containers, Android, snapshots, zram.
group('system', 'System', [
    'flatpak', 'plasma-discover-backend-flatpak', 'distrobox', 'waydroid', 'btrfs-progs',
    'snapper', 'timeshift', 'systemd-zram-generator', 'synaptic',
    'grub-btrfs', 'scx-scheds', 'ananicy-cpp', 'sunshine', 'protonup-qt', 'hhd', 'decky-loader',
])

# 9. Look: Oxygen dark default (Daniel's QPlatinum and Sparky black come as packages of ours).
group('look', 'Look', [
    'plasma-theme-oxygen', 'oxygen-icon-theme', 'oxygencursors', 'kde-style-oxygen-qt6',
    'kwin-decoration-oxygen', 'qt6ct',
])

for name, (title, pkgs) in groups.items():
    with open(os.path.join(HERE, name + '.list'), 'w') as f:
        f.write('# ' + title + ' (' + str(len(pkgs)) + ' packages; generated by make-lists.py)\n')
        f.write('\n'.join(pkgs) + '\n')
with open(os.path.join(HERE, 'MISSING.md'), 'w') as f:
    f.write('# Wanted, not in apt: to package ourselves or to offer through APTus\n\n')
    for name, pkgs in missing.items():
        f.write('- **' + name + ':** ' + ', '.join(pkgs) + '\n')
for name, (title, pkgs) in groups.items():
    print(f'{name:14} {len(pkgs):5}  missing: {", ".join(missing.get(name, [])) or "-"}')
