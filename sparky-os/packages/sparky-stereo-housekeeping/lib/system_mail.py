#!/usr/bin/python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/11/06
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/11/06
"""BleachBit's "System mail" cleaner: the one file that depends on what is installed, and its translations.

BleachBit's cleaners are plain files (CleanerML) and CleanerML has no condition on a package, so the option that clears
the leftover queues of removed mail programs is written here: a queue is listed only when dpkg says every package of
its mail program is gone (db:Status-Status not-installed or config-files) and the program itself is not on the system
(a program built by hand has no package, and its queue is in use). The queue of an installed mail program is never
listed. dpkg runs this again (a trigger) whenever one of those programs is installed or removed.

BleachBit translates a cleaner's text with its own catalog (the domain bleachbit, /usr/share/locale/LL/LC_MESSAGES),
which Debian's bleachbit package owns, so this package diverts that file (dpkg-divert, to bleachbit.mo.debian) and
writes in its place Debian's catalog and this package's strings in one (msgunfmt, msgcat --use-first, msgfmt): Debian's
translation of a string always wins. It is written again when bleachbit is upgraded (trigger on its cleaners folder).

  system_mail.py refresh    write the cleaner and the catalogs; nothing else is touched
  system_mail.py remove     take the cleaner away and give Debian's catalogs back (the package's removal)
  system_mail.py show       print the cleaner that refresh would write

Environment, for tests: SPARKY_HOUSEKEEPING_SHARE names the folder of system_mail.xml.in and po/, and
SPARKY_HOUSEKEEPING_ROOT prefixes every path it writes and reads (not the dpkg database).
"""
import os
import subprocess
import sys
from xml.sax.saxutils import quoteattr

SHARE = os.environ.get('SPARKY_HOUSEKEEPING_SHARE', '/usr/share/sparky-stereo-housekeeping')
ROOT = os.environ.get('SPARKY_HOUSEKEEPING_ROOT', '')
PACKAGE = 'sparky-stereo-housekeeping'
CLEANERS = '/usr/share/bleachbit/cleaners'
CLEANER = CLEANERS + '/system_mail.xml'
LOCALE = '/usr/share/locale'
LANGUAGES = ('de', 'es', 'fr', 'ja', 'ko', 'pl', 'pt_BR', 'zh_CN', 'zh_TW')
PRESENT = ('installed', 'unpacked', 'half-installed', 'half-configured', 'triggers-awaited', 'triggers-pending')

# (mail program, its packages, a file that shows the program is on the system, the queue folders)
# The queue folders hold messages only: Postfix's other folders under /var/spool/postfix are its chroot (libraries,
# resolv.conf), not mail; Exim's spool is all queue (input, msglog, db, scan); ssmtp sends at once and has no queue.
PROGRAMS = (
    ('exim4', ('exim4-base', 'exim4-daemon-light', 'exim4-daemon-heavy', 'exim4-daemon-custom'), '/usr/sbin/exim4',
     ('/var/spool/exim4',)),
    ('postfix', ('postfix',), '/usr/sbin/postfix',
     tuple('/var/spool/postfix/' + d for d in ('active', 'bounce', 'corrupt', 'defer', 'deferred', 'flush', 'hold',
                                                'incoming', 'maildrop', 'saved', 'trace'))),
    ('nullmailer', ('nullmailer',), '/usr/sbin/nullmailer-send',
     tuple('/var/spool/nullmailer/' + d for d in ('queue', 'failed', 'tmp'))),
    ('dma', ('dma',), '/usr/sbin/dma', ('/var/spool/dma',)),
    ('ssmtp', ('ssmtp',), '/usr/sbin/ssmtp', ()),
    ('msmtp', ('msmtp', 'msmtp-mta'), '/usr/bin/msmtp', ('~/.msmtp.queue',)),
)


class Failure(Exception):
    pass


def path(p):
    return ROOT + p


def package_state(name):
    """dpkg's status of one package; an unknown package is not-installed. Any other failure of dpkg-query stops."""
    r = subprocess.run(['dpkg-query', '--show', '--showformat=${db:Status-Status}\\n', name], capture_output=True,
                       text=True, env=dict(os.environ, LC_ALL='C'))
    if r.returncode == 0:
        return r.stdout.strip() or 'not-installed'
    if r.returncode == 1 and 'no packages found' in r.stderr:
        return 'not-installed'
    raise Failure('dpkg-query %s ended with exit status %d: %s' % (name, r.returncode, r.stderr.strip()))


