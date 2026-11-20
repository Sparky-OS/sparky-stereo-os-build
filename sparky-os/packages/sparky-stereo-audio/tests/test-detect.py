#!/usr/bin/python3 -I
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/16
# Copyright 2026 under the GNU GPL3 License
"""Tests of sparky-stereo-audio's reading of the devices, its choices and its files (ORDER 631).
Run: python3 -I tests/test-detect.py [PATH-TO-sparky-stereo-audio]   (no root, no sound system needed)"""
import importlib.machinery, importlib.util, os, re, shutil, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = sys.argv.pop(1) if len(sys.argv) > 1 and sys.argv[1].endswith('sparky-stereo-audio') else os.path.join(HERE, '..', 'bin', 'sparky-stereo-audio')
loader = importlib.machinery.SourceFileLoader('ssa', TOOL)
spec = importlib.util.spec_from_loader('ssa', loader)
ssa = importlib.util.module_from_spec(spec)
loader.exec_module(ssa)
# the engine's library: beside the source tree's bin/, or in an unpacked package's usr/lib/sparky-stereo-audio
LIB = [d for d in (os.path.join(os.path.dirname(os.path.realpath(TOOL)), '..', 'lib'),
                   os.path.join(os.path.dirname(os.path.realpath(TOOL)), '..', 'lib', 'sparky-stereo-audio')) if os.path.exists(os.path.join(d, 'session.py'))][0]


def install_lib(root):
    dest = root + '/usr/lib/sparky-stereo-audio'
    os.makedirs(dest)
    for f in os.listdir(LIB):
        if f.endswith('.py'):
            shutil.copy(os.path.join(LIB, f), dest)

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
        install_lib(self.root)
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

    def test_write_makes_the_four_drop_ins(self):
        r = self.run_tool('detect', '--write')
        self.assertEqual(r.returncode, 0, r.stderr)
        for f in ('etc/pipewire/pipewire.conf.d', 'etc/pipewire/client.conf.d',
                  'etc/pipewire/pipewire-pulse.conf.d', 'etc/wireplumber/wireplumber.conf.d'):
            self.assertTrue(os.path.exists(self.path(f, '00-sparky-stereo-audio.conf')), f)
        t = open(self.path('etc/pipewire/pipewire.conf.d/00-sparky-stereo-audio.conf')).read()
        self.assertIn('default.clock.allowed-rates = [ 16000 32000 44100 48000 88200 96000 192000 ]', t)
        self.assertIn('default.clock.rate = 48000', t)
        self.assertIn('resample.quality = 14', open(self.path('etc/pipewire/client.conf.d/00-sparky-stereo-audio.conf')).read())
        w = open(self.path('etc/wireplumber/wireplumber.conf.d/00-sparky-stereo-audio.conf')).read()
        self.assertIn('resample.quality = 14, dither.method = triangular', w)

    def test_the_quality_follows_the_processor(self):
        for cost, q in (('10.7', 14), ('20.0', 14), ('20.1', 13), ('23', 12), ('30', 12), ('100', 10), ('150', 6), ('900', 4)):
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


IDLE = os.path.join(HERE, 'fixtures', 'station-idle')
NO_DISPLAY = 'monitor_present\t\t0\neld_valid\t\t0\ncodec_pin_nid\t\t%s\n'


def copy_station(dest, no_display=False, no_eld=False, pcm_open=False):
    """The station's real /proc/asound with no stream playing (fixtures/station-idle: card0 NVidia, card1 Creative, card2
    Generic, copied on 2026-11-19 with both televisions lit), or the same cards in another state."""
    shutil.copytree(IDLE, dest)
    for card in ('card0', 'card2'):
        for f in os.listdir(os.path.join(dest, card)):
            p = os.path.join(dest, card, f)
            if f.startswith('eld#') and no_eld:
                os.unlink(p)
            elif f.startswith('eld#') and no_display:
                pin = re.search(r'codec_pin_nid\s+(\S+)', open(p).read()).group(1)
                open(p, 'w').write(NO_DISPLAY % pin)
    if pcm_open:       # the kernel prints a Device line under the converter that holds a stream (sound/hda/common/proc.c)
        for card, node, name, dev in (('card0', '0x08', 'HDMI 0', 3), ('card2', '0x04', 'HDMI 1', 7)):
            p = os.path.join(dest, card, 'codec#0')
            t = open(p).read()
            open(p, 'w').write(re.sub(r'(Node %s \[Audio Output\][^\n]*\n)' % node,
                                      r'\1  Device: name="%s", type="HDMI", device=%d\n' % (name, dev), t, count=1))


