#!/usr/bin/env python3
"""PID 1 exits immediately on TERM, so an attached client cannot orphan a build."""
import os
import signal
import subprocess
import sys


def stop(signum, frame):
    # Exiting namespace PID 1 kills its remaining tasks, including grandchildren.
    os._exit(128+signum)


signal.signal(signal.SIGTERM,stop)
signal.signal(signal.SIGINT,stop)
result=subprocess.run(sys.argv[1:],env=dict(os.environ,LC_ALL='C'))
raise SystemExit(result.returncode if result.returncode>=0 else 128-result.returncode)
