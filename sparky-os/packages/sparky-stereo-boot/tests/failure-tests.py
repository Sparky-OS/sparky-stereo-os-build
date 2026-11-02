#!/usr/bin/python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/01
# Copyright 2026 under the GNU GPL3 License
# Tests that sparky-stereo-boot never fails silently (0.1.5): the 3D splash's hand-over, the boot's kept problems
# (status, repair, dismiss, kept by the one engine since 0.1.6), the check of GRUB's resolution at boot, and the nine
# languages of every message the code uses. Each case runs in a process of its own, with fake plymouth, systemctl,
# busctl and dpkg-query first in PATH and a fake root (SPARKY_STEREO_ROOT); the program is loaded as a module and
# only its two DRM-facing functions are replaced (the outputs' framebuffers, and whether a stereo splash runs).
# Run in a container, never on a machine whose splash or services it could reach:
#   failure-tests.py PATH/TO/sparky-stereo-boot
import json, os, re, struct, subprocess, sys, tempfile, time

PKG = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else ''
LANGS = ('en', 'pl', 'pt_BR', 'fr', 'de', 'ja', 'ko', 'zh_CN', 'zh_TW')
results = []

FAKE = r'''#!/bin/sh
# logs the call, answers by the rules file: "NAME ARGS<TAB>STATUS<TAB>OUTPUT"
printf '%s' "$(basename "$0") $*" | tr '\n' '|' >> "$FAKE_LOG"; echo >> "$FAKE_LOG"
call="$(basename "$0") $*"
while IFS='	' read -r key status output; do
	if [ "$key" = "$call" ]; then
		[ -z "$output" ] || printf '%s\n' "$output"
		exit "$status"
	fi
done < "$FAKE_RULES"
exit 0
'''


def check(case, ok, text):
    results.append(ok)
    print(('PASS  ' if ok else 'FAIL  ') + '%s: %s' % (case, text), flush=True)


# the boot's problems are kept by the edition's one engine (sparky-stereo-problems, 0.1.6): its records, its
# catalogs built from the package's language files
STORE = 'var/lib/sparky-stereo-problems'
CATALOG = tempfile.mkdtemp(prefix='ssb-cat-')
subprocess.run(['sparky-stereo-problems', 'catalog', 'sparky-stereo-boot', os.path.join(PKG, 'lang'), CATALOG,
                '--subject', 'LOCAL19'], check=True, stdout=subprocess.DEVNULL)


def record_path(root, step):
    return os.path.join(root, STORE, 'sparky-stereo-boot_%s.json' % step)


def kept(root, step):
    try:
        r = json.load(open(record_path(root, step)))
    except (OSError, ValueError):
        return None
    r['key'] = r['message']
    return r


def setup(rules=(), lang='en_US.UTF-8'):
    root = tempfile.mkdtemp(prefix='ssb-fail-')
    fakes = os.path.join(root, 'fakes')
    os.makedirs(fakes)
    for name in ('plymouth', 'systemctl', 'busctl', 'dpkg-query', 'update-grub', 'update-initramfs'):
        with open(os.path.join(fakes, name), 'w') as f:
            f.write(FAKE)
        os.chmod(os.path.join(fakes, name), 0o755)
    open(os.path.join(root, 'rules'), 'w').write(''.join('%s\t%s\t%s\n' % r for r in rules))
    open(os.path.join(root, 'log'), 'w').close()
    os.makedirs(os.path.join(root, 'run/user'))
    env = dict(os.environ, PATH=fakes + ':/usr/bin:/bin', FAKE_LOG=os.path.join(root, 'log'),
               FAKE_RULES=os.path.join(root, 'rules'), SPARKY_STEREO_ROOT=root,
               SPARKY_STEREO_LIB=os.path.join(PKG, 'lib'), SPARKY_STEREO_LANG_DIR=os.path.join(PKG, 'lang'),
               SPARKY_STEREO_PROBLEMS_CATALOG=CATALOG + ':/usr/lib/systemd/catalog', XDG_STATE_HOME=os.path.join(root, 'state'),
               LANG=lang, XDG_RUNTIME_DIR=os.path.join(root, 'run/user'))
    return root, env


