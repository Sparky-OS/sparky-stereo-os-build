# SPDX-License-Identifier: MIT
"""The build record written beside the .deb files (ORDER 394b): green with every host fact, red without one."""
from pathlib import Path
import hashlib
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
    # source=None writes no Source field, like a recipe that assembles DEBIAN/control by hand
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
            # the build script ran sparky_provenance_init (it always passes the invocation id and the clock) but git and
            # docker could not be read: those two facts are listed, never guessed
            env = {k: HOST[k] for k in ('SPARKY_BUILD_INVOCATION', 'SPARKY_BUILD_STARTED')}
            (path,) = buildrecord.record([make_deb(d)], environ=env)
            obj = json.loads(path.read_text())
            for key in ('recipeCommit', 'builderImage'):
                self.assertNotIn(key, obj)
            self.assertEqual(sorted(obj['unrecorded']), ['builderImage', 'buildinfo', 'recipeCommit'])

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


def checksum_file(path, debs, source, version='1.0-1+lc1', arch='amd64'):
    """A .buildinfo or .changes listing debs the way dpkg-genbuildinfo and dpkg-genchanges write them."""
    rows = ''.join(f' {hashlib.sha256(d.read_bytes()).hexdigest()} {d.stat().st_size} {d.name}\n' for d in debs)
    Path(path).write_text(f'Format: 1.0\nSource: {source}\nBinary: x\nArchitecture: {arch}\nVersion: {version}\n'
                          f'Checksums-Sha256:\n{rows}Build-Origin: Debian\n')


class OneSourceSeveralBinaries(TestCase):
    """ORDER 439: dpkg names the .buildinfo after the SOURCE; one source build is one record, however many binaries."""

    def two_binaries(self, d, engine_source=None):
        data = make_deb(d, 'demo', arch='all')                                   # package == source: no Source field needed
        engine = make_deb(d, 'demo-engine', arch='amd64', source=engine_source)  # a different name
        for name in ('demo_1.0-1+lc1_amd64.buildinfo', 'demo_1.0-1+lc1_amd64.changes', 'demo_1.0-1+lc1.dsc'):
            (Path(d) / name).write_text('Format: 1.0\n')
        return data, engine

    def test_binary_with_a_source_field_joins_its_source(self):
        with TemporaryDirectory() as d:
            data, engine = self.two_binaries(d, engine_source='demo')
            paths = buildrecord.record([data, engine], environ=HOST)
            self.assertEqual([p.name.split('_')[0] for p in paths], ['demo'])
            obj = json.loads(paths[0].read_text())
            self.assertEqual(sorted(r['name'] for r in obj['debs']), sorted([data.name, engine.name]))
            self.assertEqual([r['name'] for r in obj['files']],
                             ['demo_1.0-1+lc1_amd64.buildinfo', 'demo_1.0-1+lc1_amd64.changes', 'demo_1.0-1+lc1.dsc'])
            self.assertEqual(obj['unrecorded'], [])

    def test_binary_without_a_source_field_is_placed_by_the_buildinfo_that_lists_it(self):
        with TemporaryDirectory() as d:
            data, engine = self.two_binaries(d)
            checksum_file(Path(d) / 'demo_1.0-1+lc1_amd64.buildinfo', [data, engine], 'demo')
            paths = buildrecord.record([data, engine], environ=HOST)
            self.assertEqual([p.name.split('_')[0] for p in paths], ['demo'])
            obj = json.loads(paths[0].read_text())
            self.assertEqual(sorted(r['name'] for r in obj['debs']), sorted([data.name, engine.name]))
            self.assertIn('demo_1.0-1+lc1_amd64.buildinfo', [r['name'] for r in obj['files']])
            self.assertNotIn('buildinfo', obj['unrecorded'])

    def test_binary_without_a_source_field_is_placed_by_the_changes_when_no_buildinfo_lists_it(self):
        with TemporaryDirectory() as d:
            data, engine = self.two_binaries(d)
            checksum_file(Path(d) / 'demo_1.0-1+lc1_amd64.changes', [data, engine], 'demo')
            (path,) = buildrecord.record([data, engine], environ=HOST)
            self.assertEqual(path.name.split('_')[0], 'demo')

    def test_the_source_field_wins_over_a_buildinfo_that_lists_the_deb_under_another_source(self):
        with TemporaryDirectory() as d:
            data, engine = self.two_binaries(d, engine_source='demo')
            checksum_file(Path(d) / 'other_9_amd64.buildinfo', [engine], 'other', version='9')
            self.assertEqual([p.name.split('_')[0] for p in buildrecord.record([data, engine], environ=HOST)], ['demo'])

    def test_a_missing_buildinfo_stays_unrecorded_and_the_binary_keeps_its_own_name(self):
        with TemporaryDirectory() as d:
            engine = make_deb(d, 'demo-engine', arch='amd64')      # no Source field and no build file lists it
            (path,) = buildrecord.record([engine], environ=HOST)
            obj = json.loads(path.read_text())
            self.assertEqual(obj['source'], 'demo-engine')
            self.assertIn('buildinfo', obj['unrecorded'])
            self.assertEqual(obj['files'], [])

    def test_a_missing_buildinfo_of_a_two_binary_source_is_still_listed(self):
        with TemporaryDirectory() as d:
            data = make_deb(d, 'demo', arch='all')
            engine = make_deb(d, 'demo-engine', arch='amd64', source='demo')
            (path,) = buildrecord.record([data, engine], environ=HOST)
            self.assertIn('buildinfo', json.loads(path.read_text())['unrecorded'])

    def test_binnmu_binaries_use_the_source_version_and_the_buildinfo_named_by_the_binary_version(self):
        with TemporaryDirectory() as d:
            deb = make_deb(d, 'demo-lib', version='1.0-1+b1', arch='amd64', source='demo (1.0-1)')
            for name in ('demo_1.0-1+b1_amd64.buildinfo', 'demo_1.0-1+b1_amd64.changes', 'demo_1.0-1.dsc',
                         'demo_1.0-10_amd64.buildinfo'):          # the last one is another version: never taken
                (Path(d) / name).write_text('Format: 1.0\n')
            (path,) = buildrecord.record([deb], environ=HOST)
            obj = json.loads(path.read_text())
            self.assertEqual((obj['source'], obj['version']), ('demo', '1.0-1'))
            self.assertEqual([r['name'] for r in obj['files']],
                             ['demo_1.0-1+b1_amd64.buildinfo', 'demo_1.0-1+b1_amd64.changes', 'demo_1.0-1.dsc'])
            self.assertEqual(path.name, 'demo_1.0-1_' + obj['buildArchitecture'] + '.sparky-build.json')

    def test_a_single_binary_source_is_unchanged(self):
        with TemporaryDirectory() as d:
            deb = make_deb(d, 'solo', version='2.0', arch='amd64')
            (Path(d) / 'solo_2.0_amd64.buildinfo').write_text('Format: 1.0\n')
            (Path(d) / 'solo_2.0_amd64.changes').write_text('Format: 1.8\n')
            (path,) = buildrecord.record([deb], environ=HOST, now=__import__('datetime').datetime(2026, 11, 6, tzinfo=__import__('datetime').timezone.utc))
            obj = json.loads(path.read_text())
            self.assertEqual(path.name, 'solo_2.0_' + obj['buildArchitecture'] + '.sparky-build.json')
            self.assertEqual([r['name'] for r in obj['files']], ['solo_2.0_amd64.buildinfo', 'solo_2.0_amd64.changes'])
            self.assertEqual(obj['unrecorded'], [])
