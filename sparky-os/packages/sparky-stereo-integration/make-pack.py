#!/usr/bin/env python3
# Created by Paweł "pavroo" Pijanowski and Daniel Ramos (Capitain Jack) 2026/10/24
# Copyright 2026 under the GNU GPL3 License
# Last update 2026/10/24
# Writes the generated files of an integration pack from its pack.json:
#   <out>/usr/share/kio/servicemenus/<menu>.desktop       one ordinary Dolphin service menu per entry of "menus"
#   <out>/usr/share/sparky-stereo/integrations.d/<id>.conf   what sparky-stereo-integration reads
# Usage: make-pack.py PACK.JSON OUT-DIR
# pack.json:
#   id        the pack's short name (the conf file, the argument of "run")
#   program   the executable the actions need (TryExec; the offer when it is missing)
#   worker    the installed executable that does the work; it gets ARG... -- FILE...
#   menus[]   file (without .desktop), icon, mime[] , urls {required[], min, max}, submenu{lang: text},
#             actions[] {id, args[], icon, name{lang: text}}
# Every text exists in the nine required languages or the generator stops.
import json, os, sys

LANGS = ['en', 'pl', 'pt_BR', 'fr', 'de', 'ja', 'ko', 'zh_CN', 'zh_TW']

def texts(key, d, where):
    miss = [l for l in LANGS if not d.get(l)]
    if miss:
        sys.exit(f'{where}: {key} lacks {" ".join(miss)}')
    for l in LANGS:
        if any(c in d[l] for c in '\n;'):
            sys.exit(f'{where}: {key}[{l}] has a newline or a semicolon')
    return [f'{key}={d["en"]}'] + [f'{key}[{l}]={d[l]}' for l in LANGS[1:]]

def main():
    spec = json.load(open(sys.argv[1]))
    out = sys.argv[2]
    pid, program, worker = spec['id'], spec['program'], spec['worker']
    sm = os.path.join(out, 'usr/share/kio/servicemenus')
    cd = os.path.join(out, 'usr/share/sparky-stereo/integrations.d')
    os.makedirs(sm, exist_ok=True)
    os.makedirs(cd, exist_ok=True)
    files = []
    for m in spec['menus']:
        name = m['file'] + '.desktop'
        files.append(name)
        ln = ['[Desktop Entry]', 'Type=Service',
              'MimeType=' + ''.join(t + ';' for t in m['mime']),
              'Actions=' + ''.join(a['id'] + ';' for a in m['actions']),
              'Icon=' + m.get('icon', 'applications-graphics')]
        u = m.get('urls', {})
        if u.get('required'):
            ln.append('X-KDE-RequiredNumberOfUrls=' + ','.join(str(n) for n in u['required']))
        if 'min' in u:
            ln.append(f'X-KDE-MinNumberOfUrls={u["min"]}')
        if 'max' in u:
            ln.append(f'X-KDE-MaxNumberOfUrls={u["max"]}')
        if m.get('submenu'):
            ln += texts('X-KDE-Submenu', m['submenu'], f'{pid}/{name}')
        for a in m['actions']:
            args = ' '.join(a.get('args', []))
            ln += ['', f'[Desktop Action {a["id"]}]'] + texts('Name', a['name'], f'{pid}/{a["id"]}')
            ln += ['Icon=' + a.get('icon', m.get('icon', 'applications-graphics')),
                   f'Exec=sparky-stereo-integration run {pid}{" " + args if args else ""} -- %F']
        open(os.path.join(sm, name), 'w').write('\n'.join(ln) + '\n')
    open(os.path.join(cd, pid + '.conf'), 'w').write(
        f'program={program}\nworker={worker}\nmenus={" ".join(files)}\n')

main()
