#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) and Claude Sonnet 5.5 2026/11/06
# Copyright 2026 under the GNU GPL3 License
# Checks of the 252c joins that live in the lists (ORDER 252c, study items J16 and J25): the developer task's terminal
# set and debsums are in developer.list and in make-lists.py (the list is generated, so a name only in the list is lost
# at the next run), the list is sorted, its header counts it, and no name is on a list that takes it out.
# Run: python3 -m unittest -v lists/tests/joins-252c-test.py
import pathlib, re, unittest

LISTS = pathlib.Path(__file__).resolve().parents[1]
TERMINAL_SET = ['ripgrep', 'fd-find', 'bat', 'fzf', 'tealdeer', 'ncdu', 'btop', 'tmux']


def names(path):
    return [l.split()[0] for l in path.read_text().splitlines() if l.strip() and not l.startswith('#')]


class DeveloperList(unittest.TestCase):
    def setUp(self):
        self.listed = names(LISTS / 'developer.list')

    def test_terminal_set_and_debsums_are_listed(self):
        for name in TERMINAL_SET + ['debsums']:
            self.assertIn(name, self.listed)

    def test_the_generator_names_them_too(self):
        source = (LISTS / 'make-lists.py').read_text()
        for name in TERMINAL_SET + ['debsums']:
            self.assertRegex(source, r"'%s'" % re.escape(name))

    def test_sorted_without_duplicates_and_counted(self):
        self.assertEqual(self.listed, sorted(set(self.listed)))
        header = (LISTS / 'developer.list').read_text().splitlines()[0]
        self.assertIn('(%d packages;' % len(self.listed), header)

    def test_not_on_a_list_that_takes_programs_out(self):
        for out in ('base-remove.list', 'aptus.list', 'not-on-image.tsv'):
            taken = set(names(LISTS / out)) if out.endswith('.list') else {l.split('\t')[0] for l in (LISTS / out).read_text().splitlines() if l and not l.startswith('#')}
            for name in TERMINAL_SET + ['debsums']:
                self.assertNotIn(name, taken, out)

    def test_no_alias_of_a_renamed_command(self):
        # fd-find installs fdfind and bat installs batcat; the edition never aliases them to the clashing names
        for path in (LISTS.parent / 'packages').glob('sparky-stereo-console/**/*'):
            if path.is_file():
                text = path.read_text(errors='replace')
                self.assertNotRegex(text, r"alias\s+(fd|bat)=")


if __name__ == '__main__':
    unittest.main()