class GraphicsCardAudio(unittest.TestCase):
    """ORDER 757: a graphics card's HDMI or DisplayPort sound is read whether or not a PCM is open."""

    def setUp(self):
        self.root = tempfile.mkdtemp(prefix='ssa-hdmi.')
        self.addCleanup(shutil.rmtree, self.root)

    def station(self, name, **kw):
        dest = os.path.join(self.root, name)
        copy_station(dest, **kw)
        return dest

    def by_id(self, cards):
        return {c['id']: c for c in cards}

    def test_the_idle_codec_has_no_device_line(self):
        for card in ('card0', 'card2'):
            self.assertNotIn('Device:', open(os.path.join(IDLE, card, 'codec#0')).read())

    def test_displays_connected_are_the_outputs_with_no_pcm_open(self):
        cards = self.by_id(ssa.scan(IDLE))
        nv, gen = cards['NVidia'], cards['Generic']
        self.assertTrue(nv['readable'] and nv['hdmi'] and gen['readable'] and gen['hdmi'])
        self.assertEqual([(o['label'], o['rates']) for o in nv['outputs']], [('SONY TV', [32000, 44100, 48000])])
        self.assertEqual(sorted((o['label'], tuple(o['rates'])) for o in gen['outputs']),
                         [('LE26W154', (32000, 44100, 48000)), ('SONY TV', (32000, 44100, 48000))])
        self.assertEqual(ssa.choose_rates(list(cards.values()))[2], [])

    def test_the_result_is_the_same_with_a_pcm_open(self):
        idle = ssa.scan(IDLE)
        opened = ssa.scan(self.station('open', pcm_open=True))
        self.assertEqual(idle, opened)

    def test_the_converters_rates_limit_the_displays(self):
        # the NVidia converters list 32000 to 192000; a display that lists a rate no converter has gets no such rate
        d = self.station('limit')
        p = os.path.join(d, 'card0', 'eld#0.4')
        t = open(p).read().replace('sad0_rates\t\t[0xe0] 32000 44100 48000', 'sad0_rates\t\t[0xe0] 32000 44100 48000 384000')
        open(p, 'w').write(t)
        nv = self.by_id(ssa.scan(d))['NVidia']
        self.assertEqual(nv['outputs'][0]['rates'], [32000, 44100, 48000])

    def test_the_displays_rates_stand_alone_where_no_converter_lists_any(self):
        d = self.station('nopcm')
        for f in ('codec#0',):
            p = os.path.join(d, 'card2', f)
            t = open(p).read()
            t = re.sub(r'(Default PCM:\n\s*rates \[[^\]]*\]:)[^\n]*', r'\1', t)
            open(p, 'w').write(t)
        gen = self.by_id(ssa.scan(d))['Generic']
        self.assertEqual(sorted(o['label'] for o in gen['outputs']), ['LE26W154', 'SONY TV'])
        self.assertEqual(gen['outputs'][0]['rates'], [32000, 44100, 48000])

    def test_nothing_connected_is_a_card_read_with_no_output(self):
        for kw in ({'no_display': True}, {'no_eld': True}):
            cards = self.by_id(ssa.scan(self.station('none-%s' % list(kw)[0], **kw)))
            for cid in ('NVidia', 'Generic'):
                self.assertTrue(cards[cid]['readable'], kw)
                self.assertTrue(cards[cid]['hdmi'], kw)
                self.assertEqual(cards[cid]['outputs'], [], kw)
            self.assertEqual(ssa.choose_rates(list(cards.values()))[2], [], kw)

    def test_a_card_with_no_codec_file_or_an_empty_one_is_still_unreadable(self):
        cards = ssa.scan(self.tree([('Gone', {}), ('Blank', {'codec#0': ''})]))
        self.assertEqual([c['readable'] for c in cards], [False, False])
        self.assertEqual([c['id'] for c in ssa.choose_rates(cards)[2]], ['Gone', 'Blank'])

    def tree(self, spec):
        root = tempfile.mkdtemp(prefix='ssa-test.', dir=self.root)
        for i, (ident, files) in enumerate(spec):
            card(root, i, ident, files)
        return root

    def test_an_analog_codec_beside_the_displays_is_unchanged(self):
        cards = self.by_id(ssa.scan(IDLE))
        c = cards['Creative']
        self.assertFalse(c.get('hdmi'))
        self.assertEqual([o['label'] for o in c['outputs']], ['CA0132 Analog', 'CA0132 Digital'])

    def test_two_televisions_of_one_name_have_two_identities(self):
        ids = [o['display'] for c in ssa.scan(IDLE) for o in c['outputs'] if o['label'] == 'SONY TV']
        self.assertEqual(len(ids), 2)
        self.assertEqual(len(set(ids)), 2)
        self.assertEqual(sorted(ids), ['0xd94d:0x2c02:SONY TV', '0xd94d:0x7402:SONY TV'])

    def test_the_hdmi_pins_alone_make_a_graphics_card(self):
        self.assertIsNone(ssa.hdmi_codec(open(os.path.join(IDLE, 'card1', 'codec#1')).read()))
        self.assertEqual(ssa.hdmi_codec(open(os.path.join(IDLE, 'card2', 'codec#0')).read()), {32000, 44100, 48000})
        self.assertEqual(ssa.hdmi_codec(open(os.path.join(IDLE, 'card0', 'codec#0')).read()),
                         {32000, 44100, 48000, 88200, 96000, 176400, 192000})


