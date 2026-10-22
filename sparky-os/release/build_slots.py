"""Serialize container launches so simultaneous queue wakeups keep four slots."""
import fcntl
from pathlib import Path
import subprocess
import time
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg


def start_build(command, container, log):
    lock_path = (cfg.path('SPARKY_MIGRATION_WORK') / 'build-launch.lock')
    while True:
        with lock_path.open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            names = subprocess.check_output(
                ['docker', 'ps', '--format', '{{.Names}}'], text=True).splitlines()
            if sum(name.startswith('sparky-lc-') for name in names) < 4:
                process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
                # Reserve until Docker can account for the new container.
                while process.poll() is None:
                    names = subprocess.check_output(
                        ['docker', 'ps', '--format', '{{.Names}}'], text=True).splitlines()
                    if container in names:
                        break
                    time.sleep(1)
                return process
        time.sleep(5)
