#!/usr/bin/python3 -I
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/16
# Copyright 2026 under the GNU GPL3 License
"""Tests of sparky-stereo-audio's reading of the devices, its choices and its files (ORDER 631).
Run: python3 -I tests/test-detect.py [PATH-TO-sparky-stereo-audio]   (no root, no sound system needed)"""
import importlib.machinery, importlib.util, os, shutil, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = sys.argv.pop(1) if len(sys.argv) > 1 and sys.argv[1].endswith('sparky-stereo-audio') else os.path.join(HERE, '..', 'bin', 'sparky-stereo-audio')
loader = importlib.machinery.SourceFileLoader('ssa', TOOL)
spec = importlib.util.spec_from_loader('ssa', loader)
ssa = importlib.util.module_from_spec(spec)
loader.exec_module(ssa)

USB = """Generic USB Audio at usb-0000:00:14.0-2, high speed : USB Audio

Playback:
  Status: Stop
  Interface 1
    Altset 1
    Format: S16_LE
    Channels: 2
    Endpoint: 0x01 (1 OUT) (ASYNC)
    Rates: 44100, 48000
    Data packet interval: 125 us
    Bits: 16
  Interface 1
    Altset 2
    Format: S24_3LE S32_LE
    Channels: 2
    Endpoint: 0x01 (1 OUT) (ASYNC)
    Rates: 44100, 48000, 88200, 96000, 176400, 192000
    Data packet interval: 125 us
    Bits: 24

Capture:
  Status: Stop
  Interface 2
    Altset 1
    Format: S16_LE
    Channels: 1
    Endpoint: 0x81 (1 IN) (ASYNC)
    Rates: 8000
    Bits: 16
"""
USB16 = USB.split('  Interface 1\n    Altset 2')[0] + '\nCapture:\n  Status: Stop\n'
USBCONT = """X : USB Audio

Playback:
  Status: Stop
  Interface 1
    Altset 1
    Format: S16_LE
    Channels: 2
    Endpoint: 0x01 (1 OUT) (ASYNC)
    Rates: 8000 - 48000 (continuous)
    Bits: 16
"""


def card(root, n, ident, files):
    d = os.path.join(root, 'card%d' % n)
    os.makedirs(d)
    open(os.path.join(d, 'id'), 'w').write(ident + '\n')
    for k, v in files.items():
        open(os.path.join(d, k), 'w').write(v)


class Station(unittest.TestCase):
    """The real /proc/asound of a computer with a Creative card and two graphics cards' HDMI (copied as it is)."""

    def setUp(self):
        self.cards = ssa.scan(os.path.join(HERE, 'fixtures', 'station'))

    def test_creative_rates_come_from_the_codec(self):
        c = [x for x in self.cards if x['id'] == 'Creative'][0]
        analog = [o for o in c['outputs'] if o['label'] == 'CA0132 Analog'][0]
        self.assertEqual(analog['rates'], [16000, 44100, 48000, 88200, 96000, 192000])
        self.assertEqual(max(analog['bits']), 24)
        digital = [o for o in c['outputs'] if o['label'] == 'CA0132 Digital'][0]
        self.assertEqual(digital['rates'], [44100, 48000, 88200, 96000])      # no 192000 on the S/PDIF output

    def test_hdmi_comes_from_the_displays_audio_block(self):
        c = [x for x in self.cards if x['id'] == 'Generic'][0]
        names = sorted(o['label'] for o in c['outputs'])
        self.assertEqual(names, ['LE26W154', 'SONY TV'])
        for o in c['outputs']:
            self.assertEqual(o['rates'], [32000, 44100, 48000])
            self.assertEqual(o['bits'], [16, 20, 24])

    def test_the_union_and_the_idle_rate(self):
        rates, default, un = ssa.choose_rates(self.cards)
        self.assertEqual(rates, [16000, 32000, 44100, 48000, 88200, 96000, 192000])
        self.assertEqual(default, 48000)
        self.assertEqual(un, [])
        self.assertFalse(ssa.sixteen_only(self.cards))


