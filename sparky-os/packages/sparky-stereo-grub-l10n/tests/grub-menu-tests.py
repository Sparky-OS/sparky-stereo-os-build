#!/usr/bin/python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/30
# Copyright 2026 under the GNU GPL3 License
# Tests that the merged GRUB messages reach GRUB's menu (sparky-stereo-grub-l10n 0.1.1), one case per fresh container,
# as root, with grub-common, grub2-common, gettext-base, python3 and a generated de_DE.UTF-8 locale:
#   grub-menu-tests.py CASE PACKAGE.deb
# CASE: old (the version before 0.1.1: the catalogue is merged, the menu is not written), new (the menu is written at
# configure and when grub2-common's catalogue triggers it), guard (no test variable: nothing written in a container),
# no-menu (no /boot/grub/grub.cfg: nothing written, no failure). The menu is in German (LANG=de_DE.UTF-8, generated in the
# bench: gettext translates nothing in the C locales); one kernel in /boot
# gives GRUB's "Advanced options for ..." submenu, a message Debian's catalogue lacks. GRUB's device probe is a stub,
# as there is no disk in a container.
import os, subprocess, sys

CASE, DEB = sys.argv[1], sys.argv[2]
MSG = 'Advanced options for %s'
CAT = '/usr/share/locale/de/LC_MESSAGES/grub.mo'
results = []


def sh(cmd, check=True, **kw):
    r = subprocess.run(cmd, shell=isinstance(cmd, str), capture_output=True, text=True, **kw)
    if check and r.returncode:
        raise SystemExit('FAIL  %s: %s exited %d\n%s%s' % (CASE, cmd, r.returncode, r.stdout, r.stderr))
    return r


def check(ok, text):
    results.append(ok)
    print(('PASS  ' if ok else 'FAIL  ') + '%s: %s' % (CASE, text), flush=True)


def submenu():
    for line in open('/boot/grub/grub.cfg', encoding='utf-8'):
        if line.startswith('submenu '):
            return line.split("'")[1]
    return None


def main():
    os.environ.update(LANG='de_DE.UTF-8')
    os.environ.pop('LANGUAGE', None)
    os.environ.pop('LC_ALL', None)
    if CASE != 'guard':
        os.environ['SPARKY_STEREO_GRUB_L10N_TEST'] = '1'
    for real in ('/usr/sbin/grub-probe', '/usr/bin/grub-mkrelpath'):
        sh(['dpkg-divert', '--local', '--rename', '--add', real])
    open('/usr/sbin/grub-probe', 'w').write(
        '#!/bin/sh\ncase "$*" in\n*--target=device*) echo /dev/vda2 ;;\n*--target=fs_uuid*) echo 0b1c2d3e-0000-4000-8000-000000000001 ;;\n'
        '*--target=partmap*) echo gpt ;;\n*--target=abstraction*) ;;\n*--target=drive*) echo "(hd0,gpt2)" ;;\n*) echo ext2 ;;\nesac\n')
    open('/usr/bin/grub-mkrelpath', 'w').write('#!/bin/sh\necho "$1"\n')
    for f in ('/usr/sbin/grub-probe', '/usr/bin/grub-mkrelpath'):
        os.chmod(f, 0o755)
    open('/etc/default/grub', 'w').write('GRUB_DEFAULT=0\nGRUB_TIMEOUT=5\nGRUB_DISTRIBUTOR=Test\nGRUB_CMDLINE_LINUX=""\nGRUB_DISABLE_OS_PROBER=true\n')
    open('/boot/vmlinuz-7.3.0-stereo3d13', 'wb').write(b'\0' * 64)
    open('/boot/initrd.img-7.3.0-stereo3d13', 'wb').write(b'\0' * 64)
    english = 'Advanced options for Test GNU/Linux'
    debian = sh(['gettext', '-d', 'grub', MSG]).stdout
    check(debian == MSG, "control: Debian's German catalogue lacks the message (%r)" % debian)
    if CASE != 'no-menu':
        os.makedirs('/boot/grub', exist_ok=True)
        sh('update-grub')
        check(submenu() == english, "before the package GRUB's menu says %r" % submenu())
    sh(['dpkg', '-i', DEB])
    german = sh(['gettext', '-d', 'grub', MSG]).stdout.replace('%s', 'Test GNU/Linux')
    translated = german != english and os.path.exists(CAT + '.debian')
    check(translated, 'the merged catalogue translates it: %r' % german)
    if CASE == 'no-menu':
        check(not os.path.exists('/boot/grub/grub.cfg'), 'with no GRUB menu, configure writes none and succeeds')
    elif CASE in ('old', 'guard'):
        check(translated and submenu() == english, "right after configure GRUB's menu still says %r" % submenu())
        sh('update-grub')
        check(translated and submenu() == german, "only another update-grub brings it: %r" % submenu())
    else:
        check(translated and submenu() == german, "right after configure GRUB's menu says %r" % submenu())
        # grub2-common's catalogue updated: the trigger merges again and writes the menu again
        sh('env LANG=C.UTF-8 update-grub')
        check(submenu() == english, "control: a menu written without the language says %r" % submenu())
        sh(['dpkg-trigger', '--by-package=grub2-common', '--no-await', CAT])
        sh('dpkg --triggers-only --pending')
        check(translated and submenu() == german, "after grub2-common's trigger GRUB's menu says %r" % submenu())
    print('== %s: %s' % (CASE, 'ALL PASS' if all(results) else '%d FAILED' % results.count(False)))
    sys.exit(0 if all(results) else 1)


if __name__ == '__main__':
    main()
