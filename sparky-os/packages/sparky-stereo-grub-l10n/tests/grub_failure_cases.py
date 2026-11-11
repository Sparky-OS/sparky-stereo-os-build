# Copyright 2026 Daniel Ramos (Capitain Jack), GPL-3.0-or-later
"""Installed failure/recovery cases used by grub-menu-tests.py in fresh containers.

Run grub-menu-tests.py fail-{configure,trigger,remove,purge} PACKAGE.deb {en,de}.
The wrapper fails only after the real update-grub completed successfully.
"""
import os
import json
from pathlib import Path

PACKAGE = 'sparky-stereo-grub-l10n'
CATALOGUE = '/usr/share/locale/de/LC_MESSAGES/grub.mo'
ERROR = 'injected update-grub failure after successful real rendering'


def failure_case(action, deb, language, sh, check, calls):
    if action not in ('configure', 'trigger', 'remove', 'purge') or language not in ('en', 'de'):
        raise SystemExit('unknown failure case or language')
    os.environ['LANG'] = 'de_DE.UTF-8' if language == 'de' else 'C.UTF-8'
    wrapper = Path('/usr/sbin/update-grub')
    wrapper.write_text('#!/bin/sh\n'
                       'printf "update-grub\\n" >> /run/grub-l10n-calls\n'
                       '/usr/sbin/update-grub.test-real "$@" || exit $?\n'
                       f'if [ -e /run/fail-update-grub ]; then echo "{ERROR}" >&2; exit 1; fi\n')
    wrapper.chmod(0o755)

    def state():
        return sh(['dpkg-query', '-W', '-f', '${Status}', PACKAGE], check=False).stdout.strip()

    if action != 'configure':
        sh(['dpkg', '-i', deb])
    if action == 'purge':
        # Reach postrm purge itself, rather than failing its preceding remove phase.
        sh(['dpkg', '--remove', PACKAGE])
    Path('/run/fail-update-grub').touch()
    before = calls()
    command = {'configure': ['dpkg', '-i', deb],
               'trigger': ['dpkg', '--triggers-only', '--pending'],
               'remove': ['dpkg', '--remove', PACKAGE],
               'purge': ['dpkg', '--purge', PACKAGE]}[action]
    if action == 'trigger':
        sh(['dpkg-trigger', '--by-package=grub2-common', '--no-await', CATALOGUE])
    result = sh(command, check=False)
    output = result.stdout + result.stderr
    print(output, flush=True)
    check(calls() == before + 1, 'the real generator ran before the injected failure')
    check(result.returncode != 0, 'dpkg rejects the failed operation (exit %s)' % result.returncode)
    configured = action in ('configure', 'trigger')
    wanted = 'half-configured' if configured else 'half-installed' if action == 'remove' else 'config-files'
    check(state().endswith(wanted), 'dpkg retains the retryable state: %s' % state())
    english = ('update-grub failed (exit status 1), so ' + PACKAGE + ' is not configured'
               if configured else 'Removing ' + PACKAGE + ': update-grub failed (exit status 1)')
    check(english in output, 'English diagnostic names update-grub, status and failed operation')
    repair = 'sudo dpkg --configure -a' if configured else 'sudo dpkg --' + action + ' ' + PACKAGE
    check(repair in output, 'the matching recovery command is shown: ' + repair)
    if language == 'de':
        check('update-grub ist fehlgeschlagen (Exit-Status 1)' in output,
              'the German diagnostic is shown alongside English')
    check(ERROR in output, 'the generator error is shown')
    log = Path('/var/log/sparky-stereo-grub-l10n.log')
    record = Path('/var/lib/sparky-stereo-problems/sparky-stereo-grub-l10n_update-grub.json')
    if configured:
        # the edition's one engine keeps it (ORDER 350): the error, the exit status and the repair, root's only
        kept = json.loads(record.read_text()) if record.exists() else {}
        check(ERROR in kept.get('output', '') and kept.get('status') == 1 and english in kept.get('text_en', '')
              and repair in kept.get('text_en', '') and kept.get('repair') == [['update-grub']],
              'error, exit status and repair are kept by the engine (%s)' % sorted(kept))
        check(record.exists() and record.stat().st_mode & 0o777 == 0o644 and record.stat().st_uid == 0
              and not log.exists(), "kept in the engine's machine store, writable by root only; no log of its own")
    else:
        saved = log.read_text() if log.exists() else ''
        check(ERROR in saved and english in saved and repair in saved, 'error, exit status and repair are retained')
        check(log.exists() and log.stat().st_mode & 0o777 == 0o600, 'retained output is readable only by root')
    if not configured:
        check(not Path('/usr/lib/' + PACKAGE + '/merge-mo').exists(),
              'postrm reports the problem after package files have gone')
        check(not Path(CATALOGUE + '.debian').exists(), 'Debian catalogue was restored before regeneration')

    Path('/run/fail-update-grub').unlink()
    before = calls()
    recovery = ['dpkg', '--configure', '-a'] if configured else ['dpkg', '--' + action, PACKAGE]
    result = sh(recovery, check=False)
    print(result.stdout + result.stderr, flush=True)
    check(result.returncode == 0 and calls() == before + 1, 'the corrected operation is retried and completes')
    check(not log.exists() and not record.exists(), 'successful regeneration clears the retained problem')
    wanted = 'installed' if configured else 'config-files' if action == 'remove' else 'not-installed'
    current = state()
    check(current.split()[-1:] == [wanted] or (action == 'purge' and not current),
          'dpkg reaches the final state: ' + (current or 'absent'))
    check(sh(['dpkg', '--configure', '-a'], check=False).returncode == 0,
          'no configuration remains blocked after recovery')
