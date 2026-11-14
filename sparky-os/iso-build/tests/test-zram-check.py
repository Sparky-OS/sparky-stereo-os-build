#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/03
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/14 (ORDER 558: a tear-down is told from a set-up by what the unit and its script do)
"""The zram and zswap gate against fixture packages (built with dpkg-deb) and fixture image roots: every rule refuses
what it is for and names the file and line, and what is allowed (the person's Stereo APTus opt-in, Suggests,
zswap.enabled=0, comments, listing zram devices, documentation) passes. A unit that only retires zram (stops, resets,
removes, reports) passes with a note for each file and line; every set-up form inside such a unit or the script it
runs, a unit that does both and anything the gate cannot read to its end are refused. Needs python3 and dpkg-deb.
SUBJECT selects another zram-check.py; ZRAM_GATE_PACKAGES names a folder with real sparky-stereo-kernel-settings
packages (published/ and staged/) to read whole."""
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

    def deb(self, name='fixture', fields='', files=None, scripts=None, modes=None):
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
            if path in (modes or {}):
                target.chmod(modes[path])
        out = self.dir / f'{name}_1.0_all.deb'
        subprocess.run(['dpkg-deb', '--root-owner-group', '-Zxz', '-b', str(root), str(out)], check=True,
                       capture_output=True)
        return out

    def read(self, deb):
        """(findings, notes) of one package; the gate before ORDER 558 had no notes."""
        result = gate.check_deb(deb)
        self.assertIsNone(result[-1])
        return result[0], (result[1] if len(result) == 3 else [])

    def findings(self, deb):
        return self.read(deb)[0]

    def assertNoted(self, deb, *parts):
        """Passed, and every part is named by a note."""
        findings, notes = self.read(deb)
        self.assertEqual(findings, [])
        for part in parts:
            self.assertTrue(any(part in n for n in notes), f'{part!r} not in the notes {notes}')
        return notes

    def assertRefused(self, deb, *parts):
        found = self.findings(deb)
        self.assertTrue(found, 'nothing found')
        for part in parts:
            self.assertTrue(any(part in f for f in found), f'{part!r} not in {found}')
        return found

    def assertPassed(self, deb):
        self.assertEqual(self.findings(deb), [])


