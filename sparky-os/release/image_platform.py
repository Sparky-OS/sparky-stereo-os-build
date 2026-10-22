"""Reject a cached container image for the wrong CPU before qualification."""
import json
import subprocess


def require_amd64_image(reference):
    rows = json.loads(subprocess.check_output(
        ['docker', 'image', 'inspect', reference], text=True))
    if len(rows) != 1:
        raise ValueError('Expected exactly one resolved container image')
    image = rows[0]
    if (image['Os'], image['Architecture']) != ('linux', 'amd64'):
        raise ValueError('Expected linux/amd64, got ' + image['Os'] + '/' + image['Architecture'])
    return image['Id']
