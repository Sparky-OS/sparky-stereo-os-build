#!/usr/bin/python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/27
# Copyright 2026 under the GNU GPL3 License
"""Tests of the anti-cheat start (sparky-stereo-boot 0.1.17, row 190), each in a fake root.

Run as root in a container with grub-common (grub-editenv), grub-efi-amd64-bin and grub-efi-amd64-signed (an unsigned
and a Debian-signed EFI image), sbsigntool, openssl and python3, with the problems engine installed:
  anticheat-tests.py PACKAGE_FOLDER
SPARKY_STEREO_TEST_KERNEL=PATH adds a row for a real kernel image signed with the edition's key (its certificate is
the package's own, secureboot/sparky-stereo-secureboot-2026.der of the build tree).
"""
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import uuid

PKG = os.path.abspath(sys.argv[1])
LIB = os.path.join(PKG, 'lib')
FIX = os.path.join(PKG, 'tests', 'fixtures')
MODULE = os.path.join(LIB, 'anticheat.py')
TREE_CERT = os.path.normpath(os.path.join(PKG, '..', '..', 'secureboot', 'sparky-stereo-secureboot-2026.der'))
results = []


def check(name, ok, detail=''):
    results.append(ok)
    print('%s %s%s' % ('PASS' if ok else 'FAIL', name, ('' if ok else ': ' + detail)))


def env_for(root, **extra):
    env = dict(os.environ)
    env.update({'SPARKY_STEREO_ROOT': root, 'SPARKY_STEREO_LANG_DIR': os.path.join(PKG, 'lang'), 'LANG': 'en_US.UTF-8',
                'SPARKY_STEREO_LIB': LIB})
    env.update(extra)
    return env


def run(root, *args, **extra):
    return subprocess.run([sys.executable, MODULE] + list(args), env=env_for(root, **extra), capture_output=True,
                          text=True, timeout=120)


def fake(path, body):
    with open(path, 'w') as handle:
        handle.write('#!/bin/sh\n' + body + '\n')
    os.chmod(path, 0o755)
    return path


def new_root():
    root = tempfile.mkdtemp(prefix='ac190-')
    for d in ('etc/default', 'var/lib/sparky-stereo-boot', 'boot/grub', 'sys/firmware/efi/efivars', 'proc/sys/kernel',
              'sys/kernel/security', 'sys/class', 'sys/kernel/iommu_groups', 'sys/power', 'sys/module', 'run',
              'var/lib/sparky-stereo-problems'):
        os.makedirs(os.path.join(root, d), exist_ok=True)
    return root


# ---------------------------------------------------------------- the entry, from Debian's 10_linux output
sys.path.insert(0, LIB)
os.environ['SPARKY_STEREO_LANG_DIR'] = os.path.join(PKG, 'lang')
import anticheat  # noqa: E402

fixture = open(os.path.join(FIX, 'debian-10_linux.out')).read()
with_args = fixture.replace(' quiet splash ', ' quiet splash ' + ' '.join(anticheat.ARGS) + ' ')
entry, kernel = anticheat.make_entry(with_args, anticheat.strings('en'))
check('entry: the first 10_linux entry, renamed and under its own id',
      entry is not None and entry.startswith("menuentry 'Sparky GNU/Linux, anti-cheat start' --class sparky")
      and "$menuentry_id_option 'gnulinux-sparky-stereo-anticheat' {" in entry and entry.rstrip().endswith('}')
      and len(re.findall(r'^\s*menuentry ', entry, re.M)) == 1 and 'submenu' not in entry, repr(entry))
check('entry: the newest kernel', kernel == '7.3.1-stereo3d16', str(kernel))
check('entry: the anti-cheat kernel line', entry is not None and all(a in entry for a in anticheat.ARGS)
      and '${sparky_stereo_boot}' in entry and '${sparky_stereo_check}' in entry)
check('entry: refused without the anti-cheat arguments (10_linux did not take them)',
      anticheat.make_entry(fixture, anticheat.strings('en')) == (None, None))
