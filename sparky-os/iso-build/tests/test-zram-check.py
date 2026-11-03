#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/03
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/03
"""The zram and zswap gate against fixture packages (built with dpkg-deb) and fixture image roots: every rule refuses
what it is for and names the file and line, and what is allowed (Conflicts, zswap.enabled=0, comments, listing zram
devices, documentation) passes. Needs python3 and dpkg-deb. SUBJECT selects another zram-check.py."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SUBJECT = Path(os.environ.get('SUBJECT', Path(__file__).resolve().parents[1] / 'zram-check.py'))
spec = importlib.util.spec_from_file_location('zram_check', SUBJECT)
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)

CONTROL = 'Package: {name}\nVersion: 1.0\nArchitecture: all\nMaintainer: Test <test@example.org>\n{fields}Description: fixture\n fixture\n'


class Fixtures(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name)

    def deb(self, name='fixture', fields='', files=None, scripts=None):
        root = self.dir / f'tree-{name}-{len(list(self.dir.iterdir()))}'
        (root / 'DEBIAN').mkdir(parents=True)
        (root / 'DEBIAN/control').write_text(CONTROL.format(name=name, fields=fields))
        for script, text in (scripts or {}).items():
            (root / 'DEBIAN' / script).write_text(text)
            (root / 'DEBIAN' / script).chmod(0o755)
        for path, content in (files or {}).items():
            target = root / path.lstrip('/')
            target.parent.mkdir(parents=True, exist_ok=True)
            if isinstance(content, tuple):
                target.symlink_to(content[1])
            elif isinstance(content, bytes):
                target.write_bytes(content)
            else:
                target.write_text(content)
        out = self.dir / f'{name}_1.0_all.deb'
        subprocess.run(['dpkg-deb', '--root-owner-group', '-Zxz', '-b', str(root), str(out)], check=True,
                       capture_output=True)
        return out

    def findings(self, deb):
        findings, error = gate.check_deb(deb)
        self.assertIsNone(error)
        return findings

    def assertRefused(self, deb, *parts):
        found = self.findings(deb)
        self.assertTrue(found, 'nothing found')
        for part in parts:
            self.assertTrue(any(part in f for f in found), f'{part!r} not in {found}')
        return found

    def assertPassed(self, deb):
        self.assertEqual(self.findings(deb), [])


class Packages(Fixtures):
    def test_relations_that_pull_a_zram_package(self):
        self.assertRefused(self.deb(fields='Depends: libc6, systemd-zram-generator (>= 1.0)\n'),
                           'DEBIAN/control:5: Depends: systemd-zram-generator')
        self.assertRefused(self.deb(fields='Recommends: foo | zram-tools\n'), 'Recommends: zram-tools')
        self.assertRefused(self.deb(fields='Suggests: zram-config\n'), 'Suggests: zram-config')
        self.assertRefused(self.deb(fields='Pre-Depends: zram-generator:amd64\n'), 'Pre-Depends: zram-generator')
        self.assertRefused(self.deb(fields='Provides: systemd-zram-generator\n'), 'Provides: systemd-zram-generator')

    def test_relations_that_keep_it_out_pass(self):
        self.assertPassed(self.deb(fields='Conflicts: systemd-zram-generator, zram-tools\nBreaks: zram-config\n'
                                          'Replaces: zram-generator\nDepends: systemd-zram-generator-doc\n'))

    def test_zram_generator_configuration(self):
        conf = '# ours\n\n[zram0]\nzram-size = ram / 2\n'
        self.assertRefused(self.deb(files={'/usr/lib/systemd/zram-generator.conf.d/50-x.conf': conf}),
                           '/usr/lib/systemd/zram-generator.conf.d/50-x.conf:3: [zram0] (a zram-generator configuration)')
        self.assertRefused(self.deb(files={'/etc/systemd/zram-generator.conf': ''}), '/etc/systemd/zram-generator.conf: a')

    def test_zram_tools_and_units_and_the_former_switch(self):
        self.assertRefused(self.deb(files={'/etc/default/zramswap': 'PERCENT=50\n'}), "zram-tools' zramswap")
        self.assertRefused(self.deb(files={'/usr/lib/systemd/system/dev-zram0.swap': '[Swap]\n'}), 'a zram unit')
        self.assertRefused(self.deb(files={'/etc/systemd/system/swap.target.wants/systemd-zram-setup@zram0.service':
                                           ('link', '/usr/lib/systemd/system/systemd-zram-setup@.service')}), 'a zram unit')
        self.assertRefused(self.deb(files={'/usr/libexec/sparky-stereo/zram-auto': '#!/bin/sh\n'}),
                           "the edition's former zram switch")

    def test_kernel_command_lines(self):
        for value in ('zswap.enabled=1', 'zswap.enabled=Y', 'zswap.enabled=y', 'zswap.enabled=true', 'zswap.enabled=on',
                      'zswap.enabled', 'systemd.zram', 'systemd.zram=1'):
            with self.subTest(value=value):
                self.assertRefused(self.deb(files={'/etc/default/grub.d/50-x.cfg':
                                                   f'# x\nGRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT {value}"\n'}),
                                   '/etc/default/grub.d/50-x.cfg:2:')
        for value in ('zswap.enabled=0', 'zswap.enabled=N', 'zswap.enabled=off', 'systemd.zram=0', 'xzswap.enabled=1'):
            with self.subTest(value=value):
                self.assertPassed(self.deb(files={'/etc/default/grub.d/50-x.cfg': f'GRUB_CMDLINE_LINUX="{value}"\n'}))
        self.assertPassed(self.deb(files={'/etc/default/grub.d/50-x.cfg': '# zswap.enabled=1 is forbidden\n'}))

    def test_kernel_configuration(self):
        self.assertRefused(self.deb(files={'/boot/config-7.3.1-test': 'CONFIG_ZSWAP=y\nCONFIG_ZSWAP_DEFAULT_ON=y\n'}),
                           '/boot/config-7.3.1-test:2: CONFIG_ZSWAP_DEFAULT_ON=y')
        self.assertPassed(self.deb(files={'/boot/config-7.3.1-test': 'CONFIG_ZSWAP=y\n# CONFIG_ZSWAP_DEFAULT_ON is not set\n'
                                          'CONFIG_ZRAM=m\n'}))

    def test_zramctl_sysfs_swap_and_modules(self):
        refused = {
            '/usr/sbin/a': '#!/bin/sh\ndev=$(zramctl --find --size 4G)\n',
            '/usr/sbin/b': '#!/bin/sh\nzramctl -s 4G /dev/zram0\n',
            '/usr/sbin/c': '#!/bin/sh\necho zstd > /sys/block/zram0/comp_algorithm\n',
            '/usr/sbin/d': '#!/bin/sh\ncat /sys/class/zram-control/hot_add > /tmp/n\n',
            '/usr/sbin/e': '#!/bin/sh\nmkswap /dev/zram0 && swapon -p 100 /dev/zram0\n',
            '/usr/sbin/f': '#!/bin/sh\nmodprobe zram num_devices=1\n',
            '/usr/sbin/g': '#!/bin/sh\necho 1 > /sys/module/zswap/parameters/enabled\n',
            '/usr/lib/tmpfiles.d/x.conf': 'w /sys/module/zswap/parameters/enabled - - - - Y\n',
            '/usr/lib/modules-load.d/x.conf': '# modules\nzram\n',
            '/usr/lib/modprobe.d/x.conf': 'options zram num_devices=2\n',
            '/etc/modprobe.d/y.conf': 'options zswap enabled=1\n',
            '/usr/lib/udev/rules.d/60-x.rules': 'KERNEL=="zram0", ATTR{disksize}="4G", TAG+="systemd"\n',
            '/etc/fstab': '/dev/zram0 none swap defaults,pri=100 0 0\n',
            '/usr/lib/systemd/system/x.swap': '[Swap]\nWhat=/dev/zram0\n',
        }
        for path, text in refused.items():
            with self.subTest(path=path):
                self.assertRefused(self.deb(files={path: text}), path + ':')
        allowed = {
            '/usr/bin/a': '#!/bin/sh\nzramctl --output NAME,DISKSIZE --noheadings\n',
            '/usr/bin/b': '#!/bin/sh\ncat /sys/block/zram0/disksize\n',
            '/usr/bin/c': '#!/bin/sh\necho N > /sys/module/zswap/parameters/enabled\n',
            '/usr/bin/d': '#!/bin/sh\nmodprobe -r zram\n',
            '/usr/lib/tmpfiles.d/x.conf': 'w /sys/module/zswap/parameters/enabled - - - - N\n',
            '/usr/lib/udev/rules.d/60-x.rules': 'KERNEL=="zram0", ATTR{disksize}=="0", GOTO="end"\n',
            '/usr/bin/e': '#!/bin/sh\n# zramctl --find --size 4G was the old way\n',
            '/etc/modules': 'zram\n# above: in /etc/modules too\n',
        }
        for path, text in allowed.items():
            with self.subTest(path=path):
                if path == '/etc/modules':
                    self.assertRefused(self.deb(files={path: text}), '/etc/modules:1: zram')
                else:
                    self.assertPassed(self.deb(files={path: text}))

    def test_maintainer_scripts(self):
        self.assertRefused(self.deb(scripts={'postinst': '#!/bin/sh\nset -e\nswapon /dev/zram0\n'}),
                           'DEBIAN/postinst:3: swapon /dev/zram0')

    def test_compiled_files(self):
        elf = b'\x7fELF' + b'\0' * 60 + 'path=/etc/default/sparky-stereo-zram'.encode('utf-16-le') + b'\0' * 8
        found = self.assertRefused(self.deb(files={'/usr/lib/kf6/kauth/libexec/helper': elf}),
                                   '/usr/lib/kf6/kauth/libexec/helper: byte 100: "sparky-stereo-zram"')
        self.assertEqual(len(found), 1)
        self.assertRefused(self.deb(files={'/usr/lib/x/plugin.so': b'\x7fELF\0\0zram-generator.conf\0'}), 'zram-generator.conf')
        self.assertPassed(self.deb(files={'/usr/share/x/picture.png': b'\x89PNG\0\0sparky-stereo-zram\0'}))

    def test_documentation_is_not_read(self):
        self.assertPassed(self.deb(files={'/usr/share/doc/x/README': 'GRUB_CMDLINE_LINUX="zswap.enabled=1"\n',
                                          '/usr/share/man/man8/x.8': 'zramctl --find --size 4G\n',
                                          '/usr/share/bash-completion/completions/zramctl': 'zramctl --size 4G\n'}))

    def test_clean_package_unreadable_package_and_companions(self):
        clean = self.deb(name='clean', files={'/usr/bin/x': '#!/bin/sh\necho ok\n'})
        broken = self.dir / 'broken_1.0_all.deb'
        broken.write_bytes(b'not a package')
        companion = self.dir / 'other-lc-hr_1.0_all.deb'
        companion.write_bytes(b'not read')
        findings, errors, what = gate.check_debs([str(clean), str(broken), str(companion)], 2)
        self.assertEqual(findings, [])
        self.assertEqual(len(errors), 1)
        self.assertIn('broken_1.0_all.deb: cannot be read', errors[0])
        self.assertIn('2 package(s), 1 refused (1 -dbgsym and -lc-hr', what)

    def test_exit_status(self):
        clean = self.deb(name='clean', files={'/usr/bin/x': '#!/bin/sh\necho ok\n'})
        bad = self.deb(name='bad', fields='Depends: systemd-zram-generator\n')
        run = lambda *a: subprocess.run([sys.executable, str(SUBJECT), *a], capture_output=True, text=True)
        ok = run('--debs', str(clean))
        self.assertEqual(ok.returncode, 0, ok.stderr)
        self.assertIn('passed', ok.stdout)
        refused = run('--debs', str(clean), str(bad))
        self.assertEqual(refused.returncode, 1)
        self.assertIn('bad_1.0_all.deb: DEBIAN/control:5: Depends: systemd-zram-generator', refused.stderr)
        listed = self.dir / 'list'
        listed.write_text(f'{clean}\n{bad}\n')
        self.assertEqual(run('--debs-file', str(listed)).returncode, 1)
        self.assertEqual(run('--debs-file', str(self.dir / 'missing')).returncode, 1)


class Images(Fixtures):
    def image(self, packages, files=None):
        root = self.dir / 'root'
        (root / 'var/lib/dpkg').mkdir(parents=True)
        (root / 'var/lib/dpkg/status').write_text(''.join(
            f'Package: {name}\nStatus: install ok installed\nVersion: 1\n{fields}\n' for name, fields in packages))
        for path, content in (files or {}).items():
            target = root / path.lstrip('/')
            target.parent.mkdir(parents=True, exist_ok=True)
            if isinstance(content, tuple):
                target.symlink_to(content[1])
            else:
                target.write_text(content)
        return root

    def test_clean_image(self):
        root = self.image([('systemd', 'Depends: libc6\n'), ('sparky-stereo-kernel-settings',
                                                              'Conflicts: systemd-zram-generator, zram-tools\n')],
                          {'/etc/default/grub': 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"\n',
                           '/boot/config-7.3.1-x': '# CONFIG_ZSWAP_DEFAULT_ON is not set\n',
                           '/usr/sbin/zramctl': '#!/bin/sh\n# stands for util-linux\n'})
        findings, errors, what = gate.check_image(root, [])
        self.assertEqual((findings, errors), ([], []))
        self.assertIn('files read', what)

    def test_installed_packages_and_files(self):
        root = self.image([('systemd-zram-generator', ''), ('x', 'Recommends: zram-tools\n')],
                          {'/etc/default/grub': '# x\nGRUB_CMDLINE_LINUX_DEFAULT="quiet zswap.enabled=1"\n',
                           '/boot/config-7.3.1-x': 'CONFIG_ZSWAP_DEFAULT_ON=y\n',
                           '/usr/lib/systemd/zram-generator.conf': '[zram0]\n',
                           '/etc/systemd/system/swap.target.wants/systemd-zram-setup@zram0.service':
                               ('link', '/usr/lib/systemd/system/systemd-zram-setup@.service'),
                           '/var/lib/dpkg/info/x.postinst': '#!/bin/sh\nzramctl --find --size 1G\n'})
        menu = self.dir / 'grub.cfg'
        menu.write_text('menuentry x {\n  linux /live/vmlinuz boot=live systemd.zram=1\n}\n')
        findings, errors, _ = gate.check_image(root, [str(menu)])
        self.assertEqual(errors, [])
        for part in ('/var/lib/dpkg/status: systemd-zram-generator is installed', '/var/lib/dpkg/status: x:4: Recommends: zram-tools',
                     '/etc/default/grub:2:', '/boot/config-7.3.1-x:1: CONFIG_ZSWAP_DEFAULT_ON=y',
                     '/usr/lib/systemd/zram-generator.conf:1: [zram0]', 'systemd-zram-setup@zram0.service: a zram unit',
                     '/var/lib/dpkg/info/x.postinst:2:', f'{menu}:2:'):
            self.assertTrue(any(part in f for f in findings), f'{part!r} not in {findings}')

    def test_image_without_status_is_refused(self):
        root = self.dir / 'empty'
        root.mkdir()
        findings, errors, _ = gate.check_image(root, [])
        self.assertEqual(len(errors), 1)
        self.assertEqual(gate.report(findings, errors, 'x'), 1)


if __name__ == '__main__':
    unittest.main()
