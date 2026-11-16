#!/usr/bin/env python3
"""Check the carried headers and prove their diffs survive the rewrite."""
from pathlib import Path
import re
import unittest

from patch_authors import sanitize


class PatchAuthors(unittest.TestCase):
    def test_header_only(self):
        address = 'a' + '@' + 'example.invalid'
        text = ('From ' + 'a' * 40 + ' Mon Sep 17 00:00:00 2001\n'
                'From: A Person <' + address + '>\n'
                ' Signed-off-by: A Person <' + address + '>\n'
                'Co-authored-by: Another Person <' + address + '>\n'
                'Signed-off-by: Daniel Campos Ramos <Capitain_Jack@yahoo.com>\n'
                '\ndiff --git a/a b/a\n--- a/a\n+++ b/a\n'
                '@@ -1 +1 @@\n-old\n+' + address + '\n')
        result = sanitize(text)
        self.assertEqual(result.split('diff --git', 1)[1], text.split('diff --git', 1)[1])
        header = result.split('diff --git', 1)[0]
        self.assertNotIn(address, header)
        self.assertIn('Author: A Person\n', header)
        self.assertIn(' Signed-off-by: A Person\n', header)
        self.assertIn('Co-authored-by: Another Person\n', header)
        self.assertIn('Capitain_Jack@yahoo.com', header)
        self.assertIn('Origin: upstream, https://git.ffmpeg.org/', header)
        self.assertEqual(result, sanitize(result))

    def test_recipe_headers(self):
        recipe = Path(__file__).resolve().parents[2] / 'media/ffmpeg/stereo3d15/patches'
        for patch in recipe.glob('*.patch'):
            text = patch.read_text()
            self.assertEqual(text, sanitize(text), patch.name)
            header = re.split(r'^diff --git |^--- a/', text, maxsplit=1, flags=re.M)[0]
            self.assertIsNone(re.search(r'<(?!Capitain_Jack@yahoo\.com>)[^<>\s]+@[^<>\s]+>', header), patch.name)
        for name in ['01_clean-output.patch', '02_vf_xfade-3.6.6.patch', '03_fix-padding-in-mp3.patch']:
            self.assertFalse((recipe / name).exists())
            self.assertIn(name, (recipe / 'series').read_text().splitlines())


if __name__ == '__main__':
    unittest.main()