check('entry: refused for empty output', anticheat.make_entry('', anticheat.strings('en')) == (None, None))
quoted = fixture.replace("menuentry 'Sparky GNU/Linux'", "menuentry 'Sparky'\\''s Linux'", 1).replace(
    ' quiet splash ', ' quiet splash lockdown=integrity ')
e, _ = anticheat.make_entry(quoted, {'LOCAL110': "%s, l'anti-triche"})
check("entry: a title with ' stays one GRUB word", e is not None and e.startswith(
    "menuentry 'Sparky'\\''s Linux, l'\\''anti-triche' --class"), repr(e and e.splitlines()[0]))
check('kernel line: lsm= of the person gains bpf', anticheat._kernel_args('ro lsm=landlock,lockdown,yama')[-1]
      == 'lsm=landlock,lockdown,yama,bpf')
check('kernel line: no lsm= of the person, nothing added', anticheat._kernel_args('ro quiet') == anticheat.ARGS)
check('kernel line: an lsm= with bpf is left alone', anticheat._kernel_args('lsm=bpf,landlock') == anticheat.ARGS)

# ---------------------------------------------------------------- update-grub: the entry and where GRUB keeps a request
work = tempfile.mkdtemp(prefix='ac190-bin-')
linux = fake(os.path.join(work, '10_linux'), "sed \"s| quiet splash | quiet splash $GRUB_CMDLINE_LINUX_DEFAULT |\" %s"
             % os.path.join(FIX, 'debian-10_linux.out'))
broken = fake(os.path.join(work, '10_linux.broken'), 'exit 0')


def probe(fs_boot, esp_fs='fat', esp_uuid='ABCD-1234'):
    return fake(os.path.join(work, 'probe-%s' % fs_boot), '''
for a; do last=$a; done
case "$1:$last" in
--target=abstraction:*) echo "" ;;
--target=fs:*/boot/efi) echo %s ;;
--target=fs:*) echo %s ;;
--target=fs_uuid:*/boot/efi) echo %s ;;
esac''' % (esp_fs, fs_boot, esp_uuid))


root = new_root()
done = run(root, 'grub', SPARKY_GRUB_10_LINUX=linux, SPARKY_GRUB_PROBE=probe('ext2'), GRUB_CMDLINE_LINUX_DEFAULT='quiet')
state = open(os.path.join(root, 'var/lib/sparky-stereo-boot/anticheat.entry')).read() if os.path.exists(
    os.path.join(root, 'var/lib/sparky-stereo-boot/anticheat.entry')) else ''
check('update-grub: the entry on a UEFI start with a writable /boot/grub', done.returncode == 0
      and "'gnulinux-sparky-stereo-anticheat'" in done.stdout and 'lockdown=integrity' in done.stdout
      and 'sparky_anticheat_once' not in done.stdout, done.stdout + done.stderr)
check('update-grub: the one-time restart is offered (grubenv)', state == 'ENTRY=gnulinux-sparky-stereo-anticheat\n'
      'PLACE=grubenv\nKERNEL=7.3.1-stereo3d16\n', state)
check('update-grub: said (LOCAL105)', 'Anti-cheat start: GRUB' in done.stderr and '7.3.1-stereo3d16' in done.stderr,
      done.stderr)

root = new_root()
os.makedirs(os.path.join(root, 'boot/efi/EFI'), exist_ok=True)
done = run(root, 'grub', SPARKY_GRUB_10_LINUX=linux, SPARKY_GRUB_PROBE=probe('btrfs'), GRUB_CMDLINE_LINUX_DEFAULT='quiet')
block = os.path.join(root, 'boot/efi/EFI/sparky-stereo-boot/grubenv')
state = open(os.path.join(root, 'var/lib/sparky-stereo-boot/anticheat.entry')).read() if os.path.exists(
    os.path.join(root, 'var/lib/sparky-stereo-boot/anticheat.entry')) else ''
check('update-grub: btrfs /boot/grub, the request kept on the EFI system partition',
      'PLACE=esp:ABCD-1234:/EFI/sparky-stereo-boot/grubenv' in state and os.path.getsize(block) == 1024, state)