def log(root):
    return open(os.path.join(root, 'log')).read().splitlines()


def call(env, function, *args, patch=''):
    """Runs FUNCTION(*ARGS) of the program, loaded as a module, with PATCH applied; returns (exit, stderr)."""
    code = '''
import importlib.machinery, importlib.util, json, sys
loader = importlib.machinery.SourceFileLoader('ssb', %r)
spec = importlib.util.spec_from_loader('ssb', loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)
%s
sys.exit(m.%s(*%r))
''' % (os.path.join(PKG, 'bin/sparky-stereo-boot'), patch, function, args)
    r = subprocess.run([sys.executable, '-I', '-c', code], env=env, capture_output=True, text=True, timeout=120)
    return r.returncode, r.stderr


def cli(env, *args):
    r = subprocess.run([sys.executable, '-I', os.path.join(PKG, 'bin/sparky-stereo-boot')] + list(args), env=env,
                       capture_output=True, text=True, timeout=120)
    return r.returncode, r.stdout + r.stderr


STEREO = 'm.stereo_splash_running = lambda: True\n'
BUFFERS = 'm.crtc_buffers = lambda: {"card0:41": 7}\n'


def handover():
    # U51: plymouth deactivate fails
    root, env = setup([('plymouth deactivate', 1, ''), ('plymouth --ping', 1, '')])
    rc, err = call(env, 'plymouth_quit', patch=STEREO + BUFFERS)
    calls = log(root)
    k = kept(root, 'handover')
    check('deactivate-fails', rc == 1, 'plymouth-quit fails (exit %d)' % rc)
    check('deactivate-fails', 'plymouth quit' in calls and not any(c.startswith('systemctl start') for c in calls),
          'the splash is quit at once, no hand-over started (%s)' % calls)
    check('deactivate-fails', bool(k) and k['key'] == 'LOCAL32' and k['args'] == [['LOCAL34', '1']],
          'kept: the hand-over failed because plymouth deactivate failed (%s)' % str(k and (k['key'], k['args'])))
    check('deactivate-fails', 'splash deactivated' not in err, 'no success line in the journal')
    # U51: the hand-over service does not start
    root, env = setup([('systemctl start --no-block sparky-stereo-boot-handover.service', 5, ''), ('plymouth --ping', 1, '')])
    rc, err = call(env, 'plymouth_quit', patch=STEREO + BUFFERS)
    calls, k = log(root), kept(root, 'handover')
    check('service-fails', rc == 1, 'plymouth-quit fails (exit %d)' % rc)
    check('service-fails', 'plymouth quit --retain-splash' in calls, 'the deactivated splash is quit keeping its picture (%s)' % calls)
    check('service-fails', bool(k) and k['args'] == [['LOCAL35', '5']], 'kept with the service exit status (%s)' % (k and k['args']))
    # the outputs cannot be read
    root, env = setup([('plymouth --ping', 1, '')])
    rc, err = call(env, 'plymouth_quit', patch=STEREO + 'def boom():\n    raise OSError("no DRM device")\nm.crtc_buffers = boom\n')
    calls, k = log(root), kept(root, 'handover')
    check('outputs-unreadable', rc == 1 and 'plymouth quit' in calls, 'quit at once, plymouth-quit fails (exit %d, %s)' % (rc, calls))
    check('outputs-unreadable', bool(k) and k['args'][0][0] == 'LOCAL33' and 'no DRM device' in k['args'][0][1],
          'kept with the reason (%s)' % (k and k['args']))
    # the display manager fails while the splash waits
    root, env = setup([('systemctl show -p ActiveState --value display-manager.service', 0, 'failed'), ('plymouth --ping', 1, '')])
    os.makedirs(os.path.join(root, 'run/sparky-stereo-boot'))
    json.dump({'card0:41': 7}, open(os.path.join(root, 'run/sparky-stereo-boot/splash-buffers.json'), 'w'))
    t = time.monotonic()
    rc, err = call(env, 'plymouth_handover', 30.0, patch=BUFFERS)
    calls, k = log(root), kept(root, 'handover')
    check('display-manager-failed', rc == 1 and calls[-1] == 'plymouth quit', 'quit so the console comes back, exit %d after %.1f s' % (rc, time.monotonic() - t))
    check('display-manager-failed', bool(k) and k['args'] == [['LOCAL37', 'failed']], 'kept: the login screen did not start (%s)' % (k and k['args']))
    # no compositor frame before the limit
    root, env = setup([('systemctl show -p ActiveState --value display-manager.service', 0, 'activating'), ('plymouth --ping', 1, '')])
    os.makedirs(os.path.join(root, 'run/sparky-stereo-boot'))
    json.dump({'card0:41': 7}, open(os.path.join(root, 'run/sparky-stereo-boot/splash-buffers.json'), 'w'))
    rc, err = call(env, 'plymouth_handover', 2.0, patch=BUFFERS)
    k = kept(root, 'handover')
    check('timeout', rc == 1 and bool(k) and k['args'] == [['LOCAL38', '2']], 'exit %d, kept: no picture in 2 seconds (%s)' % (rc, k and k['args']))
    # nothing to hand over (no splash buffers recorded): told at once, not after the limit
    root, env = setup([('plymouth --ping', 1, '')])
    t = time.monotonic()
    try:
        rc, err = call(env, 'plymouth_handover', 20.0, patch=BUFFERS)
    except subprocess.TimeoutExpired:
        rc = None
    k = kept(root, 'handover')
    check('no-buffers', rc == 1 and time.monotonic() - t < 10 and bool(k), 'exit %s after %.1f s, kept (%s)' % (rc, time.monotonic() - t, k and k['args']))
    # quit --retain-splash fails after the compositor's frame
    root, env = setup([('plymouth quit --retain-splash', 1, ''), ('plymouth --ping', 0, ''), ('plymouth quit', 1, '')])
    os.makedirs(os.path.join(root, 'run/sparky-stereo-boot'))
    json.dump({'card0:41': 7}, open(os.path.join(root, 'run/sparky-stereo-boot/splash-buffers.json'), 'w'))
    rc, err = call(env, 'plymouth_handover', 20.0, patch='m.crtc_buffers = lambda: {"card0:41": 9}\n')
    k, q = kept(root, 'handover'), kept(root, 'splash-quit')
    check('quit-fails', rc == 1 and bool(k) and k['args'] == [['LOCAL36', '1']], 'exit %d, kept: plymouth quit failed (%s)' % (rc, k and k['args']))
    check('quit-fails', bool(q) and q['key'] == 'LOCAL40', 'a splash still running is kept as a problem of its own (%s)' % (q and q['key']))
    check('quit-fails', 'compositor took over' not in err, 'no success line in the journal')
    # success clears an older record
    root, env = setup()
    os.makedirs(os.path.join(root, 'run/sparky-stereo-boot'))
    json.dump({'card0:41': 7}, open(os.path.join(root, 'run/sparky-stereo-boot/splash-buffers.json'), 'w'))
    record(root, 'handover', 'LOCAL32', [['LOCAL39']])
    rc, err = call(env, 'plymouth_handover', 20.0, patch='m.crtc_buffers = lambda: {"card0:41": 9}\n')
    check('handover-succeeds', rc == 0 and log(root) == ['plymouth quit --retain-splash'] and kept(root, 'handover') is None,
          'quit keeping the picture, exit %d, the older record cleared (%s)' % (rc, log(root)))
    # every boot without a 3D splash: a splash that stays after a failed quit is told; no splash at all is nothing
    root, env = setup([('plymouth quit', 1, ''), ('plymouth --ping', 0, '')])
    rc, err = call(env, 'plymouth_quit', patch='m.stereo_splash_running = lambda: False\n')
    q = kept(root, 'splash-quit')
    check('ordinary-quit-fails', rc == 1 and bool(q) and q['args'] == ['1'], 'exit %d, kept (%s)' % (rc, q and q['args']))
    root, env = setup([('plymouth quit', 1, ''), ('plymouth --ping', 1, '')])
    rc, err = call(env, 'plymouth_quit', patch='m.stereo_splash_running = lambda: False\n')
    check('no-splash', rc == 0 and kept(root, 'splash-quit') is None, 'no splash running: nothing to quit, nothing kept (exit %d)' % rc)


