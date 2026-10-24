#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Keep kde-inhibit alive, reject its warnings and retain the bench exit status."""
import os
from pathlib import Path
import runpy
import signal
import subprocess
import sys
import tempfile
import time
import traceback


def child(root, args):
    code = 1
    try:
        signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))
        (root/'child.pid').write_text(str(os.getpid()))
        # kde-inhibit finishes its synchronous D-Bus requests before executing us.
        if 'inhibit failed' in (root/'stderr').read_text().lower():
            raise RuntimeError('KDE inhibition failed; no benchmark or display changes started')
        os.environ['BINO_A10_INHIBITED'] = '1'
        sys.argv = [str(Path(__file__).with_name('bench.py')), *args]
        runpy.run_path(sys.argv[0], run_name='__main__')
        code = 0
    except SystemExit as error:
        code = error.code if isinstance(error.code, int) else (0 if error.code is None else 1)
    except KeyboardInterrupt:
        code = 130
    except BaseException:
        traceback.print_exc()
    finally:
        (root/'exit-status').write_text(str(code))
    return code


def launch(args):
    pending = []
    def interrupted(signum, _frame):
        pending.append(signum)
    signal.signal(signal.SIGINT, interrupted)
    signal.signal(signal.SIGTERM, interrupted)
    with tempfile.TemporaryDirectory(prefix='bino-242-inhibit-', dir=os.environ.get('XDG_RUNTIME_DIR')) as temp:
        root = Path(temp)
        with (root/'stderr').open('w') as log:
            process = subprocess.Popen(['kde-inhibit', '--power', '--screenSaver', '--',
                sys.executable, str(Path(__file__).resolve()), '--child', str(root), *args], stderr=log, start_new_session=True)
            while process.poll() is None:
                if pending and (root/'child.pid').exists():
                    try:
                        pid = int((root/'child.pid').read_text())
                        os.kill(pid, pending.pop(0))
                    except ValueError:
                        pass  # The child is still writing its PID.
                    except ProcessLookupError:
                        pending.clear()
                time.sleep(.1)
        sys.stderr.write((root/'stderr').read_text())
        status = root/'exit-status'
        if not status.exists():
            print('Inhibited child did not complete; the run failed.', file=sys.stderr)
            return 1
        return int(status.read_text())


if __name__ == '__main__':
    if len(sys.argv) > 2 and sys.argv[1] == '--child':
        sys.exit(child(Path(sys.argv[2]), sys.argv[3:]))
    sys.exit(launch(sys.argv[1:]))