check('update-grub: the ESP reader before the entry', 'search --no-floppy --fs-uuid --set=sparky_anticheat_esp ABCD-1234'
      in done.stdout and 'set default="gnulinux-sparky-stereo-anticheat"' in done.stdout
      and done.stdout.index('sparky_anticheat_esp') < done.stdout.index('menuentry'), done.stdout)

root = new_root()
done = run(root, 'grub', SPARKY_GRUB_10_LINUX=linux, SPARKY_GRUB_PROBE=probe('btrfs'), GRUB_CMDLINE_LINUX_DEFAULT='quiet')
check('update-grub: nowhere to keep a request, entry kept, restart not offered, said (LOCAL106)',
      "'gnulinux-sparky-stereo-anticheat'" in done.stdout
      and not os.path.exists(os.path.join(root, 'var/lib/sparky-stereo-boot/anticheat.entry'))
      and 'cannot keep a one-time request' in done.stderr and '(btrfs)' in done.stderr, done.stderr)

root = new_root()
shutil.rmtree(os.path.join(root, 'sys/firmware/efi'))
done = run(root, 'grub', SPARKY_GRUB_10_LINUX=linux, SPARKY_GRUB_PROBE=probe('ext2'))
check('update-grub: BIOS start, no entry and no restart, said (LOCAL107)', done.stdout == ''
      and not os.path.exists(os.path.join(root, 'var/lib/sparky-stereo-boot/anticheat.entry'))
      and 'started without UEFI' in done.stderr, done.stdout + done.stderr)

root = new_root()
open(os.path.join(root, 'etc/default/sparky-stereo-boot'), 'w').write('SPARKY_STEREO_ANTICHEAT=no\n')
done = run(root, 'grub', SPARKY_GRUB_10_LINUX=linux, SPARKY_GRUB_PROBE=probe('ext2'))
check('update-grub: SPARKY_STEREO_ANTICHEAT=no, none, said (LOCAL108)', done.stdout == ''
      and 'SPARKY_STEREO_ANTICHEAT=no' in done.stderr, done.stderr)

root = new_root()
done = run(root, 'grub', SPARKY_GRUB_10_LINUX=broken, SPARKY_GRUB_PROBE=probe('ext2'))
listed = subprocess.run(['sparky-stereo-problems', 'list'], env=env_for(root), capture_output=True, text=True)
check('update-grub: a 10_linux it cannot read, no entry, kept as a problem (LOCAL109)', done.stdout == ''
      and 'anticheat-entry' in listed.stdout, done.stderr + listed.stdout + listed.stderr)

# ---------------------------------------------------------------- the one-time restart
def restart_root(place):
    root = new_root()
    subprocess.run(['grub-editenv', os.path.join(root, 'boot/grub/grubenv'), 'create'], check=True)
    open(os.path.join(root, 'boot/grub/grub.cfg'), 'w').write(
        "menuentry 'x' $menuentry_id_option 'gnulinux-sparky-stereo-anticheat' {\n}\n")
    if place == 'esp':
        os.makedirs(os.path.join(root, 'boot/efi/EFI/sparky-stereo-boot'))
        subprocess.run(['grub-editenv', os.path.join(root, 'boot/efi/EFI/sparky-stereo-boot/grubenv'), 'create'],
                       check=True)
        place = 'esp:ABCD-1234:/EFI/sparky-stereo-boot/grubenv'
    open(os.path.join(root, 'var/lib/sparky-stereo-boot/anticheat.entry'), 'w').write(
        'ENTRY=gnulinux-sparky-stereo-anticheat\nPLACE=%s\nKERNEL=7.3.4-stereo3d18\n' % place)
    return root


def listed(path):
    return subprocess.run(['grub-editenv', path, 'list'], capture_output=True, text=True).stdout


