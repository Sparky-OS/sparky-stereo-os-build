#!/usr/bin/env python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/06
# Copyright 2026 under the GNU GPL3 License
"""reproducible.py: the one place where the tools that write a source package get their date (ORDER 421).

A source package must be the same bytes every time it is made from the same recipe commit.
The clock, the time zone, the umask and the moment a tree was checked out must not reach it.
This follows Debian's practice, reproducible-builds.org's SOURCE_DATE_EPOCH specification and dpkg-source(1), which says
"SOURCE_DATE_EPOCH: If set, it will be used as the timestamp (as seconds since the epoch) to clamp the mtime in the tar(5)
file entries" (supported since dpkg 1.18.11).
dpkg-source already sorts the members by name and writes owner 0, group 0; what is left for us is:
- the date of every changelog entry we write: it comes from the recipe, never from the clock, always in UTC (+0000);
- the mtime and mode of every file of debian/ before dpkg-source packs it (clamping only lowers a time, so a tree
  checked out before the recipe's date would keep its own checkout time; the umask decides the mode bits of new files).

The date of a recipe, in this order:
1. SOURCE_DATE_EPOCH in the environment (the caller names it: a successor's date belongs to its command, which lives in the
   caller's script);
2. the committer date of the last commit that touched the recipe's own paths, when they are committed and unchanged.
Otherwise the tool stops and says so: there is no third way, so no source is ever dated by the clock without the
person knowing.

Usage as a program (for shell recipes):
  reproducible.py epoch PATH...        print the recipe date as an epoch (step 1, else step 2 for these paths)
  reproducible.py rfc2822 EPOCH        print it as a changelog trailer date
  reproducible.py normalize EPOCH DIR  set the mtime and mode of everything under DIR
  reproducible.py normalize-tree EPOCH TREE  the same for what dpkg-source -b takes from TREE: debian/ and its include-binaries
"""
import datetime
import email.utils
import os
from pathlib import Path
import subprocess
import sys


class NoRecipeDate(Exception):
    pass


def epoch(paths=(), env=None):
    """The recipe's date as an integer epoch, or NoRecipeDate with the reason and what to do."""
    env = os.environ if env is None else env
    value = env.get('SOURCE_DATE_EPOCH')
    if value is not None:
        if not value.isdigit():
            raise NoRecipeDate(f'SOURCE_DATE_EPOCH={value!r} is not a number of seconds')
        return int(value)
    paths = [Path(p).resolve() for p in paths]
    if not paths:
        raise NoRecipeDate('no recipe date: set SOURCE_DATE_EPOCH (the date of this source belongs to its recipe, not to the clock)')
    top = paths[0] if paths[0].is_dir() else paths[0].parent
    try:
        root = Path(subprocess.check_output(['git', '-C', str(top), 'rev-parse', '--show-toplevel'], text=True,
                                            stderr=subprocess.DEVNULL).strip())
    except (OSError, subprocess.CalledProcessError):
        raise NoRecipeDate(f'{top} is in no git repository, so the recipe has no commit date: set SOURCE_DATE_EPOCH') from None
    rel = [str(p.relative_to(root)) for p in paths]
    dirty = subprocess.check_output(['git', '-C', str(root), 'status', '--porcelain', '--untracked-files=all', '--', *rel],
                                    text=True).strip()
    if dirty:
        raise NoRecipeDate('the recipe has changes that are not committed, so no commit names its date '
                           f'(commit them, or set SOURCE_DATE_EPOCH):\n{dirty}')
    stamp = subprocess.check_output(['git', '-C', str(root), 'log', '-1', '--format=%ct', '--', *rel], text=True).strip()
    if not stamp.isdigit():
        raise NoRecipeDate('no commit touches the recipe paths: ' + ' '.join(rel))
    return int(stamp)


def rfc2822(stamp):
    """A changelog trailer date, always UTC, English names, not locale or zone dependent."""
    return email.utils.format_datetime(datetime.datetime.fromtimestamp(int(stamp), datetime.timezone.utc))


def parse_trailer(text):
    """The epoch of the first changelog trailer in text (the date after ' -- Name <mail>  ')."""
    for line in text.splitlines():
        if line.startswith(' -- ') and '>  ' in line:
            return int(email.utils.parsedate_to_datetime(line.split('>  ', 1)[1].strip()).timestamp())
    raise ValueError('no changelog trailer')


def normalize(root, stamp):
    """mtime = stamp and mode 0755 (if any execute bit) or 0644, directories 0755, for every entry under root (symlinks
    keep their target; only their own time is set)."""
    root = Path(root)
    for dirpath, dirnames, filenames in os.walk(root, topdown=False):
        for name in filenames + dirnames:
            p = Path(dirpath, name)
            if p.is_symlink():
                os.utime(p, (stamp, stamp), follow_symlinks=False)
                continue
            if p.is_dir():
                os.chmod(p, 0o755)
            else:
                os.chmod(p, 0o755 if p.stat().st_mode & 0o111 else 0o644)
            os.utime(p, (stamp, stamp))
    os.chmod(root, 0o755)
    os.utime(root, (stamp, stamp))


def normalize_tree(tree, stamp):
    """What dpkg-source -b takes from a source tree into the Debian tarball: debian/ and the binary files that
    debian/source/include-binaries lists (they travel in that tarball under their upstream paths, with their own mtime
    and mode; kwin's autotests/integration/data/*.bin differed between runs under another umask)."""
    tree = Path(tree)
    normalize(tree / 'debian', stamp)
    listing = tree / 'debian/source/include-binaries'
    if listing.is_file():
        for line in listing.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            path = tree / line
            if not path.is_file() or path.is_symlink():
                raise NoRecipeDate(f'debian/source/include-binaries names {line}, which is not a regular file of the tree')
            os.chmod(path, 0o755 if path.stat().st_mode & 0o111 else 0o644)
            os.utime(path, (stamp, stamp))


def pack(workdir, tree, stamp, **kw):
    """dpkg-source -b TREE in WORKDIR with its Debian tarball inputs normalized and SOURCE_DATE_EPOCH set (dpkg-source clamps the tar times)."""
    normalize_tree(Path(workdir) / tree, stamp)
    env = {**os.environ, 'SOURCE_DATE_EPOCH': str(stamp)}
    return subprocess.run(['dpkg-source', '-b', tree], cwd=workdir, check=True, env=env, **kw)


def main(argv):
    try:
        if len(argv) >= 2 and argv[0] == 'epoch':
            print(epoch(argv[1:]))
        elif len(argv) == 2 and argv[0] == 'rfc2822':
            print(rfc2822(argv[1]))
        elif len(argv) == 3 and argv[0] == 'normalize':
            normalize(argv[2], int(argv[1]))
        elif len(argv) == 3 and argv[0] == 'normalize-tree':
            normalize_tree(argv[2], int(argv[1]))
        else:
            sys.exit(__doc__)
    except NoRecipeDate as error:
        sys.exit(f'reproducible: {error}')


if __name__ == '__main__':
    main(sys.argv[1:])
