#!/usr/bin/python3 -I
# Created by Daniel Ramos (Capitain Jack) 2026/11/19
# Copyright 2026 under the GNU GPL3 License
"""The judges' own tests (ORDER 22): each judge must say "does not hold" for a planted loss and "cannot run" for no data, so
that a row's red side means what it says. Run: python3 -I tests/test_judges.py"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROWS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "rows")


def judge(name, *args):
    return subprocess.run([sys.executable, "-I", os.path.join(ROWS, name)] + list(args), capture_output=True, text=True).returncode


class T(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp(prefix="lab-judge-", dir=os.environ.get("LAB_TEST_TMP"))
        self.addCleanup(shutil.rmtree, self.d, True)

    def w(self, name, text):
        p = os.path.join(self.d, name)
        open(p, "w").write(text)
        return p

    def audio_row(self, src, graph, dev=None, fmt="S32_LE", dither="triangular"):
        return json.dumps({"device": "dac", "source_rate": src, "graph_rate": graph, "device_rate": dev or graph, "device_format": fmt,
                           "resampled": graph != src, "stream_resample_quality": 14, "settings_clock_allowed_rates": "[ 48000 ]",
                           "settings_clock_rate": "48000", "sink_props_dither_method": dither})

    def test_audio_follow(self):
        ok = self.w("ok", self.audio_row(44100, 44100) + "\n" + self.audio_row(96000, 96000) + "\n")
        bad = self.w("bad", self.audio_row(44100, 48000) + "\n" + self.audio_row(96000, 96000) + "\n")
        self.assertEqual(judge("audio_judge.py", "follow", ok), 0)
        self.assertEqual(judge("audio_judge.py", "follow", bad), 1)
        self.assertEqual(judge("audio_judge.py", "follow", self.w("empty", "")), 77)

    def test_audio_dither16_needs_the_format_and_the_dither(self):
        ok = self.w("ok", self.audio_row(44100, 44100, fmt="S16_LE") + "\n")
        nodither = self.w("nd", self.audio_row(44100, 44100, fmt="S16_LE", dither="unset") + "\n")
        wide = self.w("w", self.audio_row(44100, 44100, fmt="S32_LE") + "\n")
        self.assertEqual(judge("audio_judge.py", "dither16", ok), 0)
        self.assertEqual(judge("audio_judge.py", "dither16", nodither), 1)
        self.assertEqual(judge("audio_judge.py", "dither16", wide), 1)

    def guest(self, hid, sdl):
        return "LAB|guest|kernel|x\nLAB|hid|kernel|device=/dev/input/event1|%s\nLAB|sdl|Pad|%s\nLAB|guest|done\n" % (hid, sdl)

    def test_input_loss_is_found_in_the_kernel_and_in_sdl(self):
        good = self.w("g", self.guest("buttons=128|axes=8|hat_codes=2|pressed=128", "buttons=128|axes=8|hats=1|pressed=128"))
        kern = self.w("k", self.guest("buttons=80|axes=8|hat_codes=2|pressed=80", "buttons=128|axes=8|hats=1|pressed=128"))
        sdl = self.w("s", self.guest("buttons=128|axes=8|hat_codes=2|pressed=128", "buttons=79|axes=8|hats=1|pressed=79"))
        axes = self.w("a", self.guest("buttons=128|axes=6|hat_codes=2|pressed=128", "buttons=128|axes=8|hats=1|pressed=128"))
        self.assertEqual(judge("input_judge.py", good), 0)
        for p in (kern, sdl, axes):
            self.assertEqual(judge("input_judge.py", p), 1)
        self.assertEqual(judge("input_judge.py", self.w("boot", "nothing\n")), 77)

    def test_screens_a_missing_mode_or_a_failed_check_does_not_hold(self):
        ok = "STEREO|check|kwin/fp-desktop 1920x1080|PASS|x\nSTEREO|check|kwin/fp-client 1920x1080|PASS|x\nSTEREO|summary|kwin|0 failed\n"
        bad = ok.replace("fp-client 1920x1080|PASS", "fp-client 1920x1080|FAIL")
        nomode = "STEREO|skip|kwin/fp|mode not listed by kscreen-doctor\nSTEREO|summary|kwin|0 failed\n"
        self.assertEqual(judge("screens_judge.py", self.w("o", ok), "fp"), 0)
        self.assertEqual(judge("screens_judge.py", self.w("b", bad), "fp"), 1)
        self.assertEqual(judge("screens_judge.py", self.w("n", nomode), "fp"), 1)
        self.assertEqual(judge("screens_judge.py", self.w("x", "STEREO|check|configfs/kwin|FAIL|no\n"), "fp"), 77)

    def test_a_crash_is_never_a_red(self):
        self.assertEqual(judge("audio_judge.py", "follow", os.path.join(self.d, "missing")), 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
