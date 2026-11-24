#!/usr/bin/python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/03
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/07
import hashlib
import pathlib
import subprocess
import tempfile

assert pathlib.Path('/.dockerenv').exists(), 'Run in Docker only'
tool = '/usr/bin/sparky-stereo-hardware'
base = {
    'lspci': '', 'lsusb': '', 'cpuinfo': '', 'laptop': '1\n',
    'architecture': 'amd64\n', 'hid-uevents': '', 'input-properties': '',
    'firmware-packages': '', 'nvidia-detect': 'No NVIDIA GPU detected.\n',
}
cases = [
    ('empty', {}, set(), set()),
    ('intel-laptop', {'laptop': '0', 'cpuinfo': 'vendor_id : GenuineIntel\n'},
     {'task-laptop', 'power-profiles-daemon', 'thermald', 'intel-microcode'}, set()),
    # thermald exits on any CPU that is not Intel (ORDER 43): only the Intel machines get it, laptop or desktop
    ('intel-desktop', {'cpuinfo': 'vendor_id : GenuineIntel\n'}, {'intel-microcode', 'thermald'}, set()),
    ('amd-desktop', {'cpuinfo': 'vendor_id : AuthenticAMD\n'}, {'amd64-microcode'}, set()),
    ('amd-laptop', {'laptop': '0', 'cpuinfo': 'vendor_id : AuthenticAMD\n'},
     {'task-laptop', 'power-profiles-daemon', 'amd64-microcode'}, set()),
    ('other-vendor', {'cpuinfo': 'vendor_id : HygonGenuine\n'}, set(), set()),
    ('firmware', {'firmware-packages': 'firmware-iwlwifi firmware-realtek\n'},
     {'firmware-iwlwifi', 'firmware-realtek'}, set()),
    ('turing', {'lspci': '0000:01:00.0 0300: 10de:1e04 (rev a1)\n'},
     {'firmware-nvidia-graphics'}, {'nvidia-open'}),
    ('ampere-named', {'lspci': '0000:01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GA106 [GeForce RTX 3060] [10de:2504] (rev a1)\n'},
     {'firmware-nvidia-graphics'}, {'nvidia-open'}),
    # Maxwell, Pascal and Volta: NVIDIA's 580 driver, the last for them, built by the edition (ORDER 354); no RTD3, which
    # needs a Turing card or newer, not even on a laptop
    ('pascal', {'lspci': '0000:01:00.0 0300: 10de:1b80\n'}, {'firmware-nvidia-graphics'}, {'nvidia-legacy-580xx'}),
    ('maxwell-laptop', {'laptop': '0', 'lspci': '0000:01:00.0 0302: 10de:13c2\n'},
     {'firmware-nvidia-graphics', 'task-laptop', 'power-profiles-daemon'}, {'nvidia-legacy-580xx'}),
    ('volta', {'lspci': '0000:01:00.0 0300: 10de:1d81\n'}, {'firmware-nvidia-graphics'}, {'nvidia-legacy-580xx'}),
    ('kepler', {'lspci': '0000:01:00.0 0300: 10de:1180\n'}, {'firmware-nvidia-graphics'}, set()),
    ('legacy-subsystem', {'lspci': '0000:01:00.0 0302: 10de:137d\n\tSubsystem: 17aa:3699\n'},
     {'firmware-nvidia-graphics'}, {'nvidia-legacy-580xx'}),
    ('legacy-wrong-subsystem', {'lspci': '0000:01:00.0 0302: 10de:137d\n\tSubsystem: 17aa:ffff\n'},
     {'firmware-nvidia-graphics'}, set()),
    ('mixed-legacy-turing', {'lspci': '0000:01:00.0 0300: 10de:1b80\n0000:02:00.0 0300: 10de:21c4\n'},
     {'firmware-nvidia-graphics'}, set()),
    ('legacy-arm', {'architecture': 'arm64', 'lspci': '0000:01:00.0 0300: 10de:1b80\n'},
     {'firmware-nvidia-graphics'}, set()),
    ('unknown', {'lspci': '0000:01:00.0 0302: 10de:ffff\n'}, {'firmware-nvidia-graphics'}, set()),
    ('mixed', {'lspci': '0000:01:00.0 0300: 10de:2504\n0000:02:00.0 0302: 10de:1b80\n'},
     {'firmware-nvidia-graphics'}, set()),
    ('nvidia-audio-only', {'lspci': '0000:01:00.1 0403: 10de:228e\n'}, set(), set()),
    ('nvidia-arm', {'architecture': 'arm64', 'lspci': '0000:01:00.0 0300: 10de:2504\n'},
     {'firmware-nvidia-graphics'}, set()),
    ('nvidia-subsystem', {'lspci': '0000:01:00.0 0302: 10de:3182\n\tSubsystem: 10de:20e6\n'},
     {'firmware-nvidia-graphics'}, {'nvidia-open'}),
    ('nvidia-wrong-subsystem', {'lspci': '0000:01:00.0 0302: 10de:3182\n\tSubsystem: 10de:ffff\n'},
     {'firmware-nvidia-graphics'}, set()),
    ('displaylink', {'lsusb': 'Bus 001 Device 002: ID 17e9:6006 DisplayLink\n'}, {'evdi-dkms'}, set()),
    ('xbox', {'lsusb': 'Bus 001 Device 003: ID 045e:0b12 Microsoft Corp. Xbox\n'},
     {'steam-devices', 'xpadneo-dkms'}, set()),
    ('microsoft-keyboard', {'lsusb': 'Bus 001 Device 003: ID 045e:07f8 Microsoft Corp. Keyboard\n'}, set(), set()),
    ('bluetooth-xbox', {'hid-uevents': 'HID_ID=0005:0000045E:00000B13\n'},
     {'steam-devices', 'xpadneo-dkms'}, set()),
    ('usb-hid-not-bluetooth', {'hid-uevents': 'HID_ID=0003:0000045E:00000B13\n'}, set(), set()),
    ('generic-pad', {'input-properties': 'ID_INPUT_JOYSTICK=1\n'}, {'steam-devices'}, set()),
    ('playstation', {'lsusb': 'Bus 001 Device 007: ID 054c:0ce6 Sony DualSense\n'}, {'steam-devices'}, set()),
    ('creative-other', {'lspci': '0000:03:00.0 0403: 1102:0009\n'}, set(), set()),
]
for device in ('0010', '0011', '0012'):
    cases.append((f'creative-{device}', {'lspci': f'0000:03:00.0 0403: 1102:{device}\n'},
                  {'firmware-creative-stereo'}, {'creative-msi'}))


