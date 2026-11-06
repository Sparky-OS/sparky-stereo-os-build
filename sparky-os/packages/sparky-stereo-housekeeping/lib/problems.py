#!/usr/bin/python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/06
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/06
"""The housekeeping's problems, kept until they are repaired, by the edition's one engine (sparky-stereo-problems,
ORDER 350).

Nothing fails silently (Daniel, 2026-11-01: "either it works or not and the user must know"). A step of the housekeeping
that cannot do what it is for says what failed, why and what to do, in the
system's language, and the engine keeps it in /var/lib/sparky-stereo-problems with its exit status and its own
output: the evidence for the repair. The step clears the record when it next succeeds. The same problem found again
keeps the time it was first found and its hide, so it is shown once; the session's notifier
(sparky-stereo-problems-plasma) shows it.

  problems.py run STEP KEY [ARG...] [--repair COMMAND...] -- COMMAND...
                                     runs COMMAND with its output shown; a failure is said and kept (KEY's first two
                                     %s are COMMAND and its exit status, then ARGs), a success clears STEP; exits with
                                     COMMAND's status
  problems.py record STEP KEY [ARG...] [--repair COMMAND...]
                                     says and keeps a problem the caller found
  problems.py clear STEP...          the steps succeeded
  problems.py say KEY [ARG...]       says a notice, kept nowhere
  problems.py status                 lists the kept problems; exits 1 while one is shown
  problems.py repair                 root: runs again what each kept problem names
  problems.py dismiss STEP           hides the problem for you until it changes or a repair fails (the engine's Hide)
  problems.py notify                 starts the session's notifier, which shows every kept problem

An ARG of the form @LOCALn is that message itself, in the same language; from Python an ARG can also be a list
[KEY, ARG...], that message with its own arguments. Messages are the package's language files (LOCALn="text", %s for
the arguments), built into journal message catalogs with the package. Environment, for tests: SPARKY_STEREO_ROOT
prefixes the engine's /var/lib and /run.
"""
import sys

import sparky_stereo_problems as _engine

TAG = 'sparky-stereo-housekeeping'
_steps = _engine.Steps(TAG, words={'header': 'LOCAL2', 'none': 'LOCAL3', 'since': 'LOCAL4', 'evidence': 'LOCAL5',
                                   'dismissed': 'LOCAL6', 'repaired': 'LOCAL7', 'failed_again': 'LOCAL8',
                                   'hidden': 'LOCAL9', 'unknown': 'LOCAL10'})
language, text, say, record, clear, pending, message = (_steps.language, _steps.text, _steps.say, _steps.record,
                                                        _steps.clear, _steps.pending, _steps.message)
execute, run, status, repair, dismiss, notify, load = (_steps.execute, _steps.run, _steps.status, _steps.repair,
                                                       _steps.dismiss, _steps.notify, _steps.load)


def main(argv):
    return _steps.main(argv, __doc__)


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