class Documentation(Fixtures):
    page = '# Forbidden setup examples\n\n```sh\nmodprobe zram\nzramctl --find --size 4G\n' \
           'echo 4G > /sys/block/zram0/disksize\nswapon /dev/zram0\n```\n'
    path = '/usr/share/agent-skills/developer/example/guide.md'

    def test_unrun_markdown_is_noted_in_documentation_and_skills_folders(self):
        for path in (self.path, '/usr/share/doc/example/guide.md', '/opt/example/docs/guide.markdown',
                     '/usr/share/doc/systemd/zram.md', '/usr/share/doc/example/zram-generator.conf.d/guide.md'):
            with self.subTest(path=path):
                notes = self.assertNoted(self.deb(files={path: self.page}), path + ': documentation, not run')
                self.assertEqual(len(notes), 1)
        self.assertNoted(self.deb(files={self.path: self.page,
            '/usr/share/doc/example/alias.md': ('link', self.path)}), 'documentation, not run')

    def test_shell_scripts_and_executable_or_shebang_markdown_refuse(self):
        for path, text, mode in (('/usr/libexec/example/setup.sh', self.page, 0o644),
                                 (self.path, self.page, 0o755),
                                 (self.path, '#!/bin/sh\n' + self.page, 0o644),
                                 ('/usr/share/doc/example/guide.md', self.page, 0o755),
                                 ('/usr/share/doc/example/guide.md', '#!/bin/sh\n' + self.page, 0o644)):
            with self.subTest(path=path, mode=mode, shebang=text.startswith('#!')):
                self.assertRefused(self.deb(files={path: text}, modes={path: mode}), 'zram')

    def test_extension_alone_does_not_make_a_document(self):
        for text in ('zramctl --find --size 4G\n', b'\x7fELF\0# Page\nzswap.enabled=1',
                     b'# Page\n\xff\nzramctl --find --size 4G\n'):
            with self.subTest(text=text):
                self.assertRefused(self.deb(files={self.path: text}), 'zram' if 'ELF' not in str(text) else 'zswap')
        self.assertRefused(self.deb(files={self.path: '# Page\n' + 'x' * gate.TEXT_LIMIT}), 'text limit')

    def test_markdown_in_configuration_paths_and_generator_configuration_refuse(self):
        for folder in ('/etc/sysctl.d', '/usr/lib/systemd/system', '/usr/lib/udev/rules.d',
                       '/usr/lib/modprobe.d', '/usr/lib/tmpfiles.d', '/usr/lib/modules-load.d',
                       '/var/lib/dpkg/info'):
            with self.subTest(folder=folder):
                self.assertRefused(self.deb(files={folder + '/docs/guide.md': self.page}), 'zram')
        self.assertRefused(self.deb(files={'/usr/lib/systemd/zram-generator.conf.d/guide.md':
                                           '# Configuration\n[zram0]\nzram-size = ram / 2\n'}),
                           'a zram-generator configuration')

    def test_unit_commands_sources_and_configuration_references_refuse(self):
        for setting in (f'ExecStart=/bin/sh {self.path}',
                        f'ExecStart=/bin/sh -c ". {self.path}"',
                        f'EnvironmentFile={self.path}'):
            with self.subTest(setting=setting):
                self.assertRefused(self.deb(files={self.path: self.page,
                    '/usr/lib/systemd/system/example.service': '[Service]\n' + setting + '\n'}), self.path)
        self.assertRefused(self.deb(files={self.path: self.page,
            '/usr/libexec/example/runner': '#!/bin/sh\n. ' + self.path + '\n'}), self.path)
        self.assertRefused(self.deb(files={self.path: self.page},
                                   scripts={'postinst': '#!/bin/sh\n. ' + self.path + '\n'}), self.path)
        self.assertRefused(self.deb(scripts={'postinst': '#!/bin/sh\nmodprobe zram\n'}), 'DEBIAN/postinst')

    def test_consumers_in_other_packages_and_compiled_references_refuse(self):
        doc = self.deb(name='documentation', files={self.path: self.page})
        consumer = self.deb(name='consumer', files={'/usr/bin/reader': b'\x7fELF\0' + self.path.encode() + b'\0'})
        findings, errors, _, notes = gate.check_debs([doc, consumer], 2)
        self.assertEqual(errors, [])
        self.assertTrue(any(self.path in f for f in findings), findings)
        self.assertFalse(any('documentation, not run' in n for n in notes), notes)

    def test_alias_and_relative_uppercase_references_refuse(self):
        self.assertRefused(self.deb(files={self.path: self.page,
            '/usr/libexec/example/alias': ('link', self.path),
            '/usr/lib/systemd/system/example.service': '[Service]\nExecStart=/bin/sh /usr/libexec/example/alias\n'}), self.path)
        path = self.path.replace('guide.md', 'GUIDE.MD')
        self.assertRefused(self.deb(files={path: self.page,
            '/usr/bin/reader.py': 'from pathlib import Path\nPath("GUIDE.MD").read_text()\n'}), path)
        for name in ('guide with spaces.md', 'guía.md'):
            path = str(Path(self.path).with_name(name))
            with self.subTest(name=name):
                self.assertRefused(self.deb(files={path: self.page,
                    '/usr/libexec/example/reader': '#!/bin/sh\n. "' + path + '"\n'}), path)

    def test_image_documentation_and_its_consumer(self):
        root = self.dir / 'root'
        (root / 'var/lib/dpkg').mkdir(parents=True)
        (root / 'var/lib/dpkg/status').write_text('')
        path = root / self.path.lstrip('/')
        path.parent.mkdir(parents=True)
        path.write_text(self.page)
        findings, errors, _, notes = gate.check_image(root, [])
        self.assertEqual((findings, errors), ([], []))
        self.assertTrue(any('documentation, not run' in n for n in notes), notes)
        unit = root / 'usr/lib/systemd/system/example.service'
        unit.parent.mkdir(parents=True)
        unit.write_text('[Service]\nExecStart=/bin/sh ' + self.path + '\n')
        self.assertTrue(gate.check_image(root, [])[0])

    def test_report_names_documentation_without_calling_it_a_teardown(self):
        deb = self.deb(files={self.path: self.page})
        run = subprocess.run([sys.executable, str(SUBJECT), '--debs', str(deb)], capture_output=True, text=True)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn('documentation, not run', run.stdout)
        self.assertNotIn('tear-down(s) let through', run.stdout)


