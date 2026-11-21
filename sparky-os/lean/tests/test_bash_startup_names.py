"""Rows 629/802: the startup files bash reads by name are shell wherever they are installed, as /etc/skel/.bashrc was;
sparky-stereo-console's /etc/skel/.bash_aliases is projected and keeps its authored text in the -lc-hr companion."""

from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from lean import consumers, project  # noqa: E402

ALIASES = b'''# Sparky Stereo OS: read by Debian's ~/.bashrc, after it has made the prompt.
if [ -x /usr/bin/dircolors ]; then
    # grep in colour
    alias grep='grep --color=auto'
fi
export EDITOR=nano VISUAL=nano
'''


class BashStartupNames(unittest.TestCase):
    def test_names_are_shell(self):
        for name in consumers.BASH_STARTUP_NAMES:
            for where in ('/etc/skel/', '/usr/share/x/skel/'):
                self.assertEqual(consumers.choose(where + name, b'# x\nalias a=b\n')[:2], ('shell', 'bash'), where + name)

    def test_other_dot_files_are_not(self):
        for path in ('/etc/skel/.selected_editor', '/etc/skel/.bashrc.debian', '/etc/skel/.profile.d'):
            self.assertIsNone(consumers.choose(path, b'# x\nalias a=b\n')[0], path)

    def test_bash_aliases_projects(self):
        r = project.project('/etc/skel/.bash_aliases', ALIASES, 'sparky-stereo-console')
        self.assertEqual(r.status, 'projected', r.reason)
        self.assertNotIn(b'# grep in colour', r.lean)
        self.assertIn(b"alias grep='grep --color=auto'", r.lean)


if __name__ == '__main__':
    unittest.main()
