#!/usr/bin/python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/01
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/02
"""The boot's problems, kept until they are repaired, by the edition's one engine (sparky-stereo-problems, ORDER 350).

A step of the boot's upkeep that cannot do what it is for (update-grub, the boot images, the Secure Boot certificate
on the EFI system partition, the kernel cleanup, the 3D splash's handover, GRUB's resolution and font) says what
failed, why and what to do, in the system's language, and the engine keeps it in /var/lib/sparky-stereo-problems with
the command, its exit status and the end of its output: the evidence for the repair. The same step clears the record
when it next succeeds. `sparky-stereo-boot status` lists the records, `sparky-stereo-boot repair` runs again what each
one names, and the session's notifier (sparky-stereo-problems-plasma) shows each one. The records of the boot's own
store before 0.1.6 (/var/lib/sparky-stereo-boot/problems) move into the engine once, at the upgrade; one that cannot
move stays there and is named in a problem of its own (old-store), which `repair` tries again.

  problems.py run STEP KEY [ARG...] -- COMMAND...   runs COMMAND with its output shown; a failure is said and kept
                                                    (KEY's first two %s are COMMAND and its exit status, then ARGs),
                                                    a success clears STEP; exits with COMMAND's status
  problems.py record STEP KEY [ARG...] [--repair COMMAND...]
                                                    says and keeps a problem the caller found
  problems.py clear STEP                            the step succeeded
  problems.py say KEY [ARG...]                      says a notice, kept nowhere
  problems.py migrate DIR                           moves the records of an older store into the engine; one
                                                    that cannot move is kept as the problem old-store

An ARG of the form @LOCALn is that message itself, in the same language; from Python an ARG can also be a list
[KEY, ARG...], that message with its own arguments. Messages are the package's language files (LOCALn="text", %s for
the arguments), built into journal message catalogs with the package. Environment, for tests: SPARKY_STEREO_ROOT
prefixes the engine's /var/lib and /run.
"""
import sys

import sparky_stereo_problems as _engine

TAG = 'sparky-stereo-boot'
_steps = _engine.Steps(TAG, words={'header': 'LOCAL15', 'none': 'LOCAL16', 'since': 'LOCAL17', 'evidence': 'LOCAL18',
                                   'repaired': 'LOCAL50', 'failed_again': 'LOCAL51', 'no_repair': 'LOCAL52',
                                   'hidden': 'LOCAL53', 'unknown': 'LOCAL15',
                                   'migrate_failed': 'LOCAL61'})
language, text, say, record, clear, pending, message = (_steps.language, _steps.text, _steps.say, _steps.record,
                                                        _steps.clear, _steps.pending, _steps.message)
execute, run, status, repair, dismiss, notify, load, migrate = (_steps.execute, _steps.run, _steps.status,
                                                                _steps.repair, _steps.dismiss, _steps.notify,
                                                                _steps.load, _steps.migrate)


def main(argv):
    return _steps.main(argv, __doc__)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