class Packages(Fixtures):
    def test_relations_that_pull_a_zram_package(self):
        self.assertRefused(self.deb(fields='Depends: libc6, systemd-zram-generator (>= 1.0)\n'),
                           'DEBIAN/control:5: Depends: systemd-zram-generator')
        self.assertRefused(self.deb(fields='Recommends: foo | zram-tools\n'), 'Recommends: zram-tools')
        self.assertRefused(self.deb(fields='Pre-Depends: zram-generator:amd64\n'), 'Pre-Depends: zram-generator')
        self.assertRefused(self.deb(fields='Provides: systemd-zram-generator\n'), 'Provides: systemd-zram-generator')

    def test_relations_that_cap_the_persons_choice(self):
        # Daniel, 2026-11-03: "we don't cape user choice"; ORDER 358's kernel-settings 20261103.3 had this line
        found = self.assertRefused(self.deb(fields='Conflicts: systemd-zram-generator, zram-tools\n'),
                                   'DEBIAN/control:5: Conflicts: systemd-zram-generator', 'Conflicts: zram-tools',
                                   'keeps the person from opting in')
        self.assertEqual(len(found), 2)
        self.assertRefused(self.deb(fields='Breaks: zram-config (<< 2)\n'), 'Breaks: zram-config')

    def test_relations_that_leave_the_choice_pass(self):
        self.assertPassed(self.deb(fields='Suggests: systemd-zram-generator\nEnhances: zram-tools\n'
                                          'Replaces: zram-generator\nDepends: systemd-zram-generator-doc\n'))

    def test_the_persons_opt_in_from_stereo_aptus_passes(self):
        # an aptus://sysoth_ entry and its install case, as sparky-aptus-stereo-appcenter's system-others.html and
        # bin/aptus-app carry their entries (Daniel, 2026-11-03: "the user opt in inside stereo aptus")
        lib = '/usr/lib/sparky-aptus-appcenter'
        self.assertPassed(self.deb(name='sparky-aptus-stereo-appcenter', files={
            lib + '/system-others.html': '<td><a href="aptus://sysoth_systemd-zram-generator" class="button1">'
                                         '<img src="images/default-icon.svg" class="appicon"><br />zram swap</a>\n',
            lib + '/bin/aptus-app': '#!/bin/bash\nif [ "$1" = "systemd-zram-generator" ]; then\n\tPACKAGE="$1"\nfi\n'
                                    'apt-get install -y "$PACKAGE"\n',
            lib + '/handler': '#!/bin/bash\nCHECKSYSOTH=`echo "$CMD" | grep sysoth_`\n'}))

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
        self.assertRefused(self.deb(files={'/usr/lib/systemd/system-preset/80-x.preset': 'disable a.service\nenable dev-zram0.swap\n'}),
                           '/usr/lib/systemd/system-preset/80-x.preset:2: enable dev-zram0.swap')
        self.assertPassed(self.deb(files={'/usr/lib/systemd/system-preset/80-x.preset': 'disable dev-zram0.swap\n'}))

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
        findings, errors, what = gate.check_debs([str(clean), str(broken), str(companion)], 2)[:3]
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
        self.assertIn('opt-in from Stereo APTus is allowed', ok.stdout)
        refused = run('--debs', str(clean), str(bad))
        self.assertEqual(refused.returncode, 1)
        self.assertIn('bad_1.0_all.deb: DEBIAN/control:5: Depends: systemd-zram-generator', refused.stderr)
        self.assertIn('the person may opt in', refused.stderr)
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
                                                              'Suggests: systemd-zram-generator\n')],
                          {'/etc/default/grub': 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"\n',
                           '/boot/config-7.3.1-x': '# CONFIG_ZSWAP_DEFAULT_ON is not set\n',
                           '/usr/sbin/zramctl': '#!/bin/sh\n# stands for util-linux\n'})
        findings, errors, what = gate.check_image(root, [])[:3]
        self.assertEqual((findings, errors), ([], []))
        self.assertIn('files read', what)

    def test_installed_packages_and_files(self):
        root = self.image([('systemd-zram-generator', ''), ('x', 'Recommends: zram-tools\n'),
                           ('y', 'Conflicts: zram-tools\n')],
                          {'/etc/default/grub': '# x\nGRUB_CMDLINE_LINUX_DEFAULT="quiet zswap.enabled=1"\n',
                           '/boot/config-7.3.1-x': 'CONFIG_ZSWAP_DEFAULT_ON=y\n',
                           '/usr/lib/systemd/zram-generator.conf': '[zram0]\n',
                           '/etc/systemd/system/swap.target.wants/systemd-zram-setup@zram0.service':
                               ('link', '/usr/lib/systemd/system/systemd-zram-setup@.service'),
                           '/var/lib/dpkg/info/x.postinst': '#!/bin/sh\nzramctl --find --size 1G\n'})
        menu = self.dir / 'grub.cfg'
        menu.write_text('menuentry x {\n  linux /live/vmlinuz boot=live systemd.zram=1\n}\n')
        findings, errors, _ = gate.check_image(root, [str(menu)])[:3]
        self.assertEqual(errors, [])
        for part in ('/var/lib/dpkg/status: systemd-zram-generator is installed', '/var/lib/dpkg/status: x:4: Recommends: zram-tools',
                     '/var/lib/dpkg/status: y:4: Conflicts: zram-tools',
                     '/etc/default/grub:2:', '/boot/config-7.3.1-x:1: CONFIG_ZSWAP_DEFAULT_ON=y',
                     '/usr/lib/systemd/zram-generator.conf:1: [zram0]', 'systemd-zram-setup@zram0.service: a zram unit',
                     '/var/lib/dpkg/info/x.postinst:2:', f'{menu}:2:'):
            self.assertTrue(any(part in f for f in findings), f'{part!r} not in {findings}')

    def test_merged_usr_is_read_once(self):
        root = self.image([('x', '')], {'/usr/lib/systemd/zram-generator.conf': '[zram0]\n'})
        (root / 'lib').symlink_to('usr/lib')
        findings, errors, _ = gate.check_image(root, [])[:3]
        self.assertEqual(findings, ['/usr/lib/systemd/zram-generator.conf:1: [zram0] (a zram-generator configuration)'])

    def test_image_without_status_is_refused(self):
        root = self.dir / 'empty'
        root.mkdir()
        findings, errors, _ = gate.check_image(root, [])[:3]
        self.assertEqual(len(errors), 1)
        self.assertEqual(gate.report(findings, errors, 'x'), 1)