def removed(program):
    name, packages, binary, queues = program
    if not queues:
        return False
    if any(package_state(p) in PRESENT for p in packages):
        return False
    return not os.path.lexists(path(binary))


def actions():
    lines = []
    for program in PROGRAMS:
        if not removed(program):
            continue
        lines.append('    <!-- %s: its packages are gone and the program is not on this system -->' % program[0])
        for queue in program[3]:
            lines.append('    <action command="delete" search="walk.files" path=%s/>' % quoteattr(queue))
    return lines


def cleaner():
    with open(os.path.join(SHARE, 'system_mail.xml.in'), encoding='utf-8') as f:
        text = f.read()
    return text.replace('<!-- QUEUES -->\n<!-- /QUEUES -->', '\n'.join(['<!-- QUEUES -->'] + actions() + ['<!-- /QUEUES -->']))


def write(target, data, mode=0o644):
    os.makedirs(os.path.dirname(target), exist_ok=True)
    tmp = target + '.tmp-' + PACKAGE
    with open(tmp, 'wb') as f:
        f.write(data)
    os.chmod(tmp, mode)
    os.replace(tmp, target)


def run(args, **kw):
    r = subprocess.run(args, capture_output=True, **kw)
    if r.returncode != 0:
        raise Failure('%s ended with exit status %d: %s' % (args[0], r.returncode,
                                                            r.stderr.decode('utf-8', 'replace').strip()))
    return r.stdout


def diverted(mo):
    r = subprocess.run(['dpkg-divert', '--listpackage', mo], capture_output=True, text=True)
    return r.returncode == 0 and r.stdout.strip() == PACKAGE


def divert(mo):
    if not diverted(mo):
        run(['dpkg-divert', '--package', PACKAGE, '--add', '--rename', '--divert', mo + '.debian', mo])


def undivert(mo):
    """Debian's catalog back under its own name; a file that is not this package's diversion is never touched."""
    if not diverted(mo):
        return
    if os.path.lexists(path(mo)):
        os.remove(path(mo))
    run(['dpkg-divert', '--package', PACKAGE, '--remove', '--rename', '--divert', mo + '.debian', mo])


def catalogs():
    """Debian's catalog of each language with this package's strings added; Debian's own wins where both have one."""
    for lang in LANGUAGES:
        mo = '%s/%s/LC_MESSAGES/bleachbit.mo' % (LOCALE, lang)
        po = os.path.join(SHARE, 'po', lang + '.po')
        divert(mo)
        if not os.path.exists(path(mo + '.debian')):
            if os.path.lexists(path(mo)):
                os.remove(path(mo))
            continue
        debian = run(['msgunfmt', path(mo + '.debian')])
        merged = subprocess.run(['msgcat', '--use-first', '-', po], input=debian, capture_output=True)
        if merged.returncode != 0:
            raise Failure('msgcat for %s ended with exit status %d: %s' % (lang, merged.returncode,
                                                                           merged.stderr.decode('utf-8', 'replace')))
        compiled = subprocess.run(['msgfmt', '-o', '-', '-'], input=merged.stdout, capture_output=True)
        if compiled.returncode != 0:
            raise Failure('msgfmt for %s ended with exit status %d: %s' % (lang, compiled.returncode,
                                                                           compiled.stderr.decode('utf-8', 'replace')))
        write(path(mo), compiled.stdout)


def refresh():
    if not os.path.isdir(path('/usr/share/bleachbit')):
        remove()
        print('%s: bleachbit is not installed, so there is no cleaner to write' % PACKAGE, file=sys.stderr)
        return 0
    write(path(CLEANER), cleaner().encode('utf-8'))
    catalogs()
    return 0


def remove():
    if os.path.lexists(path(CLEANER)):
        os.remove(path(CLEANER))
    for lang in LANGUAGES:
        undivert('%s/%s/LC_MESSAGES/bleachbit.mo' % (LOCALE, lang))
    return 0


def main(argv):
    if len(argv) != 1 or argv[0] not in ('refresh', 'remove', 'show'):
        print(__doc__, file=sys.stderr)
        return 2
    try:
        if argv[0] == 'show':
            print(cleaner(), end='')
            return 0
        return refresh() if argv[0] == 'refresh' else remove()
    except (Failure, OSError) as e:
        print('%s: %s' % (PACKAGE, e), file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
