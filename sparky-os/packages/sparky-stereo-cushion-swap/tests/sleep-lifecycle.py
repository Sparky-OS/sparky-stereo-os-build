#!/usr/bin/env python3
"""Real Cushion CLI with private proc/sys and swap commands; no machine sleeps.

Models systemd 262's documented unit/phase ordering, including the RTC wake.
Run as root in a disposable container for the engine's real boot store; all
kernel swap and sleep operations are fixtures. PKG may name an older source.
"""
import json
import fcntl
import time
import os
from pathlib import Path
import subprocess
import sys
import tempfile

pkg = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]
results = []
with tempfile.TemporaryDirectory() as tmp:
    w = Path(tmp)
    w.chmod(0o755)
    for name in ('state', 'sys', 'empty', 'catalog', 'engine'):
        (w / name).mkdir()
    swap = w / 'resume-partition'
    with swap.open('wb') as f:
        f.truncate(16 * 1024**3)
    (w / 'resume').write_text(f'RESUME={swap}\n')
    (w / 'cmdline').write_text('quiet\n')
    (w / 'sys/resume').write_text('0:0\n')
    (w / 'sys/resume_offset').write_text('0\n')
    (w / 'meminfo').write_text('MemTotal: 16777216 kB\nMemAvailable: 14000000 kB\nSwapTotal: 16777216 kB\nSwapFree: 16777216 kB\n')
    for command in ('swapon', 'swapoff'):
        f = w / command
        f.write_text('''#!/bin/sh
printf '%s %s\n' "${0##*/}" "$*" >>"$ACTIONS"
if [ "${FAIL_DEPLOY:-}" = yes ] && [ "${0##*/}" = swapon ]; then
    echo 'swapon: fixture: No space left on device' >&2; exit 7
fi
printf 'Filename Type Size Used Priority\n' >"$SWAPS_PATH"
if [ "${0##*/}" = swapon ]; then printf '%s file 16777216 0 -2\n' "$2" >>"$SWAPS_PATH"; fi
''')
        f.chmod(0o755)
    subprocess.run(['sparky-stereo-problems', 'catalog', 'sparky-stereo-cushion-swap', str(pkg / 'lang'), str(w / 'catalog'), '--subject', 'LOCAL16'], check=True)
    env = dict(os.environ, CUSHION_SWAP_CONFIG=str(w / 'absent'), CUSHION_SWAP_AREA=str(swap),
               INITRAMFS_RESUME_PATH=str(w / 'resume'), CMDLINE_PATH=str(w / 'cmdline'),
               MEMINFO_PATH=str(w / 'meminfo'), SWAPS_PATH=str(w / 'swaps'),
               SYS_POWER_DIR=str(w / 'sys'), SYS_BLOCK_DIR=str(w / 'empty'),
               FSTAB_PATH=str(w / 'absent'), STATE_DIR=str(w / 'state'),
               SWAPON_BIN=str(w / 'swapon'), SWAPOFF_BIN=str(w / 'swapoff'),
               ACTIONS=str(w / 'actions'), LANG='C.UTF-8',
               CUSHION_SWAP_LANG_DIR=str(pkg / 'lang'), LOG_EVERY_CYCLE='yes',
               SPARKY_STEREO_ROOT=str(w / 'engine'), SPARKY_STEREO_PROBLEMS_CATALOG=str(w / 'catalog') + ':/usr/lib/systemd/catalog')
    def run(*args, now=1000, **extra):
        p = subprocess.run([str(pkg / 'sbin/cushion-swap'), *args], env=dict(env, NOW_EPOCH=str(now), **extra), text=True, capture_output=True)
        return p
    def reset():
        (w / 'swaps').write_text('Filename Type Size Used Priority\n')
        (w / 'actions').unlink(missing_ok=True)
        (w / 'state/hibernate-deployed').unlink(missing_ok=True)
        (w / 'state/state').write_text('0 0 100 0 0\n')
    def active():
        return str(swap) in (w / 'swaps').read_text()
    def phase(verb, action):
        hook = pkg / 'lib/systemd/system-sleep/cushion-swap'
        if hook.is_file():
            translated = w / 'hook'
            translated.write_text(hook.read_text().replace('/usr/sbin/cushion-swap', str(pkg / 'sbin/cushion-swap')))
            translated.chmod(0o755)
            return subprocess.run([str(translated), 'post', verb], env=dict(env, SYSTEMD_SLEEP_ACTION=action), capture_output=True).returncode
        return 0
    for verb in ('hibernate', 'hybrid-sleep', 'suspend-then-hibernate'):
        reset()
        unit = pkg / f'lib/systemd/system/systemd-{verb}.service.d/50-cushion-swap.conf'
        native_pre = unit.is_file() and 'ExecStartPre=/usr/sbin/cushion-swap --hibernate-deploy' in unit.read_text()
        native_post = unit.is_file() and 'ExecStopPost=/usr/sbin/cushion-swap --hibernate-resume' in unit.read_text()
        pre = run('--hibernate-deploy')
        deployed = active()
        # Suspend-then-hibernate post/suspend executes before the hibernate phase.
        if verb == 'suspend-then-hibernate':
            phase(verb, 'suspend')
        # Long operations must retain the area even if system services run after an RTC wake.
        cycle = run('--once', now=8201)
        held = active() and (w / 'state/hibernate-deployed').exists()
        quiet = 'quiet_elapsed=0s' in cycle.stdout
        image_target = str(swap) if active() else None
        # A simulated kernel resume reads the same area before final service cleanup.
        resumed_from = image_target
        phase(verb, verb if verb != 'suspend-then-hibernate' else 'hibernate')
        post = run('--hibernate-resume', now=8202) if native_post else None
        released = not (w / 'state/hibernate-deployed').exists()
        passed = all((pre.returncode == 0, deployed, held, quiet, native_pre, native_post,
                      resumed_from == str(swap), post is not None and post.returncode == 0, released))
        results.append(dict(case=verb, pre_exit=pre.returncode, deployed=deployed, held_after_two_hours=held,
                            quiet_countdown_paused=quiet, simulated_resume_target=resumed_from,
                            cleanup_exit=post.returncode if post else None, released=released, passed=passed))
        # Failed optional Wants in the old packaging cannot block its native sleep unit.
        reset()
        failed = run('--hibernate-deploy', FAIL_DEPLOY='yes')
        sleep_entered = not native_pre or failed.returncode == 0
        records = list((w / 'engine/run/sparky-stereo-problems').glob('*hibernate-swapon.json'))
        kept = bool(records) and 'No space left on device' in records[0].read_text()
        command = ['sparky-stereo-problems', 'list', '--json', 'sparky-stereo-cushion-swap']
        root_records = subprocess.run(command, env=env, text=True, capture_output=True, check=True)
        person_records = subprocess.run(command, env=env, text=True, capture_output=True, check=True,
                                        preexec_fn=(lambda: os.setuid(1000)) if os.geteuid() == 0 else None)
        visible = bool(json.loads(root_records.stdout)) and bool(json.loads(person_records.stdout))
        results.append(dict(case=verb + '-deployment-failure', pre_exit=failed.returncode,
                            sleep_entered=sleep_entered, kept=kept, root_list=json.loads(root_records.stdout),
                            person_list=json.loads(person_records.stdout),
                            passed=failed.returncode != 0 and not sleep_entered and kept and visible and
                            'No space left on device' in failed.stderr))
    # Normal pacing starts afresh when the used area must stay on after resume.
    reset()
    run('--hibernate-deploy')
    (w / 'swaps').write_text(f'Filename Type Size Used Priority\n{swap} file 16777216 1 -2\n')
    (w / 'meminfo').write_text((w / 'meminfo').read_text().replace('SwapFree: 16777216', 'SwapFree: 16777215'))
    ended = run('--hibernate-resume', now=8202)
    run('--once', now=8203)
    stays = active()
    run('--once', now=8803)
    results.append(dict(case='quiet-window-restarts-after-resume', passed=ended.returncode == 0 and stays and not active()))
    # Manual wake ends s2h without hibernating; the native service's cleanup still runs.
    reset()
    pre = run('--hibernate-deploy')
    post = run('--hibernate-resume', now=1010)
    results.append(dict(case='manual-wake', passed=pre.returncode == 0 and post.returncode == 0 and not active()))
    reset()
    # A daemon read/decide/swap operation holding the shared lock must finish
    # before preparation can observe or change the same swap state.
    with (w / 'state/swap-actions.lock').open('w') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        waiting = subprocess.Popen([str(pkg / 'sbin/cushion-swap'), '--hibernate-deploy'],
                                   env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        time.sleep(0.2)
        blocked = waiting.poll() is None and not active()
        fcntl.flock(lock, fcntl.LOCK_UN)
        waiting.communicate(timeout=10)
    results.append(dict(case='preparation-serialized-with-daemon',
                        passed=blocked and waiting.returncode == 0 and active()))
    run('--hibernate-resume')
    reset()
    missing = run('--hibernate-deploy', INITRAMFS_RESUME_PATH=str(w / 'absent'))
    results.append(dict(case='missing-resume-blocks-sleep', exit=missing.returncode, passed=missing.returncode != 0))
print(json.dumps(results, indent=2))
raise SystemExit(0 if all(r['passed'] for r in results) else 1)