# ---- ORDER 558: what a zram unit does ------------------------------------------------------------------------------

SYSTEM = '/usr/lib/systemd/system/'
SCRIPT = '/usr/libexec/sparky-stereo/zram-migration'
LEFTOVER = SYSTEM + 'sparky-stereo-kernel-settings-zram-leftover.service'
FAILED = SYSTEM + 'sparky-stereo-kernel-settings-zram-failed@.service'
WANTS = SYSTEM + 'multi-user.target.wants/sparky-stereo-kernel-settings-zram-leftover.service'
SETUP_D = SYSTEM + 'systemd-zram-setup@zram0.service.d/'
SWAP_D = SYSTEM + 'dev-zram0.swap.d/'
# The files of sparky-stereo-kernel-settings 20261108.1 (ORDER 463), as its build.sh writes them
LEFTOVER_UNIT = """[Unit]
Description=Remove the compressed swap generator an older edition left installed (once)
Documentation=file:/usr/share/doc/sparky-stereo-kernel-settings/README.md
ConditionPathExists=/var/lib/sparky-stereo-kernel-settings/leftover-zram-generator

[Service]
Type=simple
ExecStart=/usr/libexec/sparky-stereo/zram-migration --purge-leftover
TimeoutStartSec=infinity
KillMode=process

[Install]
WantedBy=multi-user.target
"""
FAILED_UNIT = """[Unit]
Description=Say the failure of %i without offering to start it again

[Service]
Type=oneshot
ExecStart=/usr/libexec/sparky-stereo/zram-migration --failed %i
"""
GUARD = """[Unit]
RequiresMountsFor=/var/lib/apt /var/lib/sparky-stereo-kernel-settings
# At boot this unit is started several times; each skipped start counted toward the start limit
StartLimitIntervalSec=0
[Service]
ExecCondition=/usr/libexec/sparky-stereo/zram-migration --allow
"""
SWAP_GUARD = """[Unit]
# The generator orders this swap after its setup service, which evaluates the guard.
ConditionPathExists=!/run/sparky-stereo-kernel-settings/blocked-zram0
"""
FAILURE = """[Unit]
# The engine's generic handler (Repair: systemctl restart) is masked by name beside this one
OnFailure=sparky-stereo-kernel-settings-zram-failed@%n.service
"""
MIGRATION = Path(__file__).resolve().parents[2] / 'packages/sparky-stereo-kernel-settings' / SCRIPT.lstrip('/')
# The line of the round's fourth finding, as the installed (lean) script carries it
LINE_107 = ("""        'if [ -r /sys/block/zram0/disksize ] && [ "$(cat /sys/block/zram0/disksize)" != 0 ]; """
            """then echo 1 >/sys/block/zram0/reset; fi\\n')""")
RETIRE = """#!/bin/sh
set -e
if awk '$1 == "/dev/zram0" { f=1 } END { exit !f }' /proc/swaps; then
    systemctl stop dev-zram0.swap || true
    swapoff /dev/zram0
fi
if [ -r /sys/block/zram0/disksize ] && [ "$(cat /sys/block/zram0/disksize)" != 0 ]; then
    echo 1 >/sys/block/zram0/reset
fi
"""
PYTHON = """#!/usr/bin/python3
import subprocess
cleanup = (
    'set -e\\n'
    'swapoff /dev/zram0\\n'
    '{line}\\n')
subprocess.run(['/bin/sh', '-c', cleanup], check=True)
"""