# Fixture directories (tests/fixtures): packages, then the lines of kind fact and candidate that
# must be present. The new facts are read-only; the packages named are ones the lists install.
here = pathlib.Path(__file__).resolve().parent / 'fixtures'
fixture_cases = {
    # a Corsair K70 (OpenRGB drives it) on a Gigabyte desktop board: OpenRGB, and the SMBus for its board lights (ORDER 108, milestone 6)
    'gigabyte-corsair-v3': ({'amd64-microcode', 'linux-image-sparky-stereo-v3', 'linux-headers-sparky-stereo-v3', 'openrgb', 'i2c-tools'}, [
        'fact\tcpu-level\tv3', 'fact\tx86-64-v3\tyes', 'action\topenrgb-session', 'action\ti2c-dev',
        'fact\tsmbus-modules\ti2c-dev i2c-piix4', 'fact\tperipheral\topenrgb\t1b1c:1b13',
        'fact\tboard\tGigabyte Technology Co., Ltd. / B550 TEST BOARD',
        'fact\tusb-vendors\t1b1c (Corsair) 1d6b'], []),
    # a Razer Huntsman Elite on an ASUS desktop board: OpenRGB and OpenRazer (the daemon and its DKMS module), and the SMBus (Intel: i2c-i801)
    'razer-mt7922-v3': ({'intel-microcode', 'thermald', 'firmware-mediatek', 'linux-image-sparky-stereo-v3', 'linux-headers-sparky-stereo-v3',
                         'openrgb', 'i2c-tools', 'openrazer-daemon', 'openrazer-driver-dkms'}, [
        'fact\tcpu-level\tv3', 'fact\tx86-64-v3\tyes', 'action\topenrgb-session', 'fact\tsmbus-modules\ti2c-dev i2c-i801',
        'fact\tperipheral\topenrazer\t1532:0243',
        'fact\tboard\tASUSTeK COMPUTER INC. / Z370 TEST BOARD',
        'fact\tusb-vendors\t1532 (Razer)',
        'fact\tnetwork-driver\t14c3:0616 mt7921e (in our kernel) MediaTek Wi-Fi 6/7 (MT7921, MT7922, MT7902, MT7925)',
        'fact\tnetwork-pci\t14c3:0616'], []),
    'broadcom-4331-v2': ({'task-laptop', 'power-profiles-daemon', 'thermald', 'intel-microcode'}, [
        'fact\tcpu-level\tv2', 'fact\tx86-64-v3\tno',
        'fact\tnetwork-pci\t14e4:4331',
        # b43 drives it and wl drives it too: the kernel's driver keeps it, wl is offered (row 728)
        'fact\tnetwork-two-drivers\t14e4:4331 b43/brcmsmac/brcmfmac', 'action\tbroadcom-wl-swap'],
        ['candidate\tbroadcom-sta-dkms\t14e4:4331: closed Broadcom wl driver']),
    # An Intel iMac 21.5-inch, Late 2013 (iMac14,1): the Wi-Fi is a BCM4360, which no driver of our kernel drives, so wl
    # is the plan's candidate with its licence line; the wired Broadcom card (tg3) is not in the table and is left alone
    'imac14-1-bcm4360': ({'intel-microcode', 'thermald', 'linux-image-sparky-stereo-v3', 'linux-headers-sparky-stereo-v3'}, [
        'fact\tcpu-level\tv3', 'fact\tx86-64-v3\tyes',
        'fact\tboard\tApple Inc. / Mac-031B6874CF7F642A',
        'fact\tusb-vendors\t05ac 1d6b',
        'fact\tnetwork-driver\t14e4:43a0 wl (Broadcom, DKMS; no driver of our kernel) Broadcom Wi-Fi (802.11ac)',
        'fact\tnetwork-no-kernel-driver\t14e4:43a0', 'action\tbroadcom-wl',
        'fact\tnetwork-pci\t14e4:1686 14e4:43a0',
        'licence\tbroadcom-sta-dkms\t14e4:43a0\tBroadcom Software License Agreement\tusr/share/doc/broadcom-sta-dkms/copyright'],
        ['candidate\tbroadcom-sta-dkms\t14e4:43a0: closed Broadcom wl driver']),
    'baseline-cpu': ({'intel-microcode', 'thermald'}, [
        'fact\tcpu-level\tv1', 'fact\tx86-64-v3\tno'], []),
}
# lines that must NOT appear: the BCM4331 has b43 in our kernel, so it is not a card without a kernel driver
absent_lines = {'broadcom-4331-v2': ['fact\tnetwork-no-kernel-driver', 'action\tbroadcom-wl'],
                'imac14-1-bcm4360': ['fact\tnetwork-two-drivers', 'action\tbroadcom-wl-swap']}
