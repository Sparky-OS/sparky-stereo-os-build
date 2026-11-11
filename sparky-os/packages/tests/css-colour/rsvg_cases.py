"""Writes rsvg_render's case list from cases.json: "id width height x,y;x,y" and "P id width height"."""
import json
import sys

d = json.load(open(sys.argv[1]))
for c in d['cases']:
    print('%s %d %d %s' % (c['id'], d['width'], d['height'], ';'.join('%d,%d' % tuple(p) for p in c['points'])))
for p in d['precision']:
    print('P %s %d %d' % (p['id'], p['width'], p['height']))
