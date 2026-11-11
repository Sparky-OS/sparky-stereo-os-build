#!/usr/bin/python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/30
# Copyright 2026 under the GNU GPL3 License
# Tests that the merged GRUB messages reach GRUB's menu (sparky-stereo-grub-l10n 0.1.1), one case per fresh container,
# as root, with grub-common, grub2-common, gettext-base, python3 and a generated de_DE.UTF-8 locale:
#   grub-menu-tests.py CASE PACKAGE.deb
# Set PREVIOUS_DEB to the published 0.1.2 archive with CASE=new to test the installed APT upgrade.
# CASE: old (the version before 0.1.1: the catalogue is merged, the menu is not written), new (the menu is written at
# configure and when grub2-common's catalogue triggers it), guard (no test variable: nothing written in a container),
# no-menu (no /boot/grub/grub.cfg: nothing written, no failure), remove and purge (0.1.2: the menu back in Debian's words
# at once), remove-old (the version before 0.1.2: the menu keeps the merged words after removal). The menu is in German (LANG=de_DE.UTF-8, generated in the
# bench: gettext translates nothing in the C locales); one kernel in /boot
# gives GRUB's "Advanced options for ..." submenu, a message Debian's catalogue lacks. GRUB's device probe is a stub,
# as there is no disk in a container.
import os, subprocess, sys
from pathlib import Path

CASE, DEB = sys.argv[1], sys.argv[2]
MSG = 'Advanced options for %s'
CAT = '/usr/share/locale/de/LC_MESSAGES/grub.mo'
results = []


def sh(cmd, check=True, **kw):
    r = subprocess.run(cmd, shell=isinstance(cmd, str), capture_output=True, text=True, **kw)
    if check and r.returncode:
        raise SystemExit('FAIL  %s: %s exited %d\n%s%s' % (CASE, cmd, r.returncode, r.stdout, r.stderr))
    return r


# apt over HTTPS only (ORDER 400b, CVE-2026-109518): the container mounts the host's CA bundle at /run/host-ca.crt and
# tools/https-only-apt.sh at /run/https-only-apt.sh (read-only); a missing helper stops the test
sh(['sh', '/run/https-only-apt.sh'])


def check(ok, text):
    results.append(ok)
    print(('PASS  ' if ok else 'FAIL  ') + '%s: %s' % (CASE, text), flush=True)


def submenu():
    for line in open('/boot/grub/grub.cfg', encoding='utf-8'):
        if line.startswith('submenu '):
            return line.split("'")[1]
    return None


def calls():
    return len(Path('/run/grub-l10n-calls').read_text().splitlines())