reboot = fake(os.path.join(work, 'grub-reboot'), 'grub-editenv "$SPARKY_STEREO_ROOT/boot/grub/grubenv" set next_entry="$1"')
root = restart_root('grubenv')
status = run(root, 'status')
done = run(root, 'set', SPARKY_GRUB_REBOOT=reboot)
env_after = listed(os.path.join(root, 'boot/grub/grubenv'))
check('restart: available', status.returncode == 0 and status.stdout.strip() == 'yes', status.stdout)
check('restart set: GRUB\'s own grub-reboot names the entry once', done.returncode == 0
      and 'next_entry=gnulinux-sparky-stereo-anticheat' in env_after, done.stderr + env_after)
done = run(root, 'unset')
check('restart unset: our request taken back', done.returncode == 0
      and 'next_entry' not in listed(os.path.join(root, 'boot/grub/grubenv')), done.stderr)
subprocess.run(['grub-editenv', os.path.join(root, 'boot/grub/grubenv'), 'set', 'next_entry=gnulinux-other'], check=True)
run(root, 'unset')
check('restart unset: a request that is not ours is left', 'next_entry=gnulinux-other' in
      listed(os.path.join(root, 'boot/grub/grubenv')))
root = restart_root('esp')
done = run(root, 'set', SPARKY_GRUB_REBOOT='/bin/false')
block = os.path.join(root, 'boot/efi/EFI/sparky-stereo-boot/grubenv')
check('restart set: the ESP block where GRUB cannot write /boot/grub', done.returncode == 0
      and 'sparky_anticheat_once=1' in listed(block) and 'next_entry' not in listed(os.path.join(root, 'boot/grub/grubenv')),
      done.stderr + listed(block))
run(root, 'unset')
check('restart unset: the ESP block cleared', 'sparky_anticheat_once' not in listed(block))
root = new_root()
done = run(root, 'set', SPARKY_GRUB_REBOOT=reboot)
check('restart set: not available, exit 3, said', done.returncode == 3 and 'not available' in done.stderr, done.stderr)
check('restart status: not available, exit 3', run(root, 'status').returncode == 3)
root = restart_root('grubenv')
open(os.path.join(root, 'boot/grub/grub.cfg'), 'w').write('')
check('restart set: the menu was not written with the entry, exit 3', run(root, 'set', SPARKY_GRUB_REBOOT=reboot).returncode == 3)
root = restart_root('grubenv')
check('restart set: grub-reboot fails, exit 4, said', run(root, 'set', SPARKY_GRUB_REBOOT='/bin/false').returncode == 4)

# ---------------------------------------------------------------- what Easy Anti-Cheat would see
keys = tempfile.mkdtemp(prefix='ac190-keys-')
subprocess.run(['openssl', 'req', '-new', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '2', '-subj',
                '/CN=Row 190 throwaway test key/', '-keyout', keys + '/test.key', '-out', keys + '/test.pem'],
               check=True, capture_output=True)
subprocess.run(['openssl', 'x509', '-in', keys + '/test.pem', '-outform', 'DER', '-out', keys + '/test.der'], check=True)
unsigned = '/usr/lib/grub/x86_64-efi/monolithic/grubx64.efi'
debian_signed = '/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed'
subprocess.run(['sbsign', '--key', keys + '/test.key', '--cert', keys + '/test.pem', '--output', keys + '/signed.efi',
                unsigned], check=True, capture_output=True)


def esl(*ders):
    out = b''
    for der in ders:
        out += uuid.UUID('a5c059a1-94e4-4aa7-87b5-ab155c2bf072').bytes_le + struct.pack('<III', 28 + 16 + len(der), 0,
                                                                                          16 + len(der))
        out += uuid.UUID('605dab50-e046-4300-abb6-3dd810dd8b23').bytes_le + der
    return out


def event(pcr, kind, data):
    digest = b'\x11' * 32
    return struct.pack('<III', pcr, kind, 1) + struct.pack('<H', 0x000b) + digest + struct.pack('<I', len(data)) + data


