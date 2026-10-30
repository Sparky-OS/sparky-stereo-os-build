#!/usr/bin/env python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/30
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/30
"""Tests for kernel-fixes.py on small ISO and image trees: a real Linux boot header, an initramfs made of an
uncompressed early archive and a compressed main one, dpkg's status file and the menus the packer writes.
Each red case differs from a green one in one place where an older kernel can be left, and must fail for that reason.
Needs python3, dpkg, zstd and gzip. Run: python3 sparky-os/iso-build/tests/test_kernel_fixes.py
"""
import gzip
import os
import struct
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, '..', 'kernel-fixes.py')
B12 = ('7.3.0-rc6-stereo3d12', '7.3.0~rc6-12+lc1')
B13 = ('7.3.0-stereo3d13', '7.3.0-13+lc1')
B14 = ('7.3.1-stereo3d14', '7.3.1-14+lc1')


def bzimage(release):
    b = bytearray(0x400)
    b[0:2] = b'MZ'
    b[0x202:0x206] = b'HdrS'
    struct.pack_into('<H', b, 0x206, 0x20f)
    struct.pack_into('<H', b, 0x20e, 0x100)
    text = ('%s (sparky@stereo) #%s SMP PREEMPT_DYNAMIC Sun Oct  4 20:45:25 UTC 2026' % (release, release.rsplit('d', 1)[-1])).encode()
    b[0x300:0x300 + len(text)] = text
    return bytes(b)


def cpio(entries):
    out = b''
    for i, (name, data) in enumerate(entries + [('TRAILER!!!', b'')]):
        n = name.encode() + b'\0'
        mode = 0o040755 if data is None else 0o100644
        data = data or b''
        fields = (i + 1, mode, 0, 0, 1, 0, len(data), 0, 0, 0, 0, len(n), 0)
        out += b'070701' + b''.join(b'%08X' % v for v in fields) + n + b'\0' * ((4 - (110 + len(n)) % 4) % 4)
        out += data + b'\0' * ((4 - len(data) % 4) % 4)
    return out


def initrd(release, compress='zstd'):
    early = cpio([('kernel', None), ('kernel/x86/microcode/AuthenticAMD.bin', b'\x01' * 37)])
    main = cpio([('usr', None), ('usr/lib', None), ('usr/lib/modules', None), ('usr/lib/modules/%s' % release, None),
                 ('usr/lib/modules/%s/kernel/drivers/gpu/drm/drm.ko' % release, os.urandom(3000)),
                 ('usr/lib/modules/%s/modules.dep' % release, b'kernel/drivers/gpu/drm/drm.ko:\n'), ('init', b'#!/bin/sh\n')])
    if compress == 'gzip':
        return early + gzip.compress(main)
    return early + subprocess.run(['zstd', '-q', '-c'], input=main, capture_output=True, check=True).stdout


def stanza(package, version, source, status='install ok installed'):
    return 'Package: %s\nStatus: %s\nArchitecture: amd64\nSource: %s\nVersion: %s\n' % (package, status, source, version)


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb' if isinstance(data, bytes) else 'w') as f:
        f.write(data)


GRUB = '''menuentry "Sparky Stereo OS (live)" {
    if linux /live/vmlinuz boot=live components quiet splash findiso=${iso_path}; then
        initrd /live/initrd.img
    fi
}
menuentry "Memory Test x64.efi" {
    linux   /boot/memtest86+x64.efi
}
'''
ISOLINUX = '''label live
\tmenu label Sparky Stereo OS (live)
\tkernel /live/vmlinuz
\tappend initrd=/live/initrd.img boot=live config quiet splash
label memtest
\tkernel /isolinux/memtest
'''


