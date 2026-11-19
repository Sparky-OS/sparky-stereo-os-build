#!/usr/bin/python3
# Copyright 2026 Daniel Ramos (Capitain Jack), GPL-3.0-or-later.
"""Immutable publisher terms in ordinary per-profile debconf templates."""
import hashlib


def render(profile, licences, messages):
    bodies=[]
    for item in profile['licences']:
        raw=(licences/item['file']).read_bytes()
        if hashlib.sha256(raw).hexdigest()!=item['sha256']:raise ValueError(item['file'])
        bodies.append(item['name']+'\n'+item['url']+'\n'+raw.decode('utf-8'))
    legal='\n\n'.join(bodies)
    if '${' in legal:raise ValueError('Literal template variable in publisher terms')
    def description(code):
        note=profile.get('licence_notes',{}).get(code,'')
        text=(note+'\n\n' if note else '')+legal
        if any(line=='.' for line in text.splitlines()):raise ValueError('Literal paragraph marker in publisher terms')
        return profile['title']+'\n'+''.join(' '+(line if line else '.')+'\n' for line in text.splitlines())
    text='Template: '+profile['package']+'/licence\nType: note\nDescription: '+description('en')
    for code in profile.get('licence_notes',{}):
        if code!='en':text+='Description-'+code+': '+description(code)
    text+='\nTemplate: '+profile['package']+'/consent\nType: boolean\nDefault: false\n'
    for code,words in messages.items():
        text+='Description'+('' if code=='en' else '-'+code)+': '+words['consent']+'\n '+profile['title']+'\n'
    return text