_order = [0]


def record(root, step, key, args, repair=None, output=''):
    """A kept problem of the boot, kept by the engine (its first time in the order of the calls)."""
    _order[0] += 1
    details = {'args': args, 'status': 1, 'first': '2026-11-01T12:00:%02dZ' % _order[0]}
    if output:
        details['output'] = output
    if repair:
        details['repair'] = repair
    subprocess.run(['sparky-stereo-problems', 'keep', '--machine', '--quiet', 'sparky-stereo-boot', step, key,
                    '--details', json.dumps(details)], check=True, stderr=subprocess.DEVNULL,
                   env=dict(os.environ, SPARKY_STEREO_ROOT=root, SPARKY_STEREO_PROBLEMS_CATALOG=CATALOG + ':/usr/lib/systemd/catalog'))


def strings(lang):
    values = {}
    for line in open(os.path.join(PKG, 'lang', lang), encoding='utf-8'):
        if '=' in line:
            k, v = line.rstrip('\n').split('=', 1)
            values[k] = v.strip('"')
    return values


def problems():
    pt = strings('pt_BR')
    root, env = setup(lang='pt_BR.UTF-8')
    rc, out = cli(env, 'status')
    check('status-none', pt['LOCAL16'] in out, 'no problem: said so in pt_BR (%s)' % out.strip().splitlines()[-1:])
    record(root, 'update-grub', 'LOCAL21', ['update-grub', '1'], repair=[['update-grub']], output='error: disk full\n')
    record(root, 'handover', 'LOCAL32', [['LOCAL34', '1']])
    rc, out = cli(env, 'status')
    want = pt['LOCAL21'] % ('update-grub', '1')
    check('status', rc == 1 and pt['LOCAL15'] in out and want in out and (pt['LOCAL32'] % (pt['LOCAL34'] % '1')) in out,
          'both problems listed in pt_BR, the reason inside the hand-over message, exit %d' % rc)
    check('status', ('%s: %s' % (pt['LOCAL18'], record_path(root, 'update-grub'))) in out, 'where the output is kept')
    # the session's notifier (sparky-stereo-problems-plasma) shows the problems: notify starts it
    root, env = setup(lang='de_DE.UTF-8')
    record(root, 'update-grub', 'LOCAL21', ['update-grub', '1'])
    rc, out = cli(env, 'notify')
    check('notify', rc == 0 and 'systemctl --user start sparky-stereo-problems-notifier.service' in log(root),
          "notify starts the session's notifier (%s)" % log(root))
    root, env = setup([('systemctl --user start sparky-stereo-problems-notifier.service', 1, 'Failed to connect to bus')])
    rc, out = cli(env, 'notify')
    check('notify-fails', rc == 1 and 'Failed to connect to bus' in out, "a notifier that cannot be started is said, systemctl's own words (exit %d)" % rc)
    # repair: what has a command runs again and is cleared; what has none is listed; what fails again is kept
    en = strings('en')
    root, env = setup([('update-initramfs -u -k all', 1, 'E: still broken'), ('dpkg-query -W -f ${db:Status-Abbrev} sparky-stereo-boot', 0, 'iF')])
    record(root, 'update-grub', 'LOCAL21', ['update-grub', '1'], repair=[['update-grub']])
    record(root, 'kernel-cleanup', 'LOCAL27', ['update-initramfs -u -k all', '1'], repair=[['update-initramfs', '-u', '-k', 'all'], ['update-grub']])
    record(root, 'handover', 'LOCAL32', [['LOCAL39']])
    rc, out = cli(env, 'repair')
    k = kept(root, 'kernel-cleanup')
    check('repair', kept(root, 'update-grub') is None and (en['LOCAL50'] % 'update-grub') in out, 'update-grub ran again and its problem is cleared')
    check('repair', bool(k) and 'still broken' in (k.get('last_repair') or {}).get('output', '')
          and (en['LOCAL51'] % ('update-initramfs -u -k all', '1')) in out,
          'a step that fails again is kept with the new output of its repair')
    check('repair', kept(root, 'handover') is not None and (en['LOCAL52'] % ('handover', 'handover')) in out, 'a problem with nothing to run is listed')
    check('repair', rc == 1 and en['LOCAL54'] in out, 'exit 1, and the package still waiting for dpkg --configure -a is said')
    rc, out = cli(env, 'dismiss', 'handover')
    listed = json.loads(subprocess.run(['sparky-stereo-problems', 'list', '--json'], capture_output=True, text=True, env=env).stdout)
    hidden = [p.get('hidden') for p in listed if p.get('key') == 'handover']
    check('dismiss', rc == 0 and kept(root, 'handover') is not None and hidden == [True] and (en['LOCAL53'] % 'handover') in out,
          "the person hides a problem: the engine's Hide, kept listed")
    rc, out = cli(env, 'dismiss', 'nothing-like-this')
    check('dismiss', rc == 1 and 'kernel-cleanup' in out, 'an unknown step names the kept ones (exit %d)' % rc)


