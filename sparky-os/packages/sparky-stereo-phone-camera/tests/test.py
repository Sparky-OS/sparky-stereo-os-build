#!/usr/bin/python3
# Each failure of sparky-phone-camera says its own sentence, in the person's language; a working setup says nothing.
# The system is a fake root (SPARKY_PHONE_CAMERA_ROOT) and stand-ins for modinfo, pkexec and adb on the PATH.
# Usage: python3 -I tests/test.py   (from the package folder)
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.dirname(HERE)
BIN = os.path.join(PKG, 'bin', 'sparky-phone-camera')
LANGS = ['en', 'pl', 'pt_BR', 'fr', 'de', 'es', 'ja', 'ko', 'zh_CN', 'zh_TW']


def stub(folder, name, body):
    path = os.path.join(folder, name)
    with open(path, 'w') as handle:
        handle.write('#!/bin/sh\n' + body + '\n')
    os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)


class Rig:
    def __init__(self, loaded=False, device=False, built=True, pkexec_fail=None, adb=None):
        self.tmp = tempfile.TemporaryDirectory()
        root = self.tmp.name
        self.root = os.path.join(root, 'root')
        self.bin = os.path.join(root, 'bin')
        os.makedirs(self.bin)
        os.makedirs(os.path.join(self.root, 'sys/class/video4linux'))
        if loaded:
            os.makedirs(os.path.join(self.root, 'sys/module/v4l2loopback'))
        if device:
            os.makedirs(os.path.join(self.root, 'sys/class/video4linux/video7'))
            with open(os.path.join(self.root, 'sys/class/video4linux/video7/name'), 'w') as handle:
                handle.write('Phone camera\n')
        stub(self.bin, 'modinfo', '[ %s = yes ] || { echo "modinfo: ERROR: Module v4l2loopback not found." >&2; exit 1; }; echo /x/v4l2loopback.ko' % ('yes' if built else 'no'))
        if pkexec_fail:
            stub(self.bin, 'pkexec', 'echo "%s" >&2; exit 1' % pkexec_fail)
        else:
            stub(self.bin, 'pkexec', 'mkdir -p "$SPARKY_PHONE_CAMERA_ROOT/sys/module/v4l2loopback" "$SPARKY_PHONE_CAMERA_ROOT/sys/class/video4linux/video9"; echo "Phone camera" > "$SPARKY_PHONE_CAMERA_ROOT/sys/class/video4linux/video9/name"')
        if adb is not None:
            stub(self.bin, 'adb', 'echo "List of devices attached"; ' + ''.join('echo "%s\t%s"; ' % row for row in adb))
        self.env = {'PATH': self.bin + ':/usr/bin:/bin', 'SPARKY_PHONE_CAMERA_ROOT': self.root, 'SPARKY_PHONE_CAMERA_LANG': os.path.join(PKG, 'lang'), 'LANG': 'en_US.UTF-8'}

    def run(self, *args, lang='en_US.UTF-8', **extra):
        env = dict(self.env, LANG=lang, **extra)
        return subprocess.run([sys.executable, '-I', BIN] + list(args), capture_output=True, text=True, env=env)


def sentence(lang, key):
    # the lookup order of the edition: the whole LANG, the bare language, English
    for code in (lang, lang.split('_')[0], 'en'):
        path = os.path.join(PKG, 'lang', code + '.json')
        if os.path.isfile(path):
            with open(path, encoding='utf-8') as handle:
                return json.load(handle)[key]


class Catalogues(unittest.TestCase):
    def test_ten_languages_same_keys_same_placeholders(self):
        base = json.load(open(os.path.join(PKG, 'lang', 'en.json'), encoding='utf-8'))
        for code in LANGS:
            data = json.load(open(os.path.join(PKG, 'lang', code + '.json'), encoding='utf-8'))
            self.assertEqual(sorted(data), sorted(base), code)
            for key, text in data.items():
                self.assertEqual(text.count('%s'), base[key].count('%s'), (code, key))
                self.assertNotEqual(text.strip(), '', (code, key))
                if code != 'en':
                    self.assertNotEqual(text, base[key], (code, key, 'left in English'))