spec = b'Spec ID Event03\x00' + struct.pack('<IBBBBI', 0, 0, 2, 0, 2, 1) + struct.pack('<HH', 0x000b, 32) + b'\x00'
header = struct.pack('<II', 0, 3) + b'\x00' * 20 + struct.pack('<I', len(spec)) + spec
good_log = header + event(0, 0x80000008, b'x' * 9) + event(4, 0x80000003, b'shim' * 8) + event(9, 0xd, b'grub.cfg')
plain_log = header + event(0, 0x80000008, b'x' * 9) + event(7, 0x800000e0, b'sb')
check('event log: entries counted, the boot manager\'s own measurement (PCR 9) found', anticheat.event_log(good_log) == (4, True),
      str(anticheat.event_log(good_log)))
check('event log: only the firmware measured, not the boot manager', anticheat.event_log(plain_log) == (3, False))
sm3_spec = b'Spec ID Event03\x00' + struct.pack('<IBBBBI', 0, 0, 2, 0, 2, 2) + struct.pack('<HHHH', 0x000b, 32, 0x0012, 32) + b'\x00'
sm3_header = struct.pack('<II', 0, 3) + b'\x00' * 20 + struct.pack('<I', len(sm3_spec)) + sm3_spec
sm3_event = struct.pack('<III', 8, 0xd, 2) + struct.pack('<H', 0x000b) + b'\x22' * 32 + struct.pack('<H', 0x0012) + b'\x33' * 32 + struct.pack('<I', 4) + b'grub'
check('event log: an SM3_256 bank beside SHA-256 is read too', anticheat.event_log(sm3_header + sm3_event) == (2, True),
      str(anticheat.event_log(sm3_header + sm3_event)))
check('event log: too short', anticheat.event_log(b'abc') == (0, False))
real = open(os.path.join(FIX, 'ovmf-swtpm-eventlog.bin'), 'rb').read()
check('event log: a real one (OVMF, swtpm, shim, GRUB 2.14): 137 entries as tpm2_eventlog counts, GRUB measured',
      anticheat.event_log(real) == (137, True), str(anticheat.event_log(real)))
test_der = open(keys + '/test.der', 'rb').read()
check('MOK list: X.509 entries read', anticheat.esl_certificates(esl(test_der, test_der)) == [test_der, test_der])


def check_root(**over):
    root = new_root()
    def put(rel, data, mode='w'):
        path = os.path.join(root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, mode) as handle:
            handle.write(data)
    put('sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c',
        b'\x06\x00\x00\x00' + (b'\x01' if over.get('sb', True) else b'\x00'), 'wb')
    put('sys/firmware/efi/efivars/SetupMode-8be4df61-93ca-11d2-aa0d-00e098032b8c', b'\x06\x00\x00\x00\x00', 'wb')
    if over.get('mok') is not None:
        put('sys/firmware/efi/efivars/MokListRT-605dab50-e046-4300-abb6-3dd810dd8b23', b'\x06\x00\x00\x00' + over['mok'], 'wb')
    if over.get('tpm', '2'):
        put('sys/class/tpm/tpm0/tpm_version_major', over.get('tpm', '2') + '\n')
    if over.get('log', good_log) is not None:
        put('sys/kernel/security/tpm0/binary_bios_measurements', over.get('log', good_log), 'wb')
    if over.get('iommu', 'DMA-FQ'):
        os.makedirs(os.path.join(root, 'sys/class/iommu/dmar0'))
        put('sys/kernel/iommu_groups/0/type', over.get('iommu', 'DMA-FQ') + '\n')
    put('sys/kernel/security/lockdown', over.get('lockdown', 'none [integrity] confidentiality') + '\n')
    put('sys/kernel/security/lsm', over.get('lsm', 'lockdown,capability,landlock,yama,apparmor,bpf'))
    put('proc/sys/kernel/kexec_load_disabled', over.get('kexec', '1') + '\n')
    put('proc/cmdline', over.get('cmdline', 'BOOT_IMAGE=/boot/vmlinuz root=UUID=1 ro lockdown=integrity '
                                 'sysctl.kernel.kexec_load_disabled=1 nohibernate sparky_stereo.anticheat=1') + '\n')
    put('sys/power/disk', over.get('disk', '[disabled]') + '\n')
    for name, taint in over.get('modules', []):
        put('sys/module/%s/taint' % name, taint + '\n')
    put('proc/sys/kernel/tainted', over.get('tainted', '0') + '\n')
    if over.get('vendor'):
        put('sys/class/dmi/id/sys_vendor', over['vendor'] + '\n')
    if over.get('chassis'):
        put('sys/class/dmi/id/chassis_type', over['chassis'] + '\n')
    return root