class Devices(unittest.TestCase):
    def tree(self, spec):
        root = tempfile.mkdtemp(prefix='ssa-test.')
        self.addCleanup(shutil.rmtree, root)
        for i, (ident, files) in enumerate(spec):
            card(root, i, ident, files)
        return root

    def test_usb_dac_gives_its_rates_and_best_bits(self):
        cards = ssa.scan(self.tree([('DAC', {'stream0': USB})]))
        rates, default, un = ssa.choose_rates(cards)
        self.assertEqual(rates, [44100, 48000, 88200, 96000, 176400, 192000])
        self.assertEqual(max(max(o['bits']) for o in cards[0]['outputs']), 32)
        self.assertEqual(len(cards[0]['outputs']), 2)       # two altsettings; the capture endpoint is not an output

    def test_a_16_bit_only_device_is_found(self):
        cards = ssa.scan(self.tree([('Cheap', {'stream0': USB16})]))
        self.assertTrue(ssa.sixteen_only(cards))
        rates, default, un = ssa.choose_rates(cards)
        self.assertEqual(rates, [44100, 48000])

    def test_continuous_rates_stand_for_the_standards_between(self):
        cards = ssa.scan(self.tree([('Cont', {'stream0': USBCONT})]))
        self.assertEqual(cards[0]['outputs'][0]['rates'], [32000, 44100, 48000])

    def test_a_card_that_cannot_be_read_keeps_the_standard_rates_and_is_said(self):
        cards = ssa.scan(self.tree([('Old', {})]))
        rates, default, un = ssa.choose_rates(cards)
        self.assertEqual(rates, [32000, 44100, 48000, 88200, 96000, 176400, 192000])
        self.assertEqual([c['id'] for c in un], ['Old'])

    def test_no_card_at_all(self):
        rates, default, un = ssa.choose_rates(ssa.scan(self.tree([])))
        self.assertEqual(default, 48000)
        self.assertIn(192000, rates)

    def test_a_device_without_48000_takes_44100_as_the_idle_rate(self):
        usb = USB16.replace('Rates: 44100, 48000', 'Rates: 44100')
        cards = ssa.scan(self.tree([('X', {'stream0': usb})]))
        self.assertEqual(ssa.choose_rates(cards)[1], 44100)