def main():
    # Count real update-grub executions, so unchanged text cannot hide a missed purge/guard.
    os.rename('/usr/sbin/update-grub', '/usr/sbin/update-grub.test-real')
    Path('/run/grub-l10n-calls').touch()
    Path('/usr/sbin/update-grub').write_text(
        '#!/bin/sh\nprintf "update-grub\\n" >> /run/grub-l10n-calls\nexec /usr/sbin/update-grub.test-real "$@"\n')
    os.chmod('/usr/sbin/update-grub', 0o755)
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
    if CASE.startswith('fail-'):
        from grub_failure_cases import failure_case
        failure_case(CASE[5:], DEB, sys.argv[3], sh, check, calls)
        print('== %s: %s' % (CASE, 'ALL PASS' if all(results) else '%d FAILED' % results.count(False)))
        sys.exit(0 if all(results) else 1)
    previous = os.environ.get('PREVIOUS_DEB')
    if previous:
        sh(['dpkg', '-i', previous])
        check(sh(['dpkg-query', '-W', '-f', '${Version}', 'sparky-stereo-grub-l10n']).stdout == '0.1.2+lc1',
              'published 0.1.2+lc1 is installed before the upgrade')
        sh('env LANG=C.UTF-8 update-grub')
    before = calls()
    if previous:
        simulation = sh(['apt-get', '-s', '--no-remove', 'install', DEB]).stdout
        print(simulation, flush=True)
        inst = [line for line in simulation.splitlines() if line.startswith('Inst ')]
        check(len(inst) == 1 and inst[0].startswith('Inst sparky-stereo-grub-l10n [0.1.2+lc1] (0.1.3+lc1 '),
              'APT Inst line proves the requested upgrade, not a kept-back package')
        check(not any(line.startswith('Remv ') for line in simulation.splitlines()), 'APT removes nothing')
        print(sh(['apt-get', '-y', '--no-remove', 'install', DEB],
                 env=dict(os.environ, DEBIAN_FRONTEND='noninteractive')).stdout, flush=True)
        check(sh(['dpkg-query', '-W', '-f', '${Status} ${Version}', 'sparky-stereo-grub-l10n']).stdout ==
              'install ok installed 0.1.3+lc1', 'rebuilt 0.1.3+lc1 is installed and configured')
    else:
        sh(['dpkg', '-i', DEB])
    check(calls() - before == (0 if CASE in ('guard', 'no-menu', 'old') else 1),
          'configure runs update-grub exactly when eligible')
    german = sh(['gettext', '-d', 'grub', MSG]).stdout.replace('%s', 'Test GNU/Linux')
    translated = german != english and os.path.exists(CAT + '.debian')
    check(translated, 'the merged catalogue translates it: %r' % german)
    if CASE == 'no-menu':
        check(not os.path.exists('/boot/grub/grub.cfg'), 'with no GRUB menu, configure writes none and succeeds')
        for command in (['dpkg-trigger', '--by-package=grub2-common', '--no-await', CAT],
                        ['dpkg', '--triggers-only', '--pending'],
                        ['dpkg', '-r', 'sparky-stereo-grub-l10n'],
                        ['dpkg', '-P', 'sparky-stereo-grub-l10n']):
            sh(command)
            check(calls() == 0 and not os.path.exists('/boot/grub/grub.cfg'),
                  'no menu is generated without an existing menu: %s' % command)
    elif CASE in ('old', 'guard'):
        check(translated and submenu() == english, "right after configure GRUB's menu still says %r" % submenu())
        sh('update-grub')
        check(translated and submenu() == german, "only another update-grub brings it: %r" % submenu())
        if CASE == 'guard':
            before = calls()
            sh(['dpkg-trigger', '--by-package=grub2-common', '--no-await', CAT])
            sh(['dpkg', '--triggers-only', '--pending'])
            check(calls() == before, 'container trigger does not regenerate the existing menu')
            sh(['dpkg', '-r', 'sparky-stereo-grub-l10n'])
            sh(['dpkg', '-P', 'sparky-stereo-grub-l10n'])
            check(calls() == before, 'container remove and purge do not regenerate the existing menu')
            check(submenu() == german and not os.path.exists(CAT + '.debian'), 'removed in a container: the catalogue is Debian\'s again and no menu is written (%r)' % submenu())
    elif CASE in ('remove', 'remove-old', 'purge'):
        check(translated and submenu() == german, "right after configure GRUB's menu says %r" % submenu())
        # Give removal its own negative control, independent of configure's result.
        sh('update-grub')
        before = calls()
        sh(['dpkg', '-P' if CASE == 'purge' else '-r', 'sparky-stereo-grub-l10n'])
        check(calls() - before == (0 if CASE == 'remove-old' else 2 if CASE == 'purge' else 1),
              'each remove/purge invocation regenerates the menu')
        back = sh(['gettext', '-d', 'grub', MSG]).stdout == MSG and not os.path.exists(CAT + '.debian')
        want = german if CASE == 'remove-old' else english
        check(back and submenu() == want, 'after %s Debian\'s catalogue is back and GRUB\'s menu says %r (expected %r)'
              % ('purge' if CASE == 'purge' else 'removal', submenu(), want))
        if CASE == 'remove':
            before = calls()
            sh(['dpkg', '-P', 'sparky-stereo-grub-l10n'])
            check(calls() == before + 1, 'purge after removal regenerates even when Debian text was already restored')
            check(submenu() == english, "after the purge that follows, still Debian's words: %r" % submenu())
    else:
        check(translated and submenu() == german, "right after configure GRUB's menu says %r" % submenu())
        # grub2-common's catalogue updated: the trigger merges again and writes the menu again
        sh('env LANG=C.UTF-8 update-grub')
        check(submenu() == english, "control: a menu written without the language says %r" % submenu())
        before = calls()
        sh(['dpkg-trigger', '--by-package=grub2-common', '--no-await', CAT])
        sh('dpkg --triggers-only --pending')
        check(calls() == before + 1, 'grub2-common trigger regenerates exactly once')
        check(translated and submenu() == german, "after grub2-common's trigger GRUB's menu says %r" % submenu())
    print('== %s: %s' % (CASE, 'ALL PASS' if all(results) else '%d FAILED' % results.count(False)))
    sys.exit(0 if all(results) else 1)


if __name__ == '__main__':
    main()
