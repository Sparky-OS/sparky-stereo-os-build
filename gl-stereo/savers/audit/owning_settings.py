#!/usr/bin/python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""A saver whose settings an owning patch extends (owning-settings.json): the installed file has
exactly the recorded hash, the listed settings are added with exactly the recorded attributes,
and with them taken out the file equals the original setting for setting.

usage: owning_settings.py <original.xml> <installed.xml> <name>   (check, then the self-test)"""
import copy
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

OWNING = json.loads(Path(__file__).with_name('owning-settings.json').read_text())

def canonical(root):
    return ET.canonicalize(ET.tostring(root, encoding='unicode'), strip_text=True)

def without_additions(root, added):
    root = copy.deepcopy(root); wanted = {a['id']: a for a in added}; found = []
    for parent in list(root.iter()):
        for child in list(parent):
            if child.tag == 'boolean' and child.get('id') in wanted:
                assert dict(child.attrib) == wanted[child.get('id')], ('added setting differs', child.attrib)
                found.append(child.get('id')); parent.remove(child)
    assert sorted(found) == sorted(wanted), ('added settings', found)
    for parent in list(root.iter()):
        for child in list(parent):
            if child.tag in ('hgroup', 'vgroup') and len(child) == 0: parent.remove(child)
    return root

def check(name, original_xml, installed_xml):
    """The installed settings of an owning saver: its hash, its additions, everything else."""
    import hashlib
    entry = OWNING[name]
    assert hashlib.sha256(Path(original_xml).read_bytes()).hexdigest() == entry['original_sha256'], (name, 'original settings')
    assert hashlib.sha256(Path(installed_xml).read_bytes()).hexdigest() == entry['settings_sha256'], (name, 'installed settings')
    original, installed = ET.parse(original_xml).getroot(), ET.parse(installed_xml).getroot()
    assert canonical(without_additions(installed, entry['added'])) == canonical(original), (name, 'settings changed beyond the listed additions')

def self_test(name, original_xml, installed_xml):
    """Every stray change must fail: an original setting changed, removed or reordered, an
    unlisted setting added, a listed one changed or missing."""
    original, installed = ET.parse(original_xml).getroot(), ET.parse(installed_xml).getroot()
    added = OWNING[name]['added']
    assert canonical(without_additions(installed, added)) == canonical(original)
    def changed(mutate):
        root = copy.deepcopy(installed); mutate(root)
        try: return canonical(without_additions(root, added)) != canonical(original)
        except AssertionError: return True
    first = lambda root, tag: next(e for e in root.iter(tag))
    mutations = {
        'original default changed': lambda r: first(r, 'number').set('default', '1'),
        'original label changed': lambda r: first(r, 'boolean').set('_label', 'Titles'),
        'original setting removed': lambda r: next(p for p in r.iter() if first(r, 'number') in list(p)).remove(first(r, 'number')),
        'description changed': lambda r: setattr(first(r, '_description'), 'text', 'A snake.'),
        'unlisted setting added': lambda r: first(r, 'hgroup').append(ET.Element('boolean', {'id': 'extra', '_label': 'Extra', 'arg-set': '--extra'})),
        'listed setting changed': lambda r: next(e for e in r.iter('boolean') if e.get('id') == added[0]['id']).set('arg-unset', '--no-light'),
        'listed setting missing': lambda r: next(p for p in r.iter() if any(c.get('id') == added[-1]['id'] for c in p)).remove(next(e for e in r.iter('boolean') if e.get('id') == added[-1]['id'])),
    }
    for label, mutate in mutations.items():
        assert changed(mutate), ('stray change accepted', label)
    return list(mutations)

if __name__ == '__main__':
    original_xml, installed_xml, name = sys.argv[1:4]
    check(name, original_xml, installed_xml)
    print('PASS:', name, 'settings: original unchanged, exactly', len(OWNING[name]['added']), 'added; rejected:', ', '.join(self_test(name, original_xml, installed_xml)))
