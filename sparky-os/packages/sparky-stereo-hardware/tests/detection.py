#!/usr/bin/python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/03
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/03
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