# Every set-up form the gate knew before ORDER 558 (zramctl(8); zram.rst: disksize, comp_algorithm, max_comp_streams,
# mem_limit, backing_dev, algorithm_params, hot_add; mkswap and swapon; the module; zswap.rst: the run-time switch and
# the kernel command line), as one shell command each
KNOWN_SETUPS = (
    'zramctl --find --size 4G',
    'zramctl -s 4G /dev/zram0',
    'zramctl --algorithm zstd /dev/zram0',
    'echo 4G > /sys/block/zram0/disksize',
    'echo zstd > /sys/block/zram0/comp_algorithm',
    'echo 2 > /sys/block/zram0/max_comp_streams',
    'echo 1G > /sys/block/zram0/mem_limit',
    'echo /dev/sda5 > /sys/block/zram0/backing_dev',
    'echo "algo=zstd level=9" > /sys/block/zram0/algorithm_params',
    'cat /sys/class/zram-control/hot_add > /run/n',
    'mkswap /dev/zram0',
    'swapon -p 100 /dev/zram0',
    'modprobe zram num_devices=1',
    'echo 1 > /sys/module/zswap/parameters/enabled',
    'echo Y | tee /sys/module/zswap/parameters/enabled',
    'grub-editenv - set kernelopts="quiet zswap.enabled=1"',
    'grub-editenv - set kernelopts="quiet systemd.zram=1"',
)
# What a retiring unit or its script could also do to set zram up, and what the gate cannot read: refused there
MORE_SETUPS = (
    'id=$(cat /sys/class/zram-control/hot_add)',
    'systemctl start dev-zram0.swap',
    'systemctl enable --now zramswap.service',
    'systemctl restart systemd-zram-setup@zram0.service',
    'apt-get -y install systemd-zram-generator',
    '/usr/lib/systemd/system-generators/zram-generator --setup-device zram0',
    'zramswap start',
    'd=/sys/block/zram0; echo 4G > $d/disksize',
    'dd if=/dev/zero of=/dev/zram0 bs=1M count=1',
    'echo 1 > /sys/block/zram0/compact',
    'echo $n > /sys/block/zram0/reset',
    'eval "$ZRAM_COMMAND"',
    'systemctl mask dev-zram0.swap',
    'apt-get -y install $PACKAGE',
    'zramswap restart',
)