def boot_check():
    def params(root, video, w, h):
        d = os.path.join(root, 'sys/kernel/boot_params')
        os.makedirs(d, exist_ok=True)
        data = bytearray(4096)
        data[0x0f] = video
        struct.pack_into('<HHH', data, 0x12, w, h, 32)
        open(os.path.join(d, 'data'), 'wb').write(bytes(data))

    def display(root, text):
        d = os.path.join(root, 'var/lib/sparky-stereo-boot')
        os.makedirs(d, exist_ok=True)
        open(os.path.join(d, 'grub-display'), 'w').write(text)
    saved = 'GFXMODE=3840x2160,1920x1080,1280x720,1024x768,auto\nWANTED=3840x2160\nSOURCE=saved\nFONT=\nPAYLOAD=keep\nSCREEN=card0-HDMI-A-1\n'
    root, env = setup()
    params(root, 0x70, 1920, 1080)
    display(root, saved)
    rc, out = cli(env, 'boot-check')
    k = kept(root, 'grub-mode')
    check('boot-check', rc == 1 and bool(k) and k['key'] == 'LOCAL46' and k['args'] == ['1920x1080', '3840x2160', '3840x2160'],
          'GRUB showed 1920x1080, not the saved 3840x2160: kept (%s)' % (k and k['args']))
    params(root, 0x70, 3840, 2160)
    rc, out = cli(env, 'boot-check')
    check('boot-check', rc == 0 and kept(root, 'grub-mode') is None, 'GRUB showed what it was given: cleared')
    params(root, 0x70, 1920, 1080)
    display(root, saved.replace('PAYLOAD=keep', 'PAYLOAD=text'))
    rc, out = cli(env, 'boot-check')
    check('boot-check', rc == 0 and kept(root, 'grub-mode') is None, "the person's own gfxpayload: not checked")


