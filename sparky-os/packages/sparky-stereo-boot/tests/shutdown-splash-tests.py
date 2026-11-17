#!/usr/bin/python3
# Tests of sparky-stereo-boot plymouth-shutdown (0.1.12, ORDER 639): the splash of a restart or a shutdown is given the
# main screen's choice as it was exported last, not the one the boot started with. Each case is a fake root (/proc/cmdline,
# /var/lib/sparky-stereo-boot/main-output.json) and a plymouthd that writes the arguments it was started with.
# Run in a container with python3:
#   shutdown-splash-tests.py PATH/TO/sparky-stereo-boot
import json, os, shutil, subprocess, sys, tempfile

TOOL = os.path.abspath(sys.argv[1])
results = []
PANEL = 'plymouth.stereo=eDP-1:anaglyph-modern:mode=1366x768@60005:popped=3.25:sunk=8.13'
TV = 'plymouth.stereo=HDMI-A-1:frame-packing:mode=1920x1080@30000:popped=4.72:sunk=11.8'
START = 'BOOT_IMAGE=/boot/vmlinuz-7.3.4-stereo3d18 root=UUID=1234 ro quiet splash ' + PANEL + ' rw'


def case(name, mode, record, cmdline=START, expect_args=None, expect_status=None, expect_said=None, expect_silent=None):
    root = tempfile.mkdtemp(prefix='ssb-shutdown-')
    try:
        os.makedirs(os.path.join(root, 'proc'))
        os.makedirs(os.path.join(root, 'var/lib/sparky-stereo-boot'))
        open(os.path.join(root, 'proc/cmdline'), 'w').write(cmdline + '\n')
        if record is not None:
            open(os.path.join(root, 'var/lib/sparky-stereo-boot/main-output.json'), 'w').write(
                record if isinstance(record, str) else json.dumps(record))
        stub = os.path.join(root, 'plymouthd')
        got = os.path.join(root, 'started-with')
        open(stub, 'w').write('#!/bin/sh\nfor a in "$@"; do printf "%s\\n" "$a"; done > ' + got + '\n')
        os.chmod(stub, 0o755)
        env = dict(os.environ, SPARKY_STEREO_ROOT=root, SPARKY_STEREO_PLYMOUTHD=stub)
        run = subprocess.run([TOOL, 'plymouth-shutdown', mode], env=env, capture_output=True, text=True, timeout=60)
        args = open(got).read().splitlines() if os.path.exists(got) else None
        ok, why = True, []
        if expect_status is not None and run.returncode != expect_status:
            ok = False
            why.append('status %d, want %d' % (run.returncode, expect_status))
        if expect_args is not None and args != expect_args:
            ok = False
            why.append('plymouthd got %r, want %r' % (args, expect_args))
        if expect_said is not None and expect_said not in run.stderr:
            ok = False
            why.append('the journal line %r is missing (stderr %r)' % (expect_said, run.stderr.strip()))
        if expect_silent and run.stderr.strip():
            ok = False
            why.append('said %r where nothing changed' % run.stderr.strip())
        results.append(ok)
        print('%s: %s%s' % ('PASS' if ok else 'FAIL', name, '' if ok else ' (' + '; '.join(why) + ')'))
    finally:
        shutil.rmtree(root, ignore_errors=True)


def line(stereo):
    words = [w for w in START.split() if not w.startswith('plymouth.stereo=')]
    return ' '.join(words + stereo)


def started(mode, stereo):
    return ['--mode=' + mode, '--attach-to-session', '--kernel-command-line=' + line(stereo)]


record_tv = {'kernelArguments': [TV, 'video=HDMI-A-1:1920x1080@30']}
case('the television made the main screen in 3D since the start: the restart splash has its frame packing', 'reboot',
     record_tv, expect_args=started('reboot', [TV]), expect_status=0,
     expect_said='the restart splash follows the main screen as saved now: ' + TV)
case('the same for a shutdown', 'shutdown', record_tv, expect_args=started('shutdown', [TV]), expect_status=0,
     expect_said='the shutdown splash follows the main screen as saved now')
case('the main screen saved in 2D since the start: the splash has no plymouth.stereo=, one picture', 'reboot',
     {'kernelArguments': []}, expect_args=started('reboot', []), expect_status=0,
     expect_said='as saved now: 2D (this boot started with ' + PANEL)
case('the choice did not change: the start\'s line, nothing said', 'reboot', {'kernelArguments': [PANEL]},
     expect_args=started('reboot', [PANEL]), expect_status=0, expect_silent=True)
case('nothing exported yet: the start\'s choice stays, and the journal says why', 'reboot', None,
     expect_args=started('reboot', [PANEL]), expect_status=0,
     expect_said='the restart splash keeps the choice this boot started with')
case('an unreadable record: the start\'s choice stays, and the journal says why', 'shutdown', '{not json',
     expect_args=started('shutdown', [PANEL]), expect_status=0, expect_said='is not readable')
case('a record with a word that is no kernel argument is not handed on', 'reboot',
     {'kernelArguments': [TV + ';reboot']}, expect_args=started('reboot', []), expect_status=0)
case('a mode plymouthd does not have is refused', 'halt', record_tv, expect_args=None, expect_status=2)

print('SUMMARY %d of %d pass' % (sum(results), len(results)))
sys.exit(0 if all(results) else 1)