def rows(root, image, cert=keys + '/test.der', as_json=True):
    done = run(root, 'check', '--json', SPARKY_STEREO_KERNEL_IMAGE=image, SPARKY_STEREO_EDITION_CERT=cert)
    data = json.loads(done.stdout)
    return done.returncode, {r['id']: (r['state'], r['text']) for r in data['rows']}, data


code, got, data = rows(check_root(), keys + '/signed.efi')
check('check: JSON with the source and the anti-cheat start', data['anticheatStart'] is True and 'Epic' in data['source'])
check('check: Secure Boot on', got['secure-boot'][0] == 'met', str(got['secure-boot']))
check('check: kernel signed with the edition key, not on Epic\'s list', got['kernel-key'] == (
    'not-met', "The kernel is signed with the Sparky Stereo OS key, which is not on Epic's list of well-known keys."),
      str(got['kernel-key']))
check('check: no MOK list, met', got['mok'][0] == 'met')
check('check: no out-of-tree module, met', got['modules'][0] == 'met')
check('check: TPM 2.0 met', got['tpm'][0] == 'met')
check('check: measured boot with the boot manager, 4 entries', got['measured-boot'] == (
    'met', "The firmware's measured boot log is present (4 entries), with the boot manager's measurement."),
      str(got['measured-boot']))
check('check: IOMMU translated', got['iommu'][0] == 'met' and 'dmar0' in got['iommu'][1])
check('check: lockdown integrity', got['lockdown'] == ('met', 'Kernel lockdown is on (integrity).'))
check('check: kexec disabled from the kernel\'s start', got['kexec'][0] == 'met')
check('check: BPF LSM', got['bpf-lsm'][0] == 'met')
check('check: hibernation off said', got['hibernation'][0] == 'info')
check('check: exit 1 while a requirement is not met', code == 1)

code, got, _ = rows(check_root(sb=False, mok=esl(test_der), tpm='', log=None, iommu='identity', lockdown='[none] integrity confidentiality',
                               lsm='lockdown,capability,yama', kexec='1', cmdline='root=UUID=1 ro quiet', disk='[platform] shutdown',
                               modules=[('ac190fake', 'OE')]), debian_signed)
check('check: Secure Boot off, not met, how to turn it on', got['secure-boot'][0] == 'not-met'
      and 'Restart to UEFI setup' in got['secure-boot'][1])
check('check: an image signed by Debian, its key on Epic\'s list, met', got['kernel-key'][0] == 'met'
      and 'Debian' in got['kernel-key'][1], str(got['kernel-key']))
check('check: the edition key enrolled as MOK, not met', got['mok'][0] == 'not-met' and 'Row 190 throwaway' in got['mok'][1],
      str(got['mok']))
check('check: an unsigned module, not met', got['modules'] == ('not-met', 'Modules loaded without a signature: ac190fake.'),
      str(got['modules']))
check('check: no TPM, not met', got['tpm'][0] == 'not-met' and 'fTPM' in got['tpm'][1])
check('check: no measured boot log, not met', got['measured-boot'][0] == 'not-met')
check('check: IOMMU passthrough, not met', got['iommu'][0] == 'not-met' and 'passthrough' in got['iommu'][1])
check('check: lockdown off, not met', got['lockdown'][0] == 'not-met')
check('check: kexec disabled only after the start, unknown', got['kexec'][0] == 'unknown')
check('check: BPF LSM missing, not met', got['bpf-lsm'][0] == 'not-met')
check('check: the usual start says so', got['start'][1] == 'This is the usual start, with hibernation.')
check('check: no hibernation row when hibernation is available', 'hibernation' not in got)