class Run(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp(prefix='ssa-run.')
        self.addCleanup(shutil.rmtree, self.root)
        lang = self.root + '/usr/share/sparky/sparky-stereo-audio'
        os.makedirs(lang)
        for f in os.listdir(os.path.join(HERE, '..', 'lang')):
            shutil.copy(os.path.join(HERE, '..', 'lang', f), lang)
        self.proc = os.path.join(HERE, 'fixtures', 'station')

    def run_tool(self, *args, cost='10.7', lang='C', env=None):
        e = dict(os.environ, SPARKY_STEREO_AUDIO_ROOT=self.root, SPARKY_STEREO_AUDIO_PROC=self.proc,
                 SPARKY_STEREO_AUDIO_CPU_COST=cost, LANG=lang, LANGUAGE='', LC_ALL='', HOME=self.root + '/home')
        e.update(env or {})
        return subprocess.run([sys.executable, '-I', TOOL] + list(args), capture_output=True, text=True, env=e)

    def path(self, *p):
        return os.path.join(self.root, *p)

    def test_write_makes_the_five_drop_ins(self):
        r = self.run_tool('detect', '--write')
        self.assertEqual(r.returncode, 0, r.stderr)
        for f in ('etc/pipewire/pipewire.conf.d', 'etc/pipewire/client.conf.d', 'etc/pipewire/jack.conf.d',
                  'etc/pipewire/pipewire-pulse.conf.d', 'etc/wireplumber/wireplumber.conf.d'):
            self.assertTrue(os.path.exists(self.path(f, '00-sparky-stereo-audio.conf')), f)
        t = open(self.path('etc/pipewire/pipewire.conf.d/00-sparky-stereo-audio.conf')).read()
        self.assertIn('default.clock.allowed-rates = [ 16000 32000 44100 48000 88200 96000 192000 ]', t)
        self.assertIn('default.clock.rate = 48000', t)
        self.assertIn('resample.quality = 14', open(self.path('etc/pipewire/client.conf.d/00-sparky-stereo-audio.conf')).read())
        w = open(self.path('etc/wireplumber/wireplumber.conf.d/00-sparky-stereo-audio.conf')).read()
        self.assertIn('resample.quality = 14, dither.method = triangular', w)

    def test_the_quality_follows_the_processor(self):
        for cost, q in (('10.7', 14), ('15.0', 14), ('15.1', 13), ('17', 12), ('30', 12), ('100', 8), ('900', 4)):
            shutil.rmtree(self.path('var'), ignore_errors=True)
            r = self.run_tool('detect', '--write', cost=cost)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn('resample.quality = %d' % q, open(self.path('etc/pipewire/client.conf.d/00-sparky-stereo-audio.conf')).read(), cost)

    def test_a_second_run_changes_nothing(self):
        self.run_tool('detect', '--write')
        before = {p: os.stat(p).st_mtime_ns for p in self.files()}
        self.run_tool('detect', '--write')
        self.assertEqual(before, {p: os.stat(p).st_mtime_ns for p in self.files()})

    def files(self):
        out = []
        for d, _, fs in os.walk(self.path('etc')):
            out += [os.path.join(d, f) for f in fs]
        return out

    def test_a_file_of_the_person_with_our_name_is_left_alone_and_said(self):
        os.makedirs(self.path('etc/pipewire/pipewire.conf.d'))
        mine = self.path('etc/pipewire/pipewire.conf.d/00-sparky-stereo-audio.conf')
        open(mine, 'w').write('context.properties = { default.clock.rate = 96000 }\n')
        r = self.run_tool('detect', '--write')
        self.assertEqual(open(mine).read(), 'context.properties = { default.clock.rate = 96000 }\n')
        self.assertIn('is not the file this package wrote', r.stderr)
        self.assertTrue(os.path.exists(self.path('etc/pipewire/client.conf.d/00-sparky-stereo-audio.conf')))

    def test_a_folder_that_cannot_be_written_is_said(self):
        os.makedirs(self.path('etc/pipewire'))
        open(self.path('etc/pipewire/client.conf.d'), 'w').write('a file where the folder should be\n')
        r = self.run_tool('detect', '--write')
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('could not be written', r.stderr)

    def test_show_speaks_the_persons_language(self):
        self.run_tool('detect', '--write')
        en = self.run_tool('show').stdout
        self.assertIn('Rates the sound system may switch to', en)
        self.assertIn('up to 24 bit', en)
        self.assertIn('CA0132 Analog', en)
        for lg, word in (('pt_BR.UTF-8', 'Taxas'), ('de_DE.UTF-8', 'Raten'), ('ja_JP.UTF-8', 'レート'), ('zh_TW.UTF-8', '取樣率'),
                         ('es_MX.UTF-8', 'Frecuencias'), ('fr_CA.UTF-8', 'Fréquences'), ('pl_PL.UTF-8', 'Częstotliwości'),
                         ('ko_KR.UTF-8', '샘플레이트'), ('zh_CN.UTF-8', '采样率')):
            self.assertIn(word, self.run_tool('show', lang=lg).stdout, lg)

    def test_show_before_any_choice_says_what_to_do(self):
        r = self.run_tool('show')
        self.assertEqual(r.returncode, 1)
        self.assertIn('sudo sparky-stereo-audio detect --write', r.stdout)

    def test_a_person_setting_is_seen(self):
        home = self.path('home/.config/pipewire/pipewire.conf.d')
        os.makedirs(home)
        open(home + '/99-clock-rates.conf', 'w').write('context.properties = {\n  default.clock.allowed-rates = [ 44100 96000 ]\n}\n')
        old_home = os.environ.get('HOME')
        os.environ['HOME'] = self.path('home')
        try:
            self.assertTrue(ssa.person_sets('default.clock.allowed-rates'))
            self.assertFalse(ssa.person_sets('default.clock.quantum'))
        finally:
            if old_home is None:
                del os.environ['HOME']
            else:
                os.environ['HOME'] = old_home

    def test_every_language_has_every_message(self):
        import re
        d = os.path.join(HERE, '..', 'lang')
        en = {int(m.group(1)): m.group(2) for m in re.finditer(r'^LOCAL(\d+)="(.*)"$', open(d + '/en').read(), re.M)}
        for f in os.listdir(d):
            t = {int(m.group(1)): m.group(2) for m in re.finditer(r'^LOCAL(\d+)="(.*)"$', open(os.path.join(d, f)).read(), re.M)}
            self.assertEqual(sorted(t), sorted(en), f)
            for k in en:
                self.assertEqual(en[k].count('%s'), t[k].count('%s'), '%s LOCAL%d' % (f, k))
                self.assertEqual(en[k].count('%%'), t[k].count('%%'), '%s LOCAL%d' % (f, k))
        self.assertEqual(sorted(os.listdir(d)), ['de', 'en', 'es', 'fr', 'ja', 'ko', 'pl', 'pt_BR', 'zh_CN', 'zh_TW'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