for name, (expected_packages, expected_lines, candidate_prefixes) in fixture_cases.items():
    out = subprocess.run([tool, '--auto', '--dry-run', '--fixture', str(here / name)], text=True,
                         capture_output=True, check=True).stdout
    lines = out.splitlines()
    packages = {l.split('\t')[1] for l in lines if l.startswith('package\t')}
    assert packages == expected_packages, (name, packages, expected_packages, out)
    for line in expected_lines:
        assert line in lines, (name, line, out)
    for prefix in candidate_prefixes:
        assert any(l.startswith(prefix) for l in lines), (name, prefix, out)
        assert any('licence must be shown' in l for l in lines if l.startswith('candidate\t')), (name, out)
        # the planner names the licence file for every wl candidate: the action layer shows it before any install
        assert any(l.startswith('licence\tbroadcom-sta-dkms\t') and l.endswith('usr/share/doc/broadcom-sta-dkms/copyright') for l in lines), (name, out)
    for prefix in absent_lines.get(name, []):
        assert not any(l == prefix or l.startswith(prefix + '\t') for l in lines), (name, prefix, out)
    # the dry run says what it would do about the Wi-Fi driver, only for the card no kernel driver drives
    assert ('Would show the licence of broadcom-sta-dkms' in out) == (name == 'imac14-1-bcm4360'), (name, out)
    # and, for a card two drivers drive, that it leaves the kernel's driver and offers wl (row 728)
    assert ('Would leave the Broadcom Wi-Fi card (14e4:4331 b43/brcmsmac/brcmfmac) to the kernel' in out) == (name == 'broadcom-4331-v2'), (name, out)
    assert not any('broadcom-sta' in p for p in packages), name
    assert not any('disagreement' in l for l in lines), (name, out)
    print(f'PASS fixture {name}: packages={sorted(packages)}')
bad = subprocess.run([tool, '--broadcom-wl', 'bogus', '--dry-run', '--fixture', str(here / 'imac14-1-bcm4360')], text=True, capture_output=True)
assert bad.returncode == 2 and 'ask, yes, no, repair, reset, swap or back' in bad.stderr, bad
assert '--broadcom-wl ask|yes|no|repair|reset|swap|back' in subprocess.run([tool, '--help'], text=True, capture_output=True, check=True).stdout
print('PASS --broadcom-wl takes only ask, yes, no, repair, reset, swap or back')
# a BCM4321 5 GHz card (14e4:432a): no module of the published kernel claims it, so it takes the wl-only route (row 728)
import shutil
with tempfile.TemporaryDirectory() as tmp:
    d = pathlib.Path(tmp) / 'bcm432a'
    shutil.copytree(here / 'broadcom-4331-v2', d)
    (d / 'lspci').write_text((d / 'lspci').read_text().replace('BCM4331 802.11a/b/g/n [14e4:4331]', 'BCM4321 802.11a [14e4:432a]'))
    lines = subprocess.run([tool, '--auto', '--dry-run', '--fixture', str(d)], text=True, capture_output=True, check=True).stdout.splitlines()
    assert 'fact\tnetwork-no-kernel-driver\t14e4:432a' in lines and 'action\tbroadcom-wl' in lines, lines
    assert not any(l.startswith('fact\tnetwork-two-drivers') or l == 'action\tbroadcom-wl-swap' for l in lines), lines