class TearDowns(Fixtures):
    def package(self, **more):
        files = {LEFTOVER: LEFTOVER_UNIT, FAILED: FAILED_UNIT, WANTS: ('link', '../' + Path(LEFTOVER).name),
                 SETUP_D + '50-sparky-migration.conf': GUARD, SETUP_D + '60-sparky-zram-failure.conf': FAILURE,
                 SETUP_D + '50-sparky-stereo-problems.conf': ('link', '/dev/null'),
                 SWAP_D + '50-sparky-migration.conf': SWAP_GUARD, SCRIPT: MIGRATION.read_text()}
        files.update(more)
        return self.deb(name='sparky-stereo-kernel-settings', files={k: v for k, v in files.items() if v is not None})

    def test_the_five_findings_of_round_r1114a_pass_each_with_its_note(self):
        notes = self.assertNoted(self.package(), FAILED + ':', LEFTOVER + ':', SETUP_D + '60-sparky-zram-failure.conf:',
                                 WANTS + ':', SCRIPT + ':')
        reset = [n for n in notes if SCRIPT in n and '/sys/block/zram0/reset' in n]
        self.assertEqual(len(reset), 1, notes)
        self.assertIn('a zram device reset', reset[0])
        for note in notes:
            self.assertRegex(note, r'^sparky-stereo-kernel-settings_1\.0_all\.deb: /\S+?(:\d+)?: ')

    def test_each_finding_alone_with_the_script_it_runs(self):
        for path, text in ((FAILED, FAILED_UNIT), (LEFTOVER, LEFTOVER_UNIT),
                           (SETUP_D + '60-sparky-zram-failure.conf', FAILURE)):
            with self.subTest(path=path):
                files = {path: text, SCRIPT: MIGRATION.read_text()}
                if path.endswith('.conf'):
                    files[FAILED] = FAILED_UNIT
                self.assertNoted(self.deb(files=files), path + ':')
        self.assertNoted(self.deb(files={LEFTOVER: LEFTOVER_UNIT, WANTS: ('link', '../' + Path(LEFTOVER).name),
                                         SCRIPT: MIGRATION.read_text()}), WANTS + ':')
        self.assertNoted(self.deb(files={LEFTOVER: LEFTOVER_UNIT, SCRIPT: '#!/usr/bin/python3\ncleanup = (\n' + LINE_107 + '\n'}),
                         SCRIPT + ':3:', 'a zram device reset')

    def test_the_published_drop_ins_are_read_as_what_they_are(self):
        # 20261106.1 ships these; the gate before ORDER 558 never read them, their names have no "zram"
        self.assertNoted(self.deb(files={SETUP_D + '50-sparky-migration.conf': GUARD.replace('StartLimitIntervalSec=0\n', ''),
                                         SWAP_D + '50-sparky-migration.conf': SWAP_GUARD, SCRIPT: MIGRATION.read_text()}),
                         SETUP_D + '50-sparky-migration.conf:', SWAP_D + '50-sparky-migration.conf:')

    def test_a_shell_script_that_only_retires(self):
        unit = LEFTOVER_UNIT.replace('zram-migration --purge-leftover', 'retire')
        self.assertNoted(self.deb(files={LEFTOVER: unit, '/usr/libexec/sparky-stereo/retire': RETIRE}),
                         '/usr/libexec/sparky-stereo/retire:4:', '/usr/libexec/sparky-stereo/retire:5:',
                         '/usr/libexec/sparky-stereo/retire:8:', 'a zram unit stopped', 'swap on a zram device switched off')
        inline = LEFTOVER_UNIT.replace('/usr/libexec/sparky-stereo/zram-migration --purge-leftover',
                                       "/bin/sh -c 'swapoff /dev/zram0; echo 1 > /sys/block/zram0/reset'")
        self.assertNoted(self.deb(files={LEFTOVER: inline}), LEFTOVER + ':8:')

    def test_a_tear_down_outside_a_unit_is_noted_too(self):
        self.assertNoted(self.deb(scripts={'postinst': '#!/bin/sh\nset -e\nprintf "1\\\\n" >/sys/block/zram0/reset\n'}),
                         'DEBIAN/postinst:3:', 'a zram device reset')

    def test_the_gate_says_what_it_let_through(self):
        run = subprocess.run([sys.executable, str(SUBJECT), '--debs', str(self.package())], capture_output=True, text=True)
        self.assertEqual(run.returncode, 0, run.stderr)
        self.assertIn('passed', run.stdout)
        self.assertIn('let through', run.stdout)
        self.assertIn(LEFTOVER, run.stdout)
        self.assertIn(SCRIPT, run.stdout)

    def test_the_units_in_an_image(self):
        root = self.dir / 'root'
        (root / 'var/lib/dpkg').mkdir(parents=True)
        (root / 'var/lib/dpkg/status').write_text('Package: sparky-stereo-kernel-settings\nStatus: install ok installed\n')
        for path, text in ((LEFTOVER, LEFTOVER_UNIT), (FAILED, FAILED_UNIT), (SETUP_D + '50-sparky-migration.conf', GUARD),
                           (SETUP_D + '60-sparky-zram-failure.conf', FAILURE), (SCRIPT, MIGRATION.read_text())):
            (root / path.lstrip('/')).parent.mkdir(parents=True, exist_ok=True)
            (root / path.lstrip('/')).write_text(text)
        (root / WANTS.lstrip('/')).parent.mkdir(parents=True)
        (root / WANTS.lstrip('/')).symlink_to('../' + Path(LEFTOVER).name)
        # an image has the system's own programs, compiled: a known one is judged by its command line
        (root / 'usr/bin').mkdir(parents=True)
        (root / 'usr/bin/sh').write_bytes(b'\x7fELF' + b'\0' * 60)
        (root / 'bin').symlink_to('usr/bin')
        (root / (SYSTEM + 'sparky-zram-off.service').lstrip('/')).write_text(
            "[Service]\nExecStart=/bin/sh -c 'swapoff /dev/zram0'\n")
        result = gate.check_image(root, [])
        self.assertEqual((result[0], result[1]), ([], []))
        self.assertTrue(any(LEFTOVER in n for n in result[3]), result)
        (root / SCRIPT.lstrip('/')).write_text('#!/bin/sh\necho 4G > /sys/block/zram0/disksize\n')
        self.assertTrue(any(SCRIPT + ':2:' in f for f in gate.check_image(root, [])[0]))

    @unittest.skipUnless(os.environ.get('ZRAM_GATE_PACKAGES'), 'ZRAM_GATE_PACKAGES is not set')
    def test_the_real_packages_whole(self):
        folder = Path(os.environ['ZRAM_GATE_PACKAGES'])
        for which, version, paths in (
                ('published', '20261106.1', (SETUP_D + '50-sparky-migration.conf:', SWAP_D + '50-sparky-migration.conf:')),
                ('staged', '20261108.1', (FAILED + ':', LEFTOVER + ':', SETUP_D + '60-sparky-zram-failure.conf:', WANTS + ':',
                                          SCRIPT + ':107:', SETUP_D + '50-sparky-migration.conf:',
                                          SETUP_D + '50-sparky-stereo-problems.conf:', 'DEBIAN/postinst:'))):
            with self.subTest(which=which):
                debs = sorted((folder / which).glob(f'sparky-stereo-kernel-settings_{version}*.deb'))
                self.assertEqual(len(debs), 1, debs)
                self.assertNoted(debs[0], *paths)