code, got, _ = rows(check_root(modules=[('dkmsmod', 'OE')], cmdline='root=UUID=1 ro quiet'), keys + '/signed.efi')
check('check: a module loaded with a signature the kernel could not verify is named for the anti-cheat start',
      got.get('modules-refused', ('',))[0] == 'not-met' and 'dkmsmod' in got['modules-refused'][1], str(got.get('modules-refused')))
def rows_with_journal(root, body):
    folder = tempfile.mkdtemp(prefix='ac190-bin-')
    fake(os.path.join(folder, 'journalctl'), body)
    done = run(root, 'check', '--json', SPARKY_STEREO_KERNEL_IMAGE=keys + '/signed.efi',
               SPARKY_STEREO_EDITION_CERT=keys + '/test.der', PATH=folder + ':' + os.environ.get('PATH', ''))
    return {r['id']: (r['state'], r['text']) for r in json.loads(done.stdout)['rows']}


got = rows_with_journal(check_root(), 'exit 0')
check('check: in the anti-cheat start, a kernel log this person cannot read is said, not skipped',
      got.get('modules-refused', ('',))[0] == 'unknown' and 'only an administrator' in got['modules-refused'][1],
      str(got.get('modules-refused')))
got = rows_with_journal(check_root(), 'case "$*" in *-n\ 1*) echo "Linux version 7.3.4";; esac; exit 0')
check('check: a readable kernel log with no refusal gives no refused-modules row', 'modules-refused' not in got,
      str(got.get('modules-refused')))
got = rows_with_journal(check_root(cmdline='root=UUID=1 ro quiet'), 'exit 0')
check('check: the usual start needs no kernel log for its row', 'modules-refused' not in got, str(got.get('modules-refused')))
code, got, _ = rows(check_root(tainted=str(8192 | 4096)), keys + '/signed.efi')
check('check: an unsigned module loaded earlier in this start, the taint bit', got.get('modules-loaded', ('',))[0] == 'not-met',
      str(got.get('modules-loaded')))
code, got, _ = rows(check_root(vendor='Valve'), keys + '/signed.efi')
check('check: a Valve device is told not to turn Secure Boot on', got['secure-boot'][0] == 'not-met'
      and 'Valve' in got['secure-boot'][1], str(got['secure-boot']))
code, got, _ = rows(check_root(iommu='', chassis='31'), keys + '/signed.efi')
check('check: no IOMMU on a handheld, not required', got['iommu'][0] == 'met' and 'handheld' in got['iommu'][1], str(got['iommu']))
code, got, _ = rows(check_root(iommu=''), keys + '/signed.efi')
check('check: no IOMMU on a desktop, not met', got['iommu'][0] == 'not-met')
root = check_root(iommu='')
os.makedirs(os.path.join(root, 'sys/class/iommu/dmar0'))
code, got, _ = rows(root, keys + '/signed.efi')
check('check: an IOMMU unit with no group (not in use), not met', got['iommu'][0] == 'not-met', str(got['iommu']))
code, got, _ = rows(check_root(log=plain_log), unsigned)
check('check: an unsigned kernel image, not met', got['kernel-key'][0] == 'not-met' and 'no signature' in got['kernel-key'][1])
check('check: a measured boot log without the boot manager, not met', got['measured-boot'][0] == 'not-met')
root = check_root()
shutil.rmtree(os.path.join(root, 'sys/firmware/efi'))
code, got, _ = rows(root, unsigned)
check('check: BIOS start, no Secure Boot, no anti-cheat start offered', got['secure-boot'][0] == 'not-met'
      and 'without UEFI' in got['secure-boot'][1] and 'mok' not in got)
code, got, _ = rows(check_root(), '/nonexistent/vmlinuz')
check('check: a kernel image that cannot be read, unknown', got['kernel-key'][0] == 'unknown')
done = run(check_root(), 'check', SPARKY_STEREO_KERNEL_IMAGE=keys + '/signed.efi', SPARKY_STEREO_EDITION_CERT=keys + '/test.der')
check('check: the text form, a state word on every line', done.stdout.startswith('What Easy Anti-Cheat')
      and all(re.match(r'^\[(met|not met|unknown|note)\] ', line) for line in done.stdout.splitlines()[1:]), done.stdout)