print('PASS 14e4:432a, claimed by no kernel module, takes the wl-only route')
# The x86-64-v3 kernel (ORDER 108): both flavours of the processor, the person's own choice, and a processor that is not v3 or not amd64
import shutil
with tempfile.TemporaryDirectory() as tmp:
    for name, level_from, change, want in (
            ('v3 processor', 'gigabyte-corsair-v3', {}, True),
            ('v3 processor, the baseline kernel chosen', 'gigabyte-corsair-v3', {'kernel-choice': 'base\n'}, False),
            ('v2 processor', 'broadcom-4331-v2', {}, False),
            ('baseline processor', 'baseline-cpu', {}, False),
            ('v3 processor on arm64', 'gigabyte-corsair-v3', {'architecture': 'arm64\n'}, False)):
        d = pathlib.Path(tmp) / name.replace(' ', '-').replace(',', '')
        shutil.copytree(here / level_from, d)
        for k, v in change.items():
            (d / k).write_text(v)
        out = subprocess.run([tool, '--auto', '--dry-run', '--fixture', str(d)], text=True, capture_output=True, check=True).stdout
        got = {l.split('\t')[1] for l in out.splitlines() if l.startswith('package\t') and 'sparky-stereo-v3' in l}
        assert got == ({'linux-image-sparky-stereo-v3', 'linux-headers-sparky-stereo-v3'} if want else set()), (name, got, out)
        assert ('Would install linux-image-sparky-stereo-v3' in out) == want, (name, out)
        print(f'PASS kernel selection, {name}: x86-64-v3 kernel {"planned" if want else "not planned"}')
bad = subprocess.run([tool, '--kernel', 'bogus', '--dry-run', '--fixture', str(here / 'baseline-cpu')], text=True, capture_output=True)
assert bad.returncode == 2 and 'v3 (the default' in bad.stderr, bad
old = subprocess.run([tool, '--auto', '--dry-run', '--fixture', str(here / 'creative-nvidia-laptop')], text=True,
                     capture_output=True, check=True).stdout
assert not any(l.startswith(('fact\t', 'candidate\t')) for l in old.splitlines()), old
print('PASS existing fixture creative-nvidia-laptop prints no new facts')


def installed_state():
    result = subprocess.check_output(['dpkg-query', '-W', '-f', '${Package} ${Version} ${Status}\n'])
    return hashlib.sha256(result).digest()


before = installed_state()
with tempfile.TemporaryDirectory() as tmp:
    directory = pathlib.Path(tmp)
    for name, changes, expected_packages, expected_actions in cases:
        facts = base | changes
        for key, value in facts.items():
            (directory / key).write_text(value)
        args = [tool, '--auto', '--dry-run', '--fixture', str(directory)]
        result = subprocess.run(args, text=True, capture_output=True, check=True).stdout
        packages = {line.split('\t')[1] for line in result.splitlines() if line.startswith('package\t')}
        actions = {line.split('\t')[1] for line in result.splitlines() if line.startswith('action\t')}
        assert packages == expected_packages, (name, packages, expected_packages, result)
        assert actions == expected_actions, (name, actions, expected_actions, result)
        assert 'firmware-nvidia-gsp' not in result
        assert 'DRY RUN:' in result
        assert subprocess.check_output(args, text=True) == result, name
        print(f'PASS {name}: packages={sorted(packages)}, actions={sorted(actions)}')
    (directory / 'firmware-packages').write_text('--allow-unauthenticated\n')
    bad = subprocess.run(args, capture_output=True)
    assert bad.returncode != 0, 'Reject malformed package data'
    assert subprocess.run([tool, '--auto', '--fixture', tmp], capture_output=True).returncode == 2
    assert subprocess.run([tool, '--auto'], capture_output=True).returncode == 2
    assert subprocess.run([tool, '--bogus'], capture_output=True).returncode == 2
assert before == installed_state(), 'Dry runs changed installed package state'
assert not pathlib.Path('/etc/apt/sources.list.d/sparky-stereo-cuda.sources').exists()
assert not pathlib.Path('/etc/modprobe.d/sparky-stereo-creative.conf').exists()
print(f'PASS {len(cases)} detection cases, repeatability, dry-run package/config immutability and input guards')