class RememberedDisplays(unittest.TestCase):
    """What was read from a display is kept for that display and used while it is away (Daniel, 2026-11-19)."""

    def setUp(self):
        self.root = tempfile.mkdtemp(prefix='ssa-mem.')
        self.addCleanup(shutil.rmtree, self.root)
        install_lib(self.root)
        lang = self.root + '/usr/share/sparky/sparky-stereo-audio'
        os.makedirs(lang)
        for f in os.listdir(os.path.join(HERE, '..', 'lang')):
            shutil.copy(os.path.join(HERE, '..', 'lang', f), lang)
        self.with_displays = IDLE
        self.away = os.path.join(self.root, 'away')
        copy_station(self.away, no_display=True)

    def run_tool(self, proc, *args, lang='C'):
        e = dict(os.environ, SPARKY_STEREO_AUDIO_ROOT=self.root, SPARKY_STEREO_AUDIO_PROC=proc, SPARKY_STEREO_AUDIO_CPU_COST='10.7',
                 SPARKY_STEREO_AUDIO_SETTLE_STEP='0.05', LANG=lang, LANGUAGE='', LC_ALL='', HOME=self.root + '/home')
        return subprocess.run([sys.executable, '-I', TOOL] + list(args), capture_output=True, text=True, env=e)

    def store(self):
        import json
        return json.load(open(self.root + '/var/lib/sparky-stereo-audio/displays.json'))

    def conf(self):
        return open(self.root + '/etc/pipewire/pipewire.conf.d/00-sparky-stereo-audio.conf').read()

    def test_boot_with_the_displays_keeps_them_and_says_nothing(self):
        r = self.run_tool(self.with_displays, 'detect', '--write', '--settle')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn('could not be read', r.stderr + r.stdout)
        self.assertEqual(sorted(v['name'] for v in self.store().values()), ['LE26W154', 'SONY TV', 'SONY TV'])
        self.assertIn('SONY TV (Nvidia GPU 9f HDMI/DP): 32000 44100 48000 Hz', r.stdout)
        self.assertNotIn('remembered', r.stdout)

    def test_boot_without_a_display_is_no_fault(self):
        r = self.run_tool(self.away, 'detect', '--write')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn('could not be read', r.stderr + r.stdout)
        self.assertIn('no display is connected now', r.stdout)
        self.assertNotIn('No sound device was found', r.stdout)
        self.assertFalse(os.path.exists(self.root + '/var/lib/sparky-stereo-audio/displays.json') and self.store())

    def test_a_display_that_is_away_has_its_remembered_values(self):
        self.run_tool(self.with_displays, 'detect', '--write')
        before = self.store()
        r = self.run_tool(self.away, 'detect', '--write')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn('could not be read', r.stderr + r.stdout)
        self.assertIn('LE26W154 (ATI R6xx HDMI): 32000 44100 48000 Hz, up to 24 bit (remembered', r.stdout)
        self.assertIn('allowed-rates = [ 16000 32000 44100 48000 88200 96000 192000 ]', self.conf())
        self.assertEqual(self.store(), before)
        shown = self.run_tool(self.away, 'show').stdout
        self.assertIn('remembered', shown)

    def test_a_display_arriving_is_read_again_and_no_longer_remembered(self):
        self.run_tool(self.with_displays, 'detect', '--write')
        self.run_tool(self.away, 'detect', '--write')
        # the same television arrives with another audio block: the new values replace the old
        arrive = os.path.join(self.root, 'arrive')
        copy_station(arrive)
        p = os.path.join(arrive, 'card0', 'eld#0.4')
        text = open(p).read().replace('sad0_rates\t\t[0xe0] 32000 44100 48000', 'sad0_rates\t\t[0xe8] 32000 44100 48000 96000')
        open(p, 'w').write(text)
        r = self.run_tool(arrive, 'detect', '--write', '--settle')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn('remembered', r.stdout)
        self.assertEqual(self.store()['0xd94d:0x2c02:SONY TV']['rates'], [32000, 44100, 48000, 96000])
        self.assertIn('96000', self.conf())

    def test_the_same_display_on_another_port_is_the_same_display(self):
        self.run_tool(self.with_displays, 'detect', '--write')
        moved = os.path.join(self.root, 'moved')
        copy_station(moved)
        os.rename(os.path.join(moved, 'card0', 'eld#0.4'), os.path.join(moved, 'card0', 'eld#0.9'))
        self.run_tool(moved, 'detect', '--write')
        self.assertEqual(len(self.store()), 3)

    def test_the_sixteen_most_recent_displays_are_kept(self):
        store = {'x:%d' % i: {'name': 'D%d' % i, 'card': 'NVidia', 'rates': [48000], 'bits': [24], 'codecs': []} for i in range(20)}
        new = ssa.remember(ssa.scan(IDLE), store)
        self.assertEqual(len(new), 16)
        self.assertIn('0xd94d:0x7402:SONY TV', new)
        self.assertNotIn('x:0', new)

    def test_a_card_that_cannot_be_read_is_still_told_beside_the_displays(self):
        proc = os.path.join(self.root, 'mixed')
        copy_station(proc)
        os.makedirs(os.path.join(proc, 'card3'))
        open(os.path.join(proc, 'card3', 'id'), 'w').write('Broken\n')
        r = self.run_tool(proc, 'detect', '--write')
        self.assertIn('The sound devices Broken could not be read', r.stderr)

    def test_show_speaks_the_remembered_and_waiting_lines_in_every_language(self):
        self.run_tool(self.with_displays, 'detect', '--write')
        self.run_tool(self.away, 'detect', '--write')
        for lg, word in (('pt_BR.UTF-8', 'lembrado'), ('de_DE.UTF-8', 'gemerkt'), ('fr_FR.UTF-8', 'mémorisé'), ('es_ES.UTF-8', 'recordado'),
                         ('pl_PL.UTF-8', 'zapamiętane'), ('ja_JP.UTF-8', '記憶済み'), ('ko_KR.UTF-8', '기억된'), ('zh_CN.UTF-8', '已记住'),
                         ('zh_TW.UTF-8', '已記住')):
            self.assertIn(word, self.run_tool(self.away, 'show', lang=lg).stdout, lg)


if __name__ == '__main__':
    unittest.main(verbosity=2)
