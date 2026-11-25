#!/usr/bin/python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/25
# Copyright 2026 under the GNU GPL3 License
"""The two corrections of the known-machines table (ORDER 665, 669), on DMI fixtures: the model, its sibling and an
unrelated machine. Needs iasl; update-initramfs and update-grub are doubles that do what the package's hook and boot
option file do (the real ones are run in the guest proof). Run in a container: known-machines-corrections.py [REFERENCE.asl]"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

recipe = Path(__file__).resolve().parent.parent
tool = recipe / 'bin/sparky-stereo-known-machines'
fails = 0


def check(name, got, want):
    global fails
    if got == want:
        print('PASS ', name)
    else:
        print('FAIL  %s: got %r, want %r' % (name, got, want))
        fails += 1


work = Path(tempfile.mkdtemp())
tables = work / 'acpi-tables'
tables.mkdir()
source = recipe / 'share/acpi-tables/mbp92-gfx0.asl'
subprocess.run(['iasl', '-p', str(tables / 'mbp92-gfx0'), str(source)], check=True, capture_output=True)
aml = (tables / 'mbp92-gfx0.aml').read_bytes()
check('the table compiles to an SSDT with our OEM table ID', (aml[:4], aml[10:16], aml[16:24]), (b'SSDT', b'SPARKY', b'MBP92GFX'))
if len(sys.argv) > 1:
    ref = work / 'reference'
    ref.mkdir()
    subprocess.run(['iasl', '-p', str(ref / 'reference'), sys.argv[1]], check=True, capture_output=True)
    check('the same bytes as a build of the hand-made source (%s)' % Path(sys.argv[1]).name,
          aml == (ref / 'reference.aml').read_bytes(), True)

bin_dir = work / 'bin'
bin_dir.mkdir()
calls = work / 'calls'
# the doubles: what the hook records per kernel, and the kernel line the boot option file gives
(bin_dir / 'update-initramfs').write_text('''#!/bin/sh
echo "update-initramfs $*" >> %s
[ -e %s/fail ] && exit 3
for i in "$SPARKY_STEREO_ROOT"/boot/initrd.img-*; do
  r=${i##*/initrd.img-}; mkdir -p "$SPARKY_STEREO_ROOT/var/lib/sparky-stereo-hardware/known-machines-boot-images"
  %s --table %s --sysfs-root "$FIXTURE" --tables %s --acpi-tables | sed 's,.*/,,' > "$SPARKY_STEREO_ROOT/var/lib/sparky-stereo-hardware/known-machines-boot-images/$r"
done
''' % (calls, work, tool, recipe / 'share/known-machines.json', tables))
(bin_dir / 'update-grub').write_text('''#!/bin/sh
echo "update-grub $*" >> %s
printf 'menuentry x {\\n\\tlinux /boot/vmlinuz-7.3.4 root=UUID=1 ro quiet %%s\\n}\\n' "$(%s --table %s --sysfs-root "$FIXTURE" --tables %s --kernel-options)" > "$SPARKY_STEREO_ROOT/boot/grub/grub.cfg"
''' % (calls, tool, recipe / 'share/known-machines.json', tables))
for name in ('update-initramfs', 'update-grub'):
    (bin_dir / name).chmod(0o755)


def machine(product):
    root = Path(tempfile.mkdtemp(dir=work))
    (root / 'sys/class/dmi/id').mkdir(parents=True)
    (root / 'sys/class/dmi/id/product_name').write_text(product + '\n')
    (root / 'boot/grub').mkdir(parents=True)
    (root / 'boot/grub/grub.cfg').write_text('menuentry x {\n\tlinux /boot/vmlinuz-7.3.4 root=UUID=1 ro quiet\n}\n')
    for release in ('7.3.4-stereo3d18', '7.3.4-stereo3d18-v3'):
        (root / 'boot' / ('initrd.img-' + release)).write_text('')
    (root / 'proc').mkdir()
    (root / 'proc/cmdline').write_text('BOOT_IMAGE=/boot/vmlinuz-7.3.4 ro quiet\n')
    return root


def run(root, *args, ok=True):
    env = dict(os.environ, SPARKY_STEREO_ROOT=str(root), FIXTURE=str(root / 'sys'), PATH='%s:%s' % (bin_dir, os.environ['PATH']))
    r = subprocess.run(['python3', str(tool), '--table', str(recipe / 'share/known-machines.json'), '--sysfs-root', str(root / 'sys'), '--tables', str(tables),
                        '--cmdline', str(root / 'proc/cmdline'), *args], capture_output=True, text=True, env=env)
    if (r.returncode == 0) != ok:
        raise SystemExit('unexpected exit %s of %s: %s' % (r.returncode, args, r.stderr))
    return r


def ran():
    text = calls.read_text() if calls.exists() else ''
    calls.write_text('')
    return text.split('\n')[:-1]


expect = {'MacBookPro9,2': (['mbp92-gfx0.aml'], ''), 'MacBookPro9,1': ([], ''), 'MacBookPro10,2': ([], ''),
          'iMac14,1': ([], 'acpi_mask_gpe=0x06'), 'iMac14,2': ([], ''), 'iMac14,10': ([], ''), 'To Be Filled By O.E.M.': ([], ''), '': ([], '')}
for product, (want_tables, want_options) in expect.items():
    root = machine(product)
    got = [Path(p).name for p in run(root, '--acpi-tables').stdout.split()]
    check('%r: firmware tables for the boot image' % product, got, want_tables)
    check('%r: kernel options' % product, run(root, '--kernel-options').stdout.strip(), want_options)
    ran()
    out = json.loads(run(root, '--apply').stdout)
    steps = ran()
    want_steps = (['update-initramfs -u -k all'] if want_tables else []) + (['update-grub '] if want_options else [])
    check('%r: --apply writes exactly what is behind' % product, steps, want_steps)
    check('%r: a restart is said only when something was written' % product, out['restart_needed'], bool(want_steps))
    run(root, '--apply')
    check('%r: a second --apply does nothing' % product, ran(), [])

# the MacBook: listed, switched off and on
root = machine('MacBookPro9,2')
rows = json.loads(run(root, '--list').stdout)['corrections']
check('listed with its sentence, on, kind and table', [(r['id'], r['message'], r['on'], r['kind'], r['table']) for r in rows],
      [('mbp92-gfx0', 114, True, 'acpi-table', 'mbp92-gfx0.aml')])
check('--list changes nothing', ran(), [])
check('--apply --dry-run names the step and runs nothing',
      (json.loads(run(root, '--apply', '--dry-run').stdout)['changes'], ran()), ([{'step': 'boot-image', 'would_run': ['update-initramfs', '-u', '-k', 'all']}], []))
run(root, '--apply')
ran()
out = json.loads(run(root, '--off', 'mbp92-gfx0').stdout)
check('--off: the boot images are written again without the table, a restart is said',
      (ran(), out['restart_needed'], out['corrections'][0]['on'], run(root, '--acpi-tables').stdout), (['update-initramfs -u -k all'], True, False, ''))
check('--off is kept where the person can read it', (root / 'etc/sparky-stereo-hardware/known-machines.off').read_text().split('\n')[1], 'mbp92-gfx0')
out = json.loads(run(root, '--on', 'mbp92-gfx0').stdout)
check('--on: written again with the table', (ran(), out['corrections'][0]['on'], (root / 'etc/sparky-stereo-hardware/known-machines.off').exists()),
      (['update-initramfs -u -k all'], True, False))
check('a correction of another machine cannot be switched here', 'no correction named imac141-gpe06 applies' in run(root, '--off', 'imac141-gpe06', ok=False).stderr, True)
(work / 'fail').write_text('')
err = run(root, '--off', 'mbp92-gfx0', ok=False).stderr
kept = root / 'var/lib/sparky-stereo-problems/sparky-stereo-hardware_known-machines.json'
check('the boot images cannot be written: said, exit status 1, kept by the engine with its repair',
      ('update-initramfs -u -k all failed (status 3)' in err, kept.exists() and json.loads(kept.read_text()).get('repair')),
      (True, [['/usr/bin/sparky-stereo-known-machines', '--apply']]))
ran()
(work / 'fail').unlink()
run(root, '--apply')
check('repaired: written, and the kept problem is cleared', (ran(), kept.exists()), (['update-initramfs -u -k all'], False))

# the iMac: the option on the kernel line, in effect only after a restart
root = machine('iMac14,1')
row = json.loads(run(root, '--list').stdout)['corrections'][0]
check('iMac14,1 before the restart: on, not in effect yet', (row['id'], row['on'], row['in_effect'], row['option']), ('imac141-gpe06', True, False, 'acpi_mask_gpe=0x06'))
run(root, '--apply')
check('the menu has the option on its Linux line', 'acpi_mask_gpe=0x06' in (root / 'boot/grub/grub.cfg').read_text(), True)
(root / 'proc/cmdline').write_text('BOOT_IMAGE=/boot/vmlinuz-7.3.4 ro quiet acpi_mask_gpe=0x06\n')
check('after the restart: in effect', json.loads(run(root, '--list').stdout)['corrections'][0]['in_effect'], True)
ran()
run(root, '--off', 'imac141-gpe06')
check('--off: the menu is written again without it', (ran(), 'acpi_mask_gpe' in (root / 'boot/grub/grub.cfg').read_text()), (['update-grub '], False))

# a table nobody reviewed is refused by name
table = json.loads((recipe / 'share/known-machines.json').read_text())
for bad, words in (({'id': 'x', 'kind': 'command', 'run': 'rm -rf /', 'message': 1}, 'no reviewed handler'),
                   ({'id': 'x', 'kind': 'kernel-option', 'option': 'init=/bin/sh quiet', 'message': 1}, 'one option of the form'),
                   ({'id': 'x', 'kind': 'acpi-table', 'table': '../../etc/passwd.aml', 'message': 1}, 'names one table file'),
                   ({'id': 'x', 'kind': 'acpi-table', 'table': 'missing.aml', 'message': 1}, 'not in the package')):
    broken = json.loads(json.dumps(table))
    broken['machines'][0]['corrections'] = [bad]
    path = work / 'broken.json'
    path.write_text(json.dumps(broken))
    check('refused: %s' % bad['kind'] + ' ' + str(bad.get('option') or bad.get('table') or bad.get('run')),
          words in run(machine('x'), '--table', str(path), '--list', ok=False).stderr, True)
print('== ' + ('ALL PASS' if not fails else '%d FAILED' % fails))
sys.exit(1 if fails else 0)