de = run(check_root(), 'check', SPARKY_STEREO_KERNEL_IMAGE=keys + '/signed.efi', SPARKY_STEREO_EDITION_CERT=keys + '/test.der',
         LANG='de_DE.UTF-8')
check('check: German', 'Secure Boot ist an.' in de.stdout and '[erfüllt]' in de.stdout, de.stdout)
pt = run(check_root(), 'check', SPARKY_STEREO_KERNEL_IMAGE=keys + '/signed.efi', SPARKY_STEREO_EDITION_CERT=keys + '/test.der',
         LANG='pt_BR.UTF-8')
check('check: Brazilian Portuguese', 'O Secure Boot está ligado.' in pt.stdout and '[atendido]' in pt.stdout, pt.stdout)

module = os.environ.get('SPARKY_STEREO_TEST_MODULE')
if module:
    # a real module of the edition's kernel, signed at its build, and the same module with the signature taken off
    # (module_signature: twelve bytes and the signature before the magic, include/linux/module_signature.h)
    import lzma
    data = lzma.decompress(open(module, 'rb').read()) if module.endswith('.xz') else open(module, 'rb').read()
    magic = b'~Module signature appended~\n'
    sig_len = struct.unpack('>I', data[-len(magic) - 4:-len(magic)])[0]
    stripped = data[:-(len(magic) + 12 + sig_len)]
    root = check_root(cmdline='root=UUID=1 ro quiet')
    updates = os.path.join(root, 'lib/modules/7.3.4-stereo3d18/updates/dkms')
    os.makedirs(updates)
    open(os.path.join(updates, 'signedmod.ko'), 'wb').write(data)
    open(os.path.join(updates, 'bare.ko'), 'wb').write(stripped)
    done = run(root, 'check', '--json', SPARKY_STEREO_KERNEL_IMAGE=keys + '/signed.efi', SPARKY_STEREO_EDITION_CERT=keys + '/test.der',
               SPARKY_STEREO_RELEASE='7.3.4-stereo3d18')
    got = {r['id']: (r['state'], r['text']) for r in json.loads(done.stdout)['rows']}
    check('check: a module without a signature is named for the anti-cheat start, the signed one is not',
          got.get('modules-refused', ('', ''))[0] == 'not-met' and 'bare' in got['modules-refused'][1]
          and 'signedmod' not in got['modules-refused'][1] and 'would not load' in got['modules-refused'][1], str(got.get('modules-refused')))

kernel = os.environ.get('SPARKY_STEREO_TEST_KERNEL')
if kernel:
    code, got, _ = rows(check_root(), kernel, cert=TREE_CERT)
    check('check: the published kernel, signed with the edition key', got['kernel-key'][0] == 'not-met'
          and 'Sparky Stereo OS key' in got['kernel-key'][1], str(got['kernel-key']))

# ---------------------------------------------------------------- ten languages, the same arguments
langs = {}
for code in ('en', 'pl', 'pt_BR', 'fr', 'de', 'es', 'ja', 'ko', 'zh_CN', 'zh_TW'):
    langs[code] = {k: v for k, v in (line.split('=', 1) for line in open(os.path.join(PKG, 'lang', code), encoding='utf-8')
                                     if line.startswith('LOCAL'))}
wanted = ['LOCAL%d' % k for k in list(range(105, 111)) + list(range(120, 185)) if k not in (139, 144, 181)]
for code, values in langs.items():
    missing = [k for k in wanted if k not in values]
    wrong = [k for k in wanted if k in values and values[k].count('%s') != langs['en'][k].count('%s')]
    check('lang %s: every anti-cheat sentence, the same arguments' % code, not missing and not wrong, str(missing + wrong))

shutil.rmtree(work, ignore_errors=True)
shutil.rmtree(keys, ignore_errors=True)
print('%d passed, %d failed' % (results.count(True), results.count(False)))
sys.exit(0 if all(results) else 1)
