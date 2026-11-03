#!/usr/bin/python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/02
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/02
"""The NVIDIA branch the plan picks for a Turing, a Pascal, a Maxwell (laptop), a Kepler and an unknown card, from the
fixtures in tests/fixtures (lspci -Dnnv lines with the cards' real PCI IDs and subsystems; the machines are synthetic), with
the installed tool in a container, --dry-run only (ORDER 354). The open modules for Turing and newer; NVIDIA's 580 driver for
Maxwell, Pascal and Volta, with both drivers said as the person's choice and the default marked; nouveau, with the reason,
for Kepler and for a card in none of NVIDIA's tables. On sparky-stereo-hardware 0.1.16 the Pascal and Maxwell cases fail:
those cards get no driver offer."""
import pathlib
import subprocess

assert pathlib.Path('/.dockerenv').exists(), 'Run in Docker only'
tool = '/usr/bin/sparky-stereo-hardware'
here = pathlib.Path(__file__).resolve().parent / 'fixtures'
failures = []


def plan(name, *extra):
    run = subprocess.run([tool, '--auto', '--dry-run', '--fixture', str(here / name), *extra], text=True,
                         capture_output=True)
    if run.returncode != 0:
        failures.append(f'{name}: the dry run exited {run.returncode}: {run.stdout}{run.stderr}')
    lines = run.stdout.splitlines()
    kinds = {}
    for line in lines:
        kind, _, value = line.partition('\t')
        kinds.setdefault(kind, []).append(value)
    return run.stdout, lines, kinds


def check(name, condition, what):
    if condition:
        print(f'PASS {name}: {what}')
    else:
        failures.append(f'{name}: {what}')
        print(f'FAIL {name}: {what}')


out, lines, kinds = plan('nvidia-turing-gtx1660s')
check('turing', kinds.get('action') == ['nvidia-open'], "the edition's open modules (action nvidia-open), and nothing else")
check('turing', 'choice' not in kinds, 'no choice between drivers: the open modules have HDMI 3D')

for name, label in (('nvidia-pascal-gtx1080', 'pascal'), ('nvidia-maxwell-gtx960m-laptop', 'maxwell laptop')):
    out, lines, kinds = plan(name)
    check(label, kinds.get('action') == ['nvidia-legacy-580xx'],
          "NVIDIA's 580 driver (action nvidia-legacy-580xx), no open modules and no RTD3 (it needs Turing or newer)")
    choices = kinds.get('choice', [])
    check(label, len(choices) == 2 and choices[0].startswith('nvidia-580\tdefault: ')
          and choices[1].startswith('nouveau\t'), "both drivers said, NVIDIA's 580 marked as the default")
    check(label, any('HDMI 3D' in c for c in choices[1:]), "the nouveau choice says it keeps the edition's HDMI 3D")
    check(label, 'firmware-nvidia-graphics' in kinds.get('package', []), "nouveau's firmware, for the card until a reboot")
    check(label, any(l.startswith("Would install sparky-stereo-nvidia-legacy-580xx-driver-lock first") for l in lines)
          or any(l.startswith('Would stop with an ERROR: apt finds no nvidia-legacy-580xx-kernel-dkms') for l in lines),
          "the dry run says what the 580 path would do, or what would stop it")
    out, lines, kinds = plan(name, '--nvidia', 'nouveau')
    check(label, any(l.startswith("Would keep nouveau for the NVIDIA graphics, as chosen (--nvidia nouveau), with the "
                                  "edition's HDMI 3D") for l in lines), '--nvidia nouveau keeps nouveau and says so')
    check(label, not any('Would install sparky-stereo-nvidia-legacy-580xx-driver-lock' in l for l in lines),
          '--nvidia nouveau plans nothing of NVIDIA')

out, lines, kinds = plan('nvidia-maxwell-gtx960m-laptop')
check('maxwell laptop', 'nvidia-runtime-pm' not in kinds.get('action', []), 'no RTD3 configuration on a Maxwell laptop')

out, lines, kinds = plan('nvidia-kepler-gtx680')
check('kepler', 'action' not in kinds, 'no NVIDIA driver: the card keeps nouveau')
check('kepler', any("1180: NVIDIA's last driver for it is its legacy 470.xx branch, which the edition does not build" in f
                    for f in kinds.get('found', [])), 'the plan names the 470 branch as the reason')

out, lines, kinds = plan('nvidia-unknown-ffff')
check('unknown', 'action' not in kinds, 'no NVIDIA driver: the card keeps nouveau')
check('unknown', any("ffff is in none of NVIDIA's 615.71.09 tables" in f for f in kinds.get('found', [])),
      'the plan says the card is in none of NVIDIA\'s tables')

if failures:
    print(f'FAIL {len(failures)} checks')
    raise SystemExit(1)
print('PASS the NVIDIA branch for Turing, Pascal, Maxwell, Kepler and an unknown card')
