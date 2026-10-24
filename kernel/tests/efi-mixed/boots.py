#!/usr/bin/env python3
"""Boot one kernel N times in QEMU, headless, under 32-bit OVMF (EFI mixed mode) or another firmware, and classify each boot.

  boots.py --out DIR --count N [--loader grub --grub-disk IMG | --loader direct --kernel VMLINUZ --initrd IMG --append EXTRA]
           [--fw ia32|ovmf|seabios] [--sysmap System.map] [--ram 4G] [--smp 4] [--timeout 90]

grub: a disk made by mkgrubdisk.sh (Debian's GRUB, as on the ISO); its grub.cfg holds the kernel line (use panic=0 there).
direct: QEMU -kernel/-initrd; on IA32 OVMF the fw_cfg loader cannot LoadImage() an x64 PE and falls back to its legacy
loader, which enters the kernel's EFI stub through the 32-bit handover entry.
Each boot writes DIR/boot-NNN.serial and a JSON line in DIR/results.jsonl:
  result   pass (the probe init printed its facts and the system powered off), nxfault (BUG: kernel tried to execute
           NX-protected page), oops (another oops or panic), hang (timeout)
  fault    the oops lines: faulting address, #PF error code, the page-table walk, RIP
  text_pa  physical address of _text: /proc/iomem "Kernel code" for a pass; for a fault, read through QEMU's monitor from
           the kernel's high mapping in the page tables of the fault (CR3, PGD 511, PUD 510, first present PMD)
  tramp_pa text_pa plus the offset of __efi64_thunk_ret_tramp in System.map (when --sysmap is given)
"""
import argparse, json, os, re, shutil, socket, subprocess, time

ap = argparse.ArgumentParser()
ap.add_argument('--kernel')
ap.add_argument('--initrd')
ap.add_argument('--out', required=True)
ap.add_argument('--count', type=int, default=1)
ap.add_argument('--start', type=int, default=1)
ap.add_argument('--append', default='')
ap.add_argument('--fw', default='ia32', choices=['ia32', 'ovmf', 'seabios'])
ap.add_argument('--loader', default='direct', choices=['direct', 'grub'])
ap.add_argument('--grub-disk')
ap.add_argument('--root-disk', help='a second, writable disk')
ap.add_argument('--rw', action='store_true', help='the boot disk is writable (the installed system of vmrig/mkscenario.sh)')
ap.add_argument('--sysmap')
ap.add_argument('--ram', default='4G')
ap.add_argument('--smp', default='4')
ap.add_argument('--timeout', type=int, default=90)
ap.add_argument('--fwdir', default='/fw')
a = ap.parse_args()
os.makedirs(a.out, exist_ok=True)

tramp_off = None
if a.sysmap:
    syms = {}
    for l in open(a.sysmap):
        v, _, n = l.split()
        if n in ('_text', '__efi64_thunk_ret_tramp'):
            syms[n] = int(v, 16)
    tramp_off = syms['__efi64_thunk_ret_tramp'] - syms['_text']

def fw_args(vars_path):
    if a.fw == 'seabios':
        return []
    if a.fw == 'ia32':
        code = os.path.join(a.fwdir, 'ovmf32-trixie/usr/share/OVMF/OVMF32_CODE_4M.fd')
        tmpl = os.path.join(a.fwdir, 'ovmf32-trixie/usr/share/OVMF/OVMF32_VARS_4M.fd')
    else:
        code, tmpl = '/usr/share/OVMF/OVMF_CODE_4M.fd', '/usr/share/OVMF/OVMF_VARS_4M.fd'
    shutil.copy(tmpl, vars_path)
    return ['-drive', f'if=pflash,format=raw,unit=0,readonly=on,file={code}',
            '-drive', f'if=pflash,format=raw,unit=1,file={vars_path}']

class Qmp:
    def __init__(self, path):
        self.s = socket.socket(socket.AF_UNIX)
        for _ in range(200):
            try:
                self.s.connect(path); break
            except OSError:
                time.sleep(0.05)
        self.f = self.s.makefile('rw')
        json.loads(self.f.readline())
        self.cmd('qmp_capabilities')
    def cmd(self, name, **args):
        self.f.write(json.dumps({'execute': name, 'arguments': args}) + '\n'); self.f.flush()
        while True:
            line = self.f.readline()
            if not line:
                return {}
            m = json.loads(line)
            if 'return' in m or 'error' in m:
                return m
    def q(self, addr):
        out = self.cmd('human-monitor-command', **{'command-line': f'xp /1gx {addr:#x}'}).get('return', '')
        return int(out.split(':', 1)[1].split()[0], 16)

MASK = 0x000ffffffffff000

def kernel_text_pa(qmp, cr3):
    pgd = cr3 & MASK
    pud = qmp.q(pgd + 511 * 8) & MASK
    pmd_e = qmp.q(pud + 510 * 8)
    if pmd_e & 0x80:
        return None
    pmd = pmd_e & MASK
    for i in range(512):
        e = qmp.q(pmd + i * 8)
        if e & 1:
            pa = (e & MASK) if e & 0x80 else (qmp.q((e & MASK)) & MASK)
            return pa, 0xffffffff80000000 + (i << 21)
    return None

