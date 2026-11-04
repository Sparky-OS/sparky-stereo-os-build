# SPDX-License-Identifier: MIT
"""The build record written beside the .deb files (ORDER 394b): green with every host fact, red without one."""
from pathlib import Path
import json
import subprocess
from tempfile import TemporaryDirectory
from unittest import TestCase

from lean import buildrecord

HOST = {
    'SPARKY_BUILD_COMMIT': 'a' * 40,
    'SPARKY_BUILD_DIRTY': '0',
    'SPARKY_BUILD_REPOSITORY': 'https://github.com/Sparky-OS/sparky-stereo-os-build',
    'SPARKY_BUILD_IMAGE_NAME': 'builder:1',
    'SPARKY_BUILD_IMAGE_ID': 'sha256:' + 'b' * 64,
    'SPARKY_BUILD_INVOCATION': '0b0e86c3-6c0a-4d6a-9d57-0f5f0a1d7f10',
    'SPARKY_BUILD_STARTED': '2026-11-04T08:00:00Z',
}


def make_deb(folder, name='demo', version='1.0-1+lc1', arch='all', source=None):
    tree = Path(folder) / f'{name}-tree'
    (tree / 'DEBIAN').mkdir(parents=True)
    lines = [f'Package: {name}', f'Version: {version}', f'Architecture: {arch}', 'Maintainer: x', 'Description: d']
    if source:
        lines.insert(1, f'Source: {source}')
    (tree / 'DEBIAN/control').write_text('\n'.join(lines) + '\n')
    deb = Path(folder) / f'{name}_{version}_{arch}.deb'
    subprocess.run(['dpkg-deb', '--root-owner-group', '-Zxz', '-b', str(tree), str(deb)], check=True,
                   stdout=subprocess.DEVNULL)
    return deb


class Record(TestCase):
    def test_every_host_fact_recorded(self):
        with TemporaryDirectory() as d:
            deb = make_deb(d, 'demo-data', source='demo (1.0-1+lc1)')
            (Path(d) / 'demo_1.0-1+lc1_amd64.buildinfo').write_text('Format: 1.0\n')
            (path,) = buildrecord.record([deb], environ=HOST)
            obj = json.loads(path.read_text())
            self.assertEqual(path.name, 'demo_1.0-1+lc1_' + obj['buildArchitecture'] + '.sparky-build.json')
            self.assertEqual((obj['source'], obj['version']), ('demo', '1.0-1+lc1'))
            self.assertEqual(obj['recipeCommit'], 'a' * 40)
            self.assertIs(obj['recipeDirty'], False)
            self.assertEqual(obj['builderImage'], 'sha256:' + 'b' * 64)
            self.assertEqual(obj['invocationId'], HOST['SPARKY_BUILD_INVOCATION'])
            self.assertEqual((obj['startedOn'], obj['startBasis']), ('2026-11-04T08:00:00Z', 'build-script'))
            self.assertRegex(obj['finishedOn'], buildrecord.STAMP)
            self.assertEqual(obj['unrecorded'], [])
            self.assertEqual([row['name'] for row in obj['debs']], [deb.name])
            self.assertEqual([row['name'] for row in obj['files']], ['demo_1.0-1+lc1_amd64.buildinfo'])

    def test_missing_host_facts_are_listed_not_guessed(self):
        with TemporaryDirectory() as d:
            (path,) = buildrecord.record([make_deb(d)], environ={})
            obj = json.loads(path.read_text())
            for key in ('recipeCommit', 'builderImage', 'invocationId', 'startedOn'):
                self.assertNotIn(key, obj)
            self.assertEqual(sorted(obj['unrecorded']), ['builderImage', 'buildinfo', 'invocationId', 'recipeCommit', 'startedOn'])

    def test_required_stops_the_build(self):
        with TemporaryDirectory() as d:
            deb = make_deb(d)
            env = dict(HOST, SPARKY_PROVENANCE_REQUIRED='1')
            del env['SPARKY_BUILD_COMMIT']
            with self.assertRaisesRegex(buildrecord.Incomplete, 'SPARKY_BUILD_COMMIT'):
                buildrecord.record([deb], environ=env)
            self.assertEqual(list(Path(d).glob('*.sparky-build.json')), [])

    def test_malformed_fact_is_an_error(self):
        with TemporaryDirectory() as d:
            deb = make_deb(d)
            for var, value in (('SPARKY_BUILD_COMMIT', 'main'), ('SPARKY_BUILD_IMAGE_ID', 'sparky-lc:1'),
                               ('SPARKY_BUILD_STARTED', 'yesterday'), ('SPARKY_BUILD_INVOCATION', '42')):
                with self.assertRaises(buildrecord.Incomplete, msg=var):
                    buildrecord.record([deb], environ=dict(HOST, **{var: value}))

    def test_start_noted_by_the_build_fills_a_missing_script_start(self):
        with TemporaryDirectory() as d:
            (Path(d) / buildrecord.START).write_text(json.dumps({'dpkgBuildpackageStartedOn': '2026-11-04T07:59:00Z'}))
            env = {k: v for k, v in HOST.items() if k != 'SPARKY_BUILD_STARTED'}
            (path,) = buildrecord.record([make_deb(d)], environ=env)
            obj = json.loads(path.read_text())
            self.assertEqual((obj['startedOn'], obj['startBasis']), ('2026-11-04T07:59:00Z', 'dpkg-buildpackage'))
            self.assertNotIn('startedOn', obj['unrecorded'])
            self.assertFalse((Path(d) / buildrecord.START).exists())

    def test_two_sources_in_one_folder_get_two_records(self):
        with TemporaryDirectory() as d:
            paths = buildrecord.record([make_deb(d, 'one'), make_deb(d, 'two')], environ=HOST)
            self.assertEqual(sorted(p.name.split('_')[0] for p in paths), ['one', 'two'])

    def test_note_start_replaces_an_earlier_builds_start(self):
        with TemporaryDirectory() as d:
            (Path(d) / buildrecord.START).write_text(json.dumps({'dpkgBuildpackageStartedOn': '2026-01-01T00:00:00Z'}))
            buildrecord.note_start(d)
            self.assertIsNone(json.loads((Path(d) / buildrecord.START).read_text())['dpkgBuildpackageStartedOn'])   # no dpkg-buildpackage here

    def test_dpkg_buildpackage_start_is_read_from_proc(self):
        self.assertRegex(buildrecord.stamp(), buildrecord.STAMP)
        self.assertIsNone(buildrecord.dpkg_buildpackage_started())      # this test runs under no dpkg-buildpackage
