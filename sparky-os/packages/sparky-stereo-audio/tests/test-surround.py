#!/usr/bin/python3 -I
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
"""Run in an isolated container. These checks do not establish rendered sound."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('surround', Path(__file__).resolve().parents[1] / 'lib/surround.py')
s = importlib.util.module_from_spec(spec)
spec.loader.exec_module(s)


class Reconcile(unittest.TestCase):
    def test_ports_are_not_buses(self):
        self.assertFalse(s.headphone({'properties': {'device.bus': 'usb'}}))
        self.assertFalse(s.headphone({'properties': {'api.bluez5.profile': 'a2dp-sink'}}))
        self.assertTrue(s.headphone({'properties': {'device.form_factor': 'headset'}}))
        self.assertTrue(s.headphone({'active_port': 'front', 'ports': [{'name': 'front', 'type': 'Headphones'}]}))
        self.assertFalse(s.headphone({'active_port': 'line', 'ports': [
            {'name': 'front', 'type': 'Headphones'}, {'name': 'line', 'type': 'Line'}]}))

    def test_disconnected_and_pcm_only(self):
        text = 'monitor_present 1\neld_valid 1\nsad_count 1\nsad0_coding_type [0x1] LPCM\n'
        self.assertEqual(s.eld_formats(text), [])
        text += 'sad1_coding_type [0x2] AC-3\n'
        self.assertEqual(s.eld_formats(text), [])
        text = text.replace('sad_count 1', 'sad_count 2')
        self.assertEqual(s.eld_formats(text), ['AC3'])
        self.assertEqual(s.eld_formats(text.replace('eld_valid 1', 'eld_valid 0')), [])

    def test_all_requested_codecs(self):
        text = 'monitor_present 1\neld_valid 1\nsad_count 5\n'
        text += '\n'.join('sad%d_coding_type [0x%x] ignored-label' % (i, code)
                          for i, code in enumerate((2, 7, 10, 11, 12)))
        self.assertEqual(s.eld_formats(text), ['AC3', 'DTS', 'DTSHD', 'EAC3', 'TRUEHD'])

    def test_direction_and_no_pinned_rate(self):
        for layout, channels in (( '5.1', 6), ('7.1', 8)):
            graph = s.binaural(layout)
            self.assertEqual(len(graph['inputs']), channels)
            args = s.module_args('test', 'headphones', graph, s.LAYOUTS[layout], 'test')
            self.assertNotIn('audio.rate', str(args))
            self.assertNotIn('node.rate', str(args))
            self.assertTrue(args['playback.props']['node.linger'])
            self.assertTrue(args['playback.props']['node.dont-fallback'])
        self.assertEqual(s.ANGLES['FL'], 30)
        self.assertEqual(s.ANGLES['FR'], 330)


if __name__ == '__main__':
    unittest.main()