PAT = re.compile(r'(BUG:|#PF:|Oops:|PGD |RIP: |Kernel panic|kernel tried to execute|CR2: )')

with open(os.path.join(a.out, 'results.jsonl'), 'a') as results:
    for n in range(a.start, a.start + a.count):
        tag = f'boot-{n:03d}'
        serial = os.path.join(a.out, tag + '.serial')
        qmp_path = os.path.join(a.out, 'qmp.sock')
        if os.path.exists(qmp_path):
            os.unlink(qmp_path)
        vars_path = os.path.join(a.out, 'VARS.fd')
        cmd = ['qemu-system-x86_64', '-machine', 'q35,accel=kvm', '-cpu', 'host', '-smp', a.smp, '-m', a.ram,
               '-display', 'none', '-vga', 'none', '-nodefaults', '-no-reboot', '-monitor', 'none',
               '-serial', f'file:{serial}', '-qmp', f'unix:{qmp_path},server=on,wait=off', *fw_args(vars_path)]
        if a.loader == 'direct':
            cmd += ['-kernel', a.kernel, '-append', ('console=ttyS0,115200 panic=0 ' + a.append).strip()]
            if a.initrd:
                cmd += ['-initrd', a.initrd]
        else:
            cmd += ['-drive', f'file={a.grub_disk},if=none,id=d0,format=raw' + ('' if a.rw else ',readonly=on'),
                    '-device', 'virtio-blk-pci,drive=d0,bootindex=0']
            if a.root_disk:
                cmd += ['-drive', f'file={a.root_disk},if=none,id=d1,format=raw', '-device', 'virtio-blk-pci,drive=d1']
        t0 = time.time()
        p = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        qmp = Qmp(qmp_path)
        text, panicked = '', False
        while time.time() - t0 < a.timeout and p.poll() is None:
            time.sleep(0.2)
            text = open(serial, errors='replace').read() if os.path.exists(serial) else ''
            if 'Kernel panic' in text:
                time.sleep(0.5); panicked = True; break
        text = open(serial, errors='replace').read() if os.path.exists(serial) else ''
        row = dict(boot=n, fw=a.fw, loader=a.loader, append=a.append, kernel=os.path.basename(a.kernel or a.grub_disk))
        # the probe's last lines can be interleaved with the kernel's power-down messages on the serial console
        if 'EFI246-OK' in text or ('EFI246 runtime=' in text and 'reboot: Power down' in text):
            row['result'] = 'pass'
        elif 'kernel tried to execute NX-protected page' in text:
            row['result'] = 'nxfault'
        elif panicked or re.search(r'Oops:|BUG:', text):
            row['result'] = 'oops'
        else:
            row['result'] = 'hang'
        row['fault'] = [l.strip() for l in text.splitlines() if PAT.search(l)][:12]
        row['grublines'] = [l.split('EFI246 grubline: ', 1)[1].strip() for l in text.splitlines() if 'EFI246 grubline: ' in l]
        cl = re.search(r'Kernel command line: (.*)', text) or re.search(r'EFI246 cmdline=(.*)', text)
        if cl:
            row['cmdline'] = cl.group(1).strip()
        m = re.search(r'RIP: \w+:(0x)?(\w+)', text)
        if row['result'] != 'pass' and m:
            row['rip'] = '0x' + m.group(2).lstrip('0x') if not m.group(2).startswith('ffff') else m.group(2)
        m = re.search(r'PGD (\w+) P4D (\w+) PUD (\w+) PMD (\w+)(?: PTE (\w+))?', text)
        if m:
            row['walk'] = [x for x in m.groups() if x]
        io = re.search(r'EFI246 iomem ([0-9a-f]+)-[0-9a-f]+ : Kernel code', text)
        if io:
            row['text_pa'] = '0x' + io.group(1)
        elif panicked:
            cr3 = re.search(r'CR3: (\w+)', text)
            try:
                found = kernel_text_pa(qmp, int(cr3.group(1), 16)) if cr3 else None
            except Exception as e:
                found = None; row['dump_error'] = str(e)
            if found:
                row['text_pa'], row['text_va'] = hex(found[0]), hex(found[1])
        if 'text_pa' in row and tramp_off is not None:
            row['tramp_pa'] = hex(int(row['text_pa'], 16) + tramp_off)
            row['above_4g'] = int(row['tramp_pa'], 16) >= 1 << 32
        if p.poll() is None:
            p.kill()
        p.wait()
        row['seconds'] = round(time.time() - t0, 1)
        results.write(json.dumps(row) + '\n'); results.flush()
        print(n, row['result'], row.get('text_pa', ''), row.get('tramp_pa', ''), row.get('rip', ''), (row.get('walk') or [''])[-1], flush=True)
