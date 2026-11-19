#!/usr/bin/python3 -I
# Created by Daniel Ramos (Capitain Jack) 2026/11/19
# Copyright 2026 under the GNU GPL3 License
"""The judges' own tests (ORDER 22): each judge must say "does not hold" for a planted loss and "cannot run" for no data, so
that a row's red side means what it says. Run: python3 -I tests/test_judges.py"""
import json
import os
import shutil
import struct
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

    # ---- deep colour: a 16 bit ramp is counted level by level ----
    def deep_run(self, shm, stereo, bits="16", lay="2d"):
        """A run folder of the deep steps for one layout: the frames (functions column -> 16 bit value) and the clients' logs."""
        d = tempfile.mkdtemp(dir=self.d)
        W, H = 1920, 40
        for tag, fn in (("shm-auto", shm), ("stereo", stereo)):
            row = b"".join(struct.pack(">HHH", fn(x), fn(x), fn(x)) for x in range(W))
            with open(os.path.join(d, "%s-%s.ppm" % (lay, tag)), "wb") as f:
                f.write(b"P6\n%d %d\n65535\n" % (W, H) + row * H)
        open(os.path.join(d, "client-%s-shm-auto.log" % lay), "w").write("formats: AR24\nshm 1920x1080 format ab48 (%s bits), ramp 0x8000..0x80ff\n" % bits)
        open(os.path.join(d, "client-%s-stereo.log" % lay), "w").write("stereo window\n")
        open(os.path.join(d, "results.txt"), "w").write("STEREO|deep|kwin exit 15\n")
        return os.path.join(d, "results.txt")

    def test_deep_a_16_bit_path_keeps_the_levels(self):
        ramp = lambda x: 0x8000 + x * 256 // 1920
        self.assertEqual(judge("deep_judge.py", self.deep_run(ramp, ramp), "2d"), 0)

    def test_deep_an_8_bit_scanout_or_a_10_bit_one_does_not_hold(self):
        ramp = lambda x: 0x8000 + x * 256 // 1920
        eight = lambda x: 0x8080
        ten = lambda x: 0x8000 + (x * 4 // 1920) * 64
        self.assertEqual(judge("deep_judge.py", self.deep_run(eight, ramp), "2d"), 1)
        self.assertEqual(judge("deep_judge.py", self.deep_run(ten, ramp), "2d"), 1)
        self.assertEqual(judge("deep_judge.py", self.deep_run(ramp, eight), "2d"), 1)

    def test_deep_a_client_that_drew_8_bits_proves_nothing(self):
        ramp = lambda x: 0x8000 + x * 256 // 1920
        self.assertEqual(judge("deep_judge.py", self.deep_run(ramp, ramp, bits="8"), "2d"), 1)

    def test_deep_the_other_eyes_ramp_in_this_eye_does_not_hold(self):
        ramp = lambda x: 0x8000 + x * 256 // 1920
        leak = lambda x: 0x9000 + x // 20 if x % 2 else 0x8000 + x * 256 // 1920
        self.assertEqual(judge("deep_judge.py", self.deep_run(ramp, leak), "2d"), 1)

    def test_deep_no_compositor_is_not_a_red(self):
        r = self.w("r", "STEREO|deep|socket after 1 half seconds\n")
        self.assertEqual(judge("deep_judge.py", r, "2d"), 77)

    # ---- the 2D-only EDID twin ----
    def test_screens_the_2d_edid_declares_no_3d_and_lists_none(self):
        d = tempfile.mkdtemp(dir=self.d)
        os.makedirs(os.path.join(d, "run"))
        res = os.path.join(d, "run", "results.txt")
        open(res, "w").write("STEREO|kwin|output HDMI-A-1, 0 3D modes listed\nSTEREO|summary|kwin|0 failed\n")
        open(os.path.join(d, "edid-decode.txt"), "w").write("  Vendor-Specific Data Block (HDMI), OUI 00-0C-03:\n    Source physical address: 1.0.0.0\n")
        self.assertEqual(judge("screens_judge.py", res, "edid-no-3d", "no-3d-modes"), 0)
        open(os.path.join(d, "edid-decode.txt"), "w").write("  Vendor-Specific Data Block (HDMI), OUI 00-0C-03:\n      3D present\n")
        self.assertEqual(judge("screens_judge.py", res, "edid-no-3d"), 1)
        open(res, "w").write("STEREO|kwin|output HDMI-A-1, 24 3D modes listed\nSTEREO|summary|kwin|0 failed\n")
        self.assertEqual(judge("screens_judge.py", res, "no-3d-modes"), 1)

    # ---- the eye order matrix ----
    def eyeorder(self, tags, drop=None, failed=0):
        lines = ["STEREO|eyeorder|kwin exit 15", "STEREO|check|eyeorder/ref|PASS|ok",
                 "STEREO|check|eyeorder/plain 2D swap off shows the left view|PASS|0 pixels differ",
                 "STEREO|check|eyeorder/plain 2D swap on shows the right view|PASS|0 pixels differ"]
        for t in tags:
            for sw in ("off", "on"):
                if (t, sw) != drop:
                    lines.append("STEREO|check|eyeorder/%s swap %s|PASS|ok" % (t, sw))
        lines.append("STEREO|summary|eyeorder|%d failed" % failed)
        return self.w("eo", "\n".join(lines) + "\n")

    def test_eyeorder_every_tag_needs_both_swaps(self):
        self.assertEqual(judge("eyeorder_judge.py", self.eyeorder(["hdmi-tab", "hdmi-fp"]), "hdmi-tab", "hdmi-fp"), 0)
        self.assertEqual(judge("eyeorder_judge.py", self.eyeorder(["hdmi-tab"]), "hdmi-tab", "hdmi-fp"), 1)
        self.assertEqual(judge("eyeorder_judge.py", self.eyeorder(["hdmi-tab", "hdmi-fp"], drop=("hdmi-fp", "on")), "hdmi-tab", "hdmi-fp"), 1)
        self.assertEqual(judge("eyeorder_judge.py", self.eyeorder(["hdmi-tab"], failed=1), "hdmi-tab"), 1)

    def test_eyeorder_a_right_first_tag_holds_only_when_no_such_twin_is_listed(self):
        none = self.w("n", open(self.eyeorder(["rows-left"])).read() + "STEREO|check|eyeorder/rows-right is not listed|PASS|no right eye first twin in the mode list\n")
        self.assertEqual(judge("eyeorder_judge.py", none, "rows-left", "rows-right"), 0)
        self.assertEqual(judge("eyeorder_judge.py", self.eyeorder(["rows-left"]), "rows-left", "rows-right"), 1)

    def test_eyeorder_a_failed_check_or_a_missing_reference_does_not_hold(self):
        good = self.eyeorder(["hdmi-tab"])
        bad = self.w("bad", open(good).read().replace("hdmi-tab swap on|PASS", "hdmi-tab swap on|FAIL"))
        self.assertEqual(judge("eyeorder_judge.py", good, "hdmi-tab"), 0)
        self.assertEqual(judge("eyeorder_judge.py", bad, "hdmi-tab"), 1)
        noref = self.w("nr", "STEREO|eyeorder|kwin exit 15\nSTEREO|eyeorder|the declared test client ended: no EGL_EXT_multiview_window\n")
        self.assertEqual(judge("eyeorder_judge.py", noref, "hdmi-tab"), 1)
        self.assertEqual(judge("eyeorder_judge.py", self.w("x", "STEREO|eyeorder|kwin: socket\n"), "hdmi-tab"), 77)

    # ---- the anaglyph ----
    def anaglyph_run(self, doctor_colour, window=(0, 0, 255)):
        from PIL import Image
        d = tempfile.mkdtemp(dir=self.d)
        for v in ("plain", "file", "filemode", "doctor"):
            im = Image.new("RGB", (64, 32), window)
            for x in range(8, 24):
                for y in range(8, 16):
                    im.putpixel((x, y), doctor_colour if v == "doctor" else (255, 0, 0))
            im.save(os.path.join(d, v + ".png"))
        open(os.path.join(d, "results.txt"), "w").write("STEREO|anaglyph|done\n")
        return os.path.join(d, "results.txt")

    def test_anaglyph_the_mix_of_the_two_views_holds_and_the_left_view_alone_does_not(self):
        self.assertEqual(judge("anaglyph_judge.py", self.anaglyph_run((164, 215, 0), window=(111, 0, 255)), "doctor"), 0)
        self.assertEqual(judge("anaglyph_judge.py", self.anaglyph_run((255, 0, 0)), "doctor"), 1)
        self.assertEqual(judge("anaglyph_judge.py", self.anaglyph_run((160, 215, 0), window=(111, 0, 255)), "doctor"), 1)
        self.assertEqual(judge("anaglyph_judge.py", self.w("x", "STEREO|anaglyph|plain after 1 grabs\n"), "doctor"), 77)

    def test_a_crash_is_never_a_red(self):
        self.assertEqual(judge("audio_judge.py", "follow", os.path.join(self.d, "missing")), 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
