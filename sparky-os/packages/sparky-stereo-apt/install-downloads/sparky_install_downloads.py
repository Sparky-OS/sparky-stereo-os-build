# Created by Daniel Ramos (Capitain Jack) 2026/11/04
# Copyright 2026 under the GNU GPL3 License
"""Install-time downloads: what a package declares, whether the connection is metered, and the words every front end shows.

A package that downloads data while it is installed (its postinst fetches it) says so in its control file, which reaches
the Packages index, so apt-cache show and every front end can read it before anything is fetched:

    Install-Download-Size: 1883333376
    Install-Download-Source: https://sourceforge.net/projects/flightgear/files/release-2024.1/FlightGear-2024.1.5-data.txz/download

Size is the number of bytes, Source the address (https). There is no name for this in Debian's control fields, apt or
AppStream; the words are apt's own "Download size" and AppStream's <size type="download"> (bytes), after Debian's
"Installed-Size", with "Install-" in front because the download happens when the package is installed. A source package
carries them as XB-Install-Download-Size and XB-Install-Download-Source.

Two front ends read it through this module: apt, in a terminal (the JSON hook of install-downloads), and Stereo APTus.
"""
import json
import os
import re
import subprocess

FIELD_SIZE = 'Install-Download-Size'
FIELD_SOURCE = 'Install-Download-Source'
OPTION = 'Sparky::Install-Downloads::Announce'
MODES = ('metered', 'always', 'never')
LANGDIR = os.environ.get('SPARKY_INSTALL_DOWNLOADS_LANG', '/usr/share/sparky/sparky-stereo-apt/install-downloads')
# NetworkManager's NMMetered (org.freedesktop.NetworkManager, property Metered)
NM_METERED = {0: 'unknown', 1: 'yes', 2: 'no', 3: 'guess-yes', 4: 'guess-no'}


def declaration(section):
    """The declared download of a package record (anything with .get), or None; ValueError says what is wrong with it."""
    size = section.get(FIELD_SIZE)
    source = section.get(FIELD_SOURCE)
    if size is None and source is None:
        return None
    if size is None or source is None:
        raise ValueError('both %s and %s are needed' % (FIELD_SIZE, FIELD_SOURCE))
    size = size.strip()
    source = source.strip()
    if not re.fullmatch(r'[0-9]+', size) or int(size) <= 0:
        raise ValueError('%s is "%s", not a number of bytes' % (FIELD_SIZE, size))
    if not re.fullmatch(r'https://[^\s]+', source):
        raise ValueError('%s is "%s", not an https address' % (FIELD_SOURCE, source))
    return {'size': int(size), 'source': source}


def human(count):
    if count >= 1 << 30:
        return '%.2f GiB' % (count / (1 << 30))
    if count >= 1 << 20:
        return '%.1f MiB' % (count / (1 << 20))
    return '%.1f KiB' % (count / 1024)


def announce_mode(value):
    """The setting Sparky::Install-Downloads::Announce; (mode, problem or None)."""
    value = (value or 'metered').strip()
    if value in MODES:
        return value, None
    return 'metered', '%s is "%s"; it must be one of %s' % (OPTION, value, ', '.join(MODES))


def metered():
    """NetworkManager's answer: (state, detail). state is yes, no or unknown; the detail says what was read."""
    cmd = ['busctl', '--system', 'get-property', 'org.freedesktop.NetworkManager', '/org/freedesktop/NetworkManager',
           'org.freedesktop.NetworkManager', 'Metered']
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
    except FileNotFoundError:
        return 'unknown', 'busctl is not installed'
    except subprocess.TimeoutExpired:
        return 'unknown', 'NetworkManager did not answer within 5 seconds'
    if out.returncode:
        why = (out.stderr.strip().splitlines() or ['busctl failed'])[0]
        return 'unknown', 'NetworkManager did not answer: ' + why
    m = re.fullmatch(r'u (\d+)', out.stdout.strip())
    if not m or int(m.group(1)) not in NM_METERED:
        return 'unknown', 'NetworkManager answered "%s"' % out.stdout.strip()
    word = NM_METERED[int(m.group(1))]
    if word in ('yes', 'guess-yes'):
        return 'yes', word
    if word in ('no', 'guess-no'):
        return 'no', word
    return 'unknown', 'NetworkManager does not know (unknown)'


def language():
    for name in ('LC_ALL', 'LC_MESSAGES', 'LANG'):
        value = os.environ.get(name)
        if value:
            break
    else:
        value = 'C'
    value = value.split('.')[0].split('@')[0]
    if value.startswith('pt'):
        value = 'pt_BR'
    elif value in ('zh_TW', 'zh_HK', 'zh_MO'):
        value = 'zh_TW'
    elif value.startswith('zh'):
        value = 'zh_CN'
    for candidate in (value, value.split('_')[0], 'en'):
        if re.fullmatch(r'[A-Za-z]{2,3}(_[A-Za-z]+)?', candidate) and os.path.isfile(os.path.join(LANGDIR, candidate + '.json')):
            return candidate
    return 'en'


def messages():
    with open(os.path.join(LANGDIR, 'en.json'), encoding='utf-8') as stream:
        text = json.load(stream)
    code = language()
    if code != 'en':
        with open(os.path.join(LANGDIR, code + '.json'), encoding='utf-8') as stream:
            text.update(json.load(stream))
    return text


def assess(downloads, mode='metered', question='asked', state=None):
    """What a front end shows. downloads: [{package, version, size, source}]. Returns a dict:
    announce (bool), state (yes, no, unknown), detail, downloads (with size_text) and text (the lines, in the person's language).
    question: asked (apt will ask "Do you want to continue?"), not-asked (only the named packages are installed, apt asks nothing)
    or unattended (-y)."""
    result = {'announce': False, 'state': 'no', 'detail': '', 'mode': mode, 'downloads': [], 'text': []}
    if not downloads or mode == 'never':
        return result
    if state is None:
        state = metered() if mode == 'metered' else ('no', 'not asked')
    result['state'], result['detail'] = state
    if mode == 'metered' and state[0] == 'no':
        return result
    msg = messages()
    result['announce'] = True
    result['downloads'] = [dict(d, size_text=human(d['size'])) for d in downloads]
    lines = []
    if state[0] == 'yes':
        lines.append(msg['metered'].format(detail=state[1]))
    elif state[0] == 'unknown':
        lines.append(msg['unknown'].format(why=state[1]))
    lines.append(msg['intro'])
    for d in result['downloads']:
        lines.append(msg['line'].format(package=d['package'], size=d['size_text'], source=d['source']))
    lines.append({'asked': msg['ask'], 'not-asked': msg['noquestion'], 'unattended': msg['unattended']}[question])
    result['text'] = lines
    return result