class SetUpsStayRefused(Fixtures):
    """Each form inside a unit named like ours, and inside the script a tear-down unit runs."""

    def in_unit(self, command):
        quoted = command.replace('\\', '\\\\').replace('"', '\\"').replace('$', '$$')
        return self.deb(files={LEFTOVER: LEFTOVER_UNIT.replace(
            '/usr/libexec/sparky-stereo/zram-migration --purge-leftover', f'/bin/sh -c "{quoted}"')})

    def in_script(self, command):
        return self.deb(files={LEFTOVER: LEFTOVER_UNIT.replace('zram-migration --purge-leftover', 'retire'),
                               '/usr/libexec/sparky-stereo/retire': RETIRE + command + '\n'})

    def in_python(self, command):
        return self.deb(files={LEFTOVER: LEFTOVER_UNIT, SCRIPT: PYTHON.format(line=command.replace("'", "\\'"))})

    def test_every_known_set_up_in_a_unit_named_like_ours(self):
        for command in KNOWN_SETUPS + MORE_SETUPS:
            with self.subTest(command=command):
                self.assertRefused(self.in_unit(command), LEFTOVER + ':8:')

    def test_every_known_set_up_in_the_script_a_tear_down_unit_runs(self):
        for command in KNOWN_SETUPS + MORE_SETUPS:
            with self.subTest(command=command):
                self.assertRefused(self.in_script(command), '/usr/libexec/sparky-stereo/retire:10:')

    def test_every_known_set_up_in_the_shell_text_a_python_script_runs(self):
        for command in KNOWN_SETUPS + MORE_SETUPS:
            with self.subTest(command=command):
                self.assertRefused(self.in_python(command), SCRIPT + ':6:')

    def test_a_set_up_run_directly_by_the_unit(self):
        for command in ('/usr/sbin/zramctl --find --size 4G', '/usr/sbin/swapon /dev/zram0', '/usr/sbin/mkswap /dev/zram0',
                        '/usr/sbin/modprobe zram', '/usr/bin/systemctl start dev-zram0.swap',
                        '/usr/lib/systemd/system-generators/zram-generator --setup-device zram0'):
            with self.subTest(command=command):
                self.assertRefused(self.deb(files={LEFTOVER: LEFTOVER_UNIT.replace(
                    '/usr/libexec/sparky-stereo/zram-migration --purge-leftover', command)}), LEFTOVER + ':8:')

    def test_units_that_pull_a_zram_unit_in(self):
        for line in ('Wants=dev-zram0.swap', 'Requires=systemd-zram-setup@zram0.service', 'Upholds=dev-zram0.swap',
                     'OnSuccess=systemd-zram-setup@zram0.service'):
            with self.subTest(line=line):
                self.assertRefused(self.deb(files={LEFTOVER: LEFTOVER_UNIT.replace('[Unit]\n', '[Unit]\n' + line + '\n'),
                                                   SCRIPT: MIGRATION.read_text()}), LEFTOVER + ':2: ' + line)
        self.assertRefused(self.deb(files={LEFTOVER: LEFTOVER_UNIT + 'Also=dev-zram0.swap\n', SCRIPT: MIGRATION.read_text()}),
                           LEFTOVER + ':14: Also=dev-zram0.swap')
        self.assertRefused(self.deb(files={SYSTEM + 'sparky-stereo-kernel-settings-zram.swap': '[Swap]\nWhat=/dev/zram0\n'}),
                           'sparky-stereo-kernel-settings-zram.swap:2: What=/dev/zram0')
        self.assertRefused(self.deb(files={SYSTEM + 'swap.target.wants/dev-zram0.swap': ('link', '../dev-zram0.swap')}),
                           'a zram unit')

    def test_drop_ins_that_do_more_than_limit_or_condition(self):
        for text in ('[Service]\nExecStartPre=/usr/sbin/modprobe zram\n', '[Service]\nEnvironment=ZRAM_SIZE=4G\n',
                     '[Service]\nExecStart=\nExecStart=/usr/sbin/zramctl --find --size 8G\n', '[Unit]\nWants=dev-zram1.swap\n',
                     '[Install]\nWantedBy=swap.target\n', '[Swap]\nPriority=100\n'):
            with self.subTest(text=text):
                self.assertRefused(self.deb(files={SETUP_D + '50-sparky-migration.conf': text}),
                                   SETUP_D + '50-sparky-migration.conf:2:')

    def test_a_package_with_a_tear_down_and_a_generator_configuration(self):
        found = self.assertRefused(self.deb(files={LEFTOVER: LEFTOVER_UNIT, SCRIPT: MIGRATION.read_text(),
                                                   '/usr/lib/systemd/zram-generator.conf': '[zram0]\n'}),
                                   '/usr/lib/systemd/zram-generator.conf:1: [zram0] (a zram-generator configuration)')
        self.assertEqual(len(found), 1, found)