def languages():
    """Every message the code uses exists in the nine languages, with the English %s count and no other directive."""
    used = set()
    for path in ('bin/sparky-stereo-boot', 'lib/problems.py', 'lib/secureboot.py', 'lib/kernel-keep.py',
                 'grub/30-sparky-stereo-boot.cfg', 'build.sh'):
        used |= set(re.findall(r'LOCAL\d+', open(os.path.join(PKG, path), encoding='utf-8').read()))
    used |= {'LOCAL56', 'LOCAL57', 'LOCAL58'}   # written into postrm by build.sh
    en = strings('en')
    missing, counts = [], []
    for lang in LANGS:
        s = strings(lang)
        for key in sorted(used, key=lambda k: int(k[5:])):
            if key not in s:
                missing.append('%s %s' % (lang, key))
            elif s[key].count('%s') != en.get(key, '').count('%s') or '%' in s[key].replace('%s', ''):
                counts.append('%s %s' % (lang, key))
    check('languages', not missing, '%d messages in the code, each in the nine languages (%s)' % (len(used), ' '.join(missing) or 'none missing'))
    check('languages', not counts, 'the same %%s count as English, no other directive (%s)' % (' '.join(counts) or 'all match'))


def main():
    for part in (handover, problems, boot_check, languages):
        try:
            part()
        except Exception as error:   # noqa: BLE001: a part that cannot run is a failure, said
            check(part.__name__, False, 'did not run: %s: %s' % (type(error).__name__, error))
    print('== %s' % ('ALL PASS' if all(results) else '%d FAILED' % results.count(False)))
    sys.exit(0 if all(results) else 1)


if __name__ == '__main__':
    main()