class Failures(unittest.TestCase):
    def check(self, rig, lang, key, *args, mode=('check', 'usb')):
        result = rig.run(*mode, lang=lang)
        code = lang.split('.')[0]
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertIn((sentence(code, key) % args if args else sentence(code, key)), result.stderr)
        return result

    def test_module_not_built_in_two_languages(self):
        for lang in ('en_US.UTF-8', 'pt_BR.UTF-8', 'de_DE.UTF-8'):
            r = Rig(built=False)
            res = self.check(r, lang, 'module_not_built', os.uname().release)
            self.assertNotIn('Traceback', res.stderr)

    def test_secure_boot_refusal_is_named(self):
        r = Rig(pkexec_fail="modprobe: ERROR: could not insert 'v4l2loopback': Key was rejected by service")
        res = self.check(r, 'fr_FR.UTF-8', 'secure_boot')
        self.assertIn('Secure Boot', res.stderr)
        self.assertNotIn('Key was rejected', res.stderr)

    def test_other_load_failure_gives_the_reason(self):
        r = Rig(pkexec_fail="modprobe: FATAL: Module v4l2loopback not found")
        self.check(r, 'en_US.UTF-8', 'module_failed', 'modprobe: FATAL: Module v4l2loopback not found')

    def test_no_adb(self):
        r = Rig(device=True)
        self.check(r, 'es_ES.UTF-8', 'no_program', 'adb')

    def test_no_phone_on_usb(self):
        self.check(Rig(device=True, adb=[]), 'ja_JP.UTF-8', 'no_phone_usb')

    def test_phone_has_not_allowed_the_computer(self):
        self.check(Rig(device=True, adb=[('ABC123', 'unauthorized')]), 'zh_CN.UTF-8', 'unauthorized')

    def test_phone_offline(self):
        self.check(Rig(device=True, adb=[('ABC123', 'offline')]), 'ko_KR.UTF-8', 'offline')

    def test_several_phones_names_them(self):
        self.check(Rig(device=True, adb=[('A1', 'device'), ('B2', 'device')]), 'pl_PL.UTF-8', 'several_phones', 'A1, B2')

    def test_wifi_no_answer_names_the_address(self):
        r = Rig(loaded=True, device=True)
        stub(r.bin, 'droidcam-cli', 'echo "Video: Connect failed to $2:$3" >&2; echo "Client v2.1.7"; exit 0')
        res = r.run('droidcam', 'wifi', '127.0.0.1', lang='zh_TW.UTF-8')
        self.assertEqual(res.returncode, 1, res.stderr)
        self.assertIn(sentence('zh_TW', 'no_answer_wifi') % '127.0.0.1:4747', res.stderr)

    def test_wifi_refused_connection_stops_a_client_that_would_wait_for_the_keyboard(self):
        r = Rig(loaded=True, device=True)
        stub(r.bin, 'droidcam-cli', "echo \"send error (111) 'Connection refused'\"; sleep 30")
        import time
        started = time.time()
        res = r.run('droidcam', 'wifi', '127.0.0.1', lang='ja_JP.UTF-8')
        self.assertEqual(res.returncode, 1, res.stderr)
        self.assertLess(time.time() - started, 15)
        self.assertIn(sentence('ja', 'no_answer_wifi') % '127.0.0.1:4747', res.stderr)

    def test_wifi_client_that_connects_is_left_alone(self):
        r = Rig(loaded=True, device=True)
        stub(r.bin, 'droidcam-cli', 'echo "Video: $1"; exit 0')
        res = r.run('droidcam', 'wifi', '127.0.0.1')
        self.assertEqual((res.returncode, res.stderr), (0, ''))
        self.assertIn('Video: -dev=/dev/video7', res.stdout)

    def test_module_loaded_on_demand_when_allowed(self):
        r = Rig()
        res = r.run('check', 'none')
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertIn(sentence('en', 'module_loading'), res.stderr)

    def test_unknown_language_is_english(self):
        self.check(Rig(built=False), 'xx_XX.UTF-8', 'module_not_built', os.uname().release)


class Announce(unittest.TestCase):
    def test_announce_removes_and_adds_the_one_device(self):
        r = Rig(loaded=True, device=True)
        log = os.path.join(r.tmp.name, 'udevadm.log')
        stub(r.bin, 'udevadm', 'echo "$@" >> %s' % log)
        stub(r.bin, 'pkexec', 'exec "$@"')
        res = r.run('announce')
        self.assertEqual((res.returncode, res.stderr), (0, ''), res.stderr)
        lines = open(log).read().splitlines()
        self.assertEqual(lines[0], 'trigger --action=remove --subsystem-match=video4linux --sysname-match=video7')
        self.assertEqual(lines[1], 'trigger --action=add --subsystem-match=video4linux --sysname-match=video7')

    def test_announce_without_a_camera_says_so(self):
        res = Rig().run('announce', lang='de_DE.UTF-8')
        self.assertEqual(res.returncode, 1)
        self.assertIn(sentence('de', 'no_device') % 'Phone camera', res.stderr)

    def test_announce_that_is_refused_gives_the_reason(self):
        r = Rig(loaded=True, device=True, pkexec_fail='Error executing command as another user: Not authorized')
        res = r.run('announce')
        self.assertEqual(res.returncode, 1)
        self.assertIn('Not authorized', res.stderr)


class Working(unittest.TestCase):
    def test_nothing_is_said_when_everything_is_there(self):
        r = Rig(loaded=True, device=True, adb=[('ABC123', 'device')])
        res = r.run('check', 'usb')
        self.assertEqual((res.returncode, res.stderr), (0, ''))

    def test_status(self):
        res = Rig(loaded=True, device=True).run('status')
        self.assertEqual(json.loads(res.stdout)['device'], '/dev/video7')


if __name__ == '__main__':
    unittest.main(verbosity=2)
