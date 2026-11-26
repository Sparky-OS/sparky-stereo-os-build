#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) and Claude Fable 5.2 2026/11/25
# Copyright 2026 under the GNU GPL3 License
# Queue row 96: the video background reaches every image. Its package is in image.list and in make-lists.py (the list
# is generated: a name only in the list is lost at the next run), the list is sorted and its header counts it, no list
# takes the package out again, and make-meta.py puts image.list into sparky-stereo-desktop.
# Run: python3 -m unittest -v lists/tests/video-wallpaper-96-test.py
import pathlib, re, unittest

LISTS = pathlib.Path(__file__).resolve().parents[1]
NAME = 'qml-module-org-kde-video-wallpaper'


def names(path):
    return [l.split()[0] for l in path.read_text().splitlines() if l.strip() and not l.startswith('#')]


class VideoWallpaperOnTheImage(unittest.TestCase):
    def test_listed_and_generated(self):
        self.assertIn(NAME, names(LISTS / 'image.list'))
        self.assertRegex((LISTS / 'make-lists.py').read_text(), r"group\('image',(?s:.*?)'%s'" % re.escape(NAME))

    def test_sorted_without_duplicates_and_counted(self):
        listed = names(LISTS / 'image.list')
        self.assertEqual(listed, sorted(set(listed)))
        self.assertIn('(%d packages;' % len(listed), (LISTS / 'image.list').read_text().splitlines()[0])

    def test_no_list_takes_it_out(self):
        for out in ('base-remove.list', 'aptus.list', 'not-on-image.tsv'):
            taken = set(names(LISTS / out)) if out.endswith('.list') else {l.split('\t')[0] for l in (LISTS / out).read_text().splitlines() if l and not l.startswith('#')}
            self.assertNotIn(NAME, taken, out)

    def test_the_desktop_meta_takes_the_image_list(self):
        self.assertRegex((LISTS / 'make-meta.py').read_text(), r"'sparky-stereo-desktop': \((?s:.*?)lst\('image'\)")


if __name__ == '__main__':
    unittest.main()