class Forged(Fixtures):
    def test_a_reset_followed_by_a_disksize_write(self):
        both = 'echo 1 > /sys/block/zram0/reset; echo 4G > /sys/block/zram0/disksize'
        unit = LEFTOVER_UNIT.replace('/usr/libexec/sparky-stereo/zram-migration --purge-leftover', f"/bin/sh -c '{both}'")
        found = self.assertRefused(self.deb(files={LEFTOVER: unit}), LEFTOVER + ':8:', 'a zram device set up through sysfs')
        self.assertTrue(any('does both' in f for f in found), found)
        script = RETIRE + 'echo 4G > /sys/block/zram0/disksize\n'
        found = self.assertRefused(self.deb(files={LEFTOVER: LEFTOVER_UNIT.replace('zram-migration --purge-leftover', 'retire'),
                                                   '/usr/libexec/sparky-stereo/retire': script}),
                                   '/usr/libexec/sparky-stereo/retire:10: echo 4G > /sys/block/zram0/disksize')
        self.assertTrue(any('does both' in f for f in found), found)
        self.assertRefused(self.deb(files={LEFTOVER: LEFTOVER_UNIT, SCRIPT: PYTHON.format(line=both)}), SCRIPT + ':6:')
        # the same line outside any unit: the reset does not hide the set-up beside it
        self.assertRefused(self.deb(files={'/usr/sbin/x': '#!/bin/sh\n' + both + '\n'}), '/usr/sbin/x:2:')
        self.assertRefused(self.deb(files={'/usr/sbin/x': '#!/bin/sh\necho 0 > /run/x; echo 4G > /sys/block/zram0/disksize\n'}),
                           '/usr/sbin/x:2:')

    def test_a_script_the_gate_cannot_follow(self):
        self.assertRefused(self.deb(files={LEFTOVER: LEFTOVER_UNIT}), LEFTOVER + ':8:', 'does not ship')
        self.assertRefused(self.deb(files={LEFTOVER: LEFTOVER_UNIT, SCRIPT: b'\x7fELF' + b'\0' * 60}), LEFTOVER + ':8:',
                           'cannot read')
        self.assertRefused(self.deb(files={LEFTOVER: LEFTOVER_UNIT, SCRIPT: ('link', '/usr/bin/elsewhere')}), LEFTOVER + ':8:')
        self.assertRefused(self.deb(files={LEFTOVER: LEFTOVER_UNIT.replace('/usr/libexec/sparky-stereo/zram-migration',
                                                                          '/usr/bin/unknown-tool')}), LEFTOVER + ':8:')
        helper = '/usr/libexec/sparky-stereo/helper'
        self.assertRefused(self.deb(files={LEFTOVER: LEFTOVER_UNIT, SCRIPT: f'#!/bin/sh\nexec {helper}\n',
                                           helper: '#!/bin/sh\nzramctl --find --size 2G\n'}), helper + ':2:')
        self.assertRefused(self.deb(files={LEFTOVER: LEFTOVER_UNIT, SCRIPT: '#!/bin/sh\nzramctl \\\n  --find --size 2G\n'}),
                           SCRIPT + ':2:')

    def test_what_keeps_the_person_from_zram(self):
        self.assertRefused(self.deb(files={SETUP_D + '50-x.conf': '[Service]\nExecCondition=/bin/false\n'}),
                           SETUP_D + '50-x.conf:2:', 'caps')
        self.assertRefused(self.deb(files={'/etc/systemd/system/dev-zram0.swap': ('link', '/dev/null')}), 'caps')
        self.assertRefused(self.deb(files={SYSTEM + 'systemd-zram-setup@zram0.service': ('link', '/dev/null')}), 'caps')

    def test_a_zram_file_of_systemd_the_gate_does_not_know(self):
        self.assertRefused(self.deb(files={SYSTEM + 'sparky-zram.target': '[Unit]\nDescription=x\n'}), 'sparky-zram.target')
        self.assertRefused(self.deb(files={'/usr/lib/systemd/sparky-zram-helper': '#!/bin/sh\n'}), 'sparky-zram-helper')


if __name__ == '__main__':
    unittest.main()
