#!/usr/bin/python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/03
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/05
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
    ('amd-desktop', {'cpuinfo': 'vendor_id : AuthenticAMD\n'}, {'amd64-microcode'}, set()),
    ('firmware', {'firmware-packages': 'firmware-iwlwifi firmware-realtek\n'},
     {'firmware-iwlwifi', 'firmware-realtek'}, set()),
    ('turing', {'lspci': '0000:01:00.0 0300: 10de:1e04 (rev a1)\n'},
     {'firmware-nvidia-graphics'}, {'nvidia-open'}),
    ('ampere-named', {'lspci': '0000:01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GA106 [GeForce RTX 3060] [10de:2504] (rev a1)\n'},
     {'firmware-nvidia-graphics'}, {'nvidia-open'}),
    ('pascal', {'lspci': '0000:01:00.0 0300: 10de:1b80\n'}, {'firmware-nvidia-graphics'}, set()),
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
    'gigabyte-corsair-v3': ({'amd64-microcode'}, [
        'fact\tcpu-level\tv3', 'fact\tx86-64-v3\tyes',
        'fact\tboard\tGigabyte Technology Co., Ltd. / B550 AORUS ELITE V2',
        'fact\tusb-vendors\t1b1c (Corsair) 1d6b'], []),
    'razer-mt7922-v3': ({'intel-microcode', 'firmware-mediatek'}, [
        'fact\tcpu-level\tv3', 'fact\tx86-64-v3\tyes',
        'fact\tboard\tASUSTeK COMPUTER INC. / ROG STRIX Z370-F GAMING',
        'fact\tusb-vendors\t1532 (Razer)',
        'fact\tnetwork-driver\t14c3:0616 mt7921e (in our kernel) MediaTek Wi-Fi 6/7 (MT7921, MT7922, MT7902, MT7925)',
        'fact\tnetwork-pci\t14c3:0616'], []),
    'broadcom-4331-v2': ({'task-laptop', 'power-profiles-daemon', 'thermald', 'intel-microcode'}, [
        'fact\tcpu-level\tv2', 'fact\tx86-64-v3\tno',
        'fact\tnetwork-pci\t14e4:4331'], ['candidate\tbroadcom-sta-dkms\t14e4:4331: closed Broadcom wl driver']),
    'baseline-cpu': ({'intel-microcode'}, [
        'fact\tcpu-level\tv1', 'fact\tx86-64-v3\tno'], []),
}
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
    assert not any('broadcom-sta' in p for p in packages), name
    assert not any('disagreement' in l for l in lines), (name, out)
    print(f'PASS fixture {name}: packages={sorted(packages)}')
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