class KernelFixes(unittest.TestCase):

    def make(self, live=B13, modules_in_initrd=None, image=B13, compress='zstd', grub=GRUB, isolinux=ISOLINUX,
             extra_live=(), extra_status='', extra_modules=(), links=None, dkms=(), drop_image_package=False):
        t = tempfile.mkdtemp(prefix='kernel-fixes-')
        self.addCleanup(subprocess.run, ['rm', '-rf', t])
        iso, root = os.path.join(t, 'iso'), os.path.join(t, 'image')
        write(os.path.join(iso, 'live/vmlinuz'), bzimage(live[0]))
        write(os.path.join(iso, 'live/initrd.img'), initrd(modules_in_initrd or live[0], compress))
        for release in extra_live:
            write(os.path.join(iso, 'live/vmlinuz-' + release), bzimage(release))
            write(os.path.join(iso, 'live/initrd.img-' + release), initrd(release, compress))
        write(os.path.join(iso, 'boot/grub/grub.cfg'), grub)
        write(os.path.join(iso, 'boot/grub/loopback.cfg'), 'source /boot/grub/grub.cfg\n')
        write(os.path.join(iso, 'boot/memtest86+x64.efi'), b'memtest')
        write(os.path.join(iso, 'isolinux/isolinux.cfg'), isolinux)
        write(os.path.join(iso, 'isolinux/memtest'), b'memtest')
        release, version = image
        for f in ('vmlinuz', 'initrd.img', 'config', 'System.map'):
            write(os.path.join(root, 'boot', '%s-%s' % (f, release)), b'x')
        write(os.path.join(root, 'boot/mt86+x64'), b'x')
        for r in (release,) + tuple(extra_modules):
            write(os.path.join(root, 'usr/lib/modules', r, 'modules.dep'), b'')
        os.symlink('usr/lib', os.path.join(root, 'lib'))
        for name, target in (links or {'vmlinuz': 'boot/vmlinuz-' + release, 'initrd.img': 'boot/initrd.img-' + release,
                                        'vmlinuz.old': 'boot/vmlinuz-' + release, 'initrd.img.old': 'boot/initrd.img-' + release}).items():
            os.symlink(target, os.path.join(root, name))
        for r in dkms:
            os.makedirs(os.path.join(root, 'var/lib/dkms/nvidia/615.71.09', r, 'x86_64/module'))
        status = [stanza('linux-headers-' + release, version, 'linux-stereo-base'),
                  stanza('linux-libc-dev', version, 'linux-stereo-base'),
                  stanza('linux-image-sparky-stereo', version.replace('-', '+stereo3d', 1).rsplit('+lc1', 1)[0] + '+lc1',
                         'sparky-stereo-meta (20261025)'),
                  stanza('linux-base', '4.17', 'linux-base'), stanza('bash', '5.3-1', 'bash')]
        if not drop_image_package:
            status.append(stanza('linux-image-' + release, version, 'linux-stereo-base'))
        write(os.path.join(root, 'var/lib/dpkg/status'), '\n'.join(status) + '\n' + extra_status)
        return iso, root

    def run_check(self, iso, root):
        r = subprocess.run([sys.executable, SCRIPT, iso, root], capture_output=True, text=True)
        return r.returncode, r.stdout + r.stderr

    def green(self, **kw):
        rc, out = self.run_check(*self.make(**kw))
        self.assertEqual(rc, 0, out)
        self.assertIn('PASS  every kernel the ISO boots or installs carries the CVE-2026-98432 fix', out)
        self.assertNotIn('FAIL', out)
        return out

    def red(self, reason, **kw):
        rc, out = self.run_check(*self.make(**kw))
        self.assertEqual(rc, 1, out)
        self.assertIn(reason, out)
        self.assertNotIn('PASS  every kernel', out)
        return out

    def test_build_13_passes(self):
        out = self.green()
        self.assertIn('PASS  7.3.0-stereo3d13 carries the CVE-2026-98432 fix: Linux 7.3.0, linux-image-7.3.0-stereo3d13 7.3.0-13+lc1', out)
        self.assertIn('/live/initrd.img: 9 files, module trees 7.3.0-stereo3d13', out)
        self.assertIn('/boot/grub/grub.cfg: kernels /live/vmlinuz, initrds /live/initrd.img', out)

    def test_build_14_passes(self):
        self.assertIn('Linux 7.3.1, linux-image-7.3.1-stereo3d14 7.3.1-14+lc1', self.green(live=B14, image=B14))

    def test_gzip_initramfs_passes(self):
        self.green(compress='gzip')

    def fail_line(self, out, start):
        lines = [line for line in out.splitlines() if line.startswith('FAIL  ' + start)]
        self.assertEqual(len(lines), 1, out)
        return lines[0]

    def test_the_25_october_iso_fails(self):
        out = self.red('is Linux 7.3.0~rc6, older than 7.3.0~rc7: it lacks the CVE-2026-98432 fix', live=B12, image=B12)
        line = self.fail_line(out, '7.3.0-rc6-stereo3d12 (')
        for place in ('/live/vmlinuz', '/live/initrd.img (modules)', '/vmlinuz (link)', '/boot/vmlinuz-7.3.0-rc6-stereo3d12',
                      '/boot/initrd.img-7.3.0-rc6-stereo3d12', '/usr/lib/modules/7.3.0-rc6-stereo3d12'):
            self.assertIn(place, line)
        self.assertIn('FAIL  linux-image-7.3.0-rc6-stereo3d12 7.3.0~rc6-12+lc1 (linux-stereo-base, installed) is older than 7.3.0-13+lc1', out)
        self.assertIn('FAIL  linux-libc-dev 7.3.0~rc6-12+lc1', out)

    def test_old_live_kernel_fails(self):
        self.red('FAIL  7.3.0-rc6-stereo3d12 (/live/vmlinuz) is Linux 7.3.0~rc6', live=B12, modules_in_initrd=B13[0])

    def test_old_initramfs_modules_fail(self):
        self.red('FAIL  7.3.0-rc6-stereo3d12 (/live/initrd.img (modules)) is Linux 7.3.0~rc6', modules_in_initrd=B12[0])

    def test_left_module_tree_fails(self):
        self.red('FAIL  7.3.0-rc6-stereo3d12 (/usr/lib/modules/7.3.0-rc6-stereo3d12) is Linux 7.3.0~rc6', extra_modules=[B12[0]])

    def test_old_libc_dev_fails(self):
        out = self.red('FAIL  linux-libc-dev 7.3.0~rc6-12+lc1 (linux-stereo-base, installed) is older than 7.3.0-13+lc1',
                       extra_status=stanza('linux-libc-dev', B12[1], 'linux-stereo-base'))
        self.assertNotIn('FAIL  7.3.0-stereo3d13', out)

    def test_old_kernel_left_as_configuration_files_fails(self):
        self.red('FAIL  linux-image-7.3.0-rc6-stereo3d12 7.3.0~rc6-12+lc1 (linux-stereo-base, config-files) is older',
                 extra_status=stanza('linux-image-' + B12[0], B12[1], 'linux-stereo-base', 'deinstall ok config-files'))

    def test_menu_entry_for_an_old_kernel_fails(self):
        grub = GRUB + 'menuentry "Sparky Stereo OS (live, 7.3.0-rc6-stereo3d12)" {\n    if linux /live/vmlinuz-7.3.0-rc6-stereo3d12 boot=live; then\n        initrd /live/initrd.img-7.3.0-rc6-stereo3d12\n    fi\n}\n'
        out = self.red('/live/vmlinuz-7.3.0-rc6-stereo3d12', grub=grub, extra_live=[B12[0]])
        self.assertIn('/boot/grub/grub.cfg (text)', out)
        self.assertIn('/live/initrd.img-7.3.0-rc6-stereo3d12 (modules)', out)

    def test_old_release_in_menu_text_fails(self):
        self.red('FAIL  7.3.0-rc6-stereo3d12 (/isolinux/isolinux.cfg (text)) is Linux 7.3.0~rc6',
                 isolinux=ISOLINUX.replace('Sparky Stereo OS (live)', 'Sparky Stereo OS (live, 7.3.0-rc6-stereo3d12)'))

    def test_menu_naming_a_missing_kernel_fails(self):
        self.red('FAIL  /isolinux/isolinux.cfg names /live/vmlinuz2, which the ISO does not have',
                 isolinux=ISOLINUX + 'label live2\n\tkernel /live/vmlinuz2\n\tappend initrd=/live/initrd2.img boot=live\n')

    def test_link_to_an_old_kernel_fails(self):
        self.red('FAIL  7.3.0-rc6-stereo3d12 (/vmlinuz.old (link)) is Linux 7.3.0~rc6',
                 links={'vmlinuz': 'boot/vmlinuz-' + B13[0], 'vmlinuz.old': 'boot/vmlinuz-' + B12[0]})

    def test_old_dkms_build_fails(self):
        self.red('FAIL  7.3.0-rc6-stereo3d12 (/var/lib/dkms/nvidia/615.71.09/7.3.0-rc6-stereo3d12) is Linux 7.3.0~rc6', dkms=[B12[0]])

    def test_kernel_without_its_package_fails(self):
        out = self.red("belongs to no installed linux-image-7.3.0-stereo3d13 of the edition's kernel sources", drop_image_package=True)
        line = self.fail_line(out, '7.3.0-stereo3d13 (')
        for place in ('/live/vmlinuz', '/live/initrd.img (modules)', '/boot/vmlinuz-7.3.0-stereo3d13', '/usr/lib/modules/7.3.0-stereo3d13'):
            self.assertIn(place, line)

    def test_old_kernel_of_a_newer_release_name_fails(self):
        # a 7.3 release name whose package is still the rc6 build: the package version decides
        out = self.red('FAIL  7.3.0-stereo3d13 (', image=(B13[0], B12[1]))
        self.assertIn('linux-image-7.3.0-stereo3d13 7.3.0~rc6-12+lc1 is older than 7.3.0-13+lc1', out)


if __name__ == '__main__':
    unittest.main(verbosity=2)
