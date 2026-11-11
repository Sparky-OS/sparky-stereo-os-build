# SPDX-License-Identifier: MIT
"""A build script that never called sparky_provenance_init is a stated failure, never a silent "NOT complete" (ORDER 412)."""
from contextlib import redirect_stderr
from pathlib import Path
import io
import json
import sys
from tempfile import TemporaryDirectory
from unittest import TestCase, mock

from lean import buildrecord, release
from lean.tests.test_buildrecord import HOST, make_deb

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'release'))
import supply_chain
import provenance_args

FACTS = ('recipeCommit', 'builderImage', 'invocationId', 'startedOn')


class NeverCalled(TestCase):
    def test_no_host_fact_at_all_stops_and_names_the_call(self):
        with TemporaryDirectory() as d:
            deb = make_deb(d)
            with self.assertRaises(buildrecord.Incomplete) as ctx:
                buildrecord.record([deb], environ={})
            message = str(ctx.exception)
            for part in ('sparky_provenance_init', 'build-provenance.sh', 'SPARKY_PROV_ARGS', 'SPARKY_PROVENANCE_OPTOUT'):
                self.assertIn(part, message)
            self.assertEqual(list(Path(d).glob('*.sparky-build.json')), [])      # no record is written

    def test_the_gate_exits_1_with_the_message(self):
        with TemporaryDirectory() as d:
            deb = make_deb(d)
            err = io.StringIO()
            with mock.patch.object(release, 'check_debs'), mock.patch.dict('os.environ', clear=True), \
                    mock.patch.object(sys, 'argv', ['release', 'check-debs', str(deb)]), \
                    redirect_stderr(err), self.assertRaises(SystemExit) as ctx:
                release.main()
            self.assertEqual(ctx.exception.code, 1)
            self.assertIn('release blocked', err.getvalue())
            self.assertIn('sparky_provenance_init', err.getvalue())
            self.assertEqual(list(Path(d).glob('*.sparky-build.json')), [])

    def test_the_init_call_makes_it_complete(self):
        with TemporaryDirectory() as d:
            (Path(d) / 'demo_1.0-1+lc1_amd64.buildinfo').write_text('Format: 1.0\n')
            (path,) = buildrecord.record([make_deb(d)], environ=HOST)
            obj = json.loads(path.read_text())
            self.assertEqual(obj['unrecorded'], [])
            self.assertNotIn('provenanceOptOut', obj)

    def test_the_source_date_and_its_basis_are_in_the_record(self):
        # ORDER 421b: the record says which recipe date the source used, so a reader can make the source again
        with TemporaryDirectory() as d:
            (Path(d) / 'demo_1.0-1+lc1_amd64.buildinfo').write_text('Format: 1.0\n')
            environ = dict(HOST, SOURCE_DATE_EPOCH='1793974631', SPARKY_SOURCE_DATE_BASIS='the last commit touching packages/demo')
            (path,) = buildrecord.record([make_deb(d)], environ=environ)
            obj = json.loads(path.read_text())
            self.assertEqual(obj['sourceDateEpoch'], 1793974631)
            self.assertEqual(obj['sourceDateBasis'], 'the last commit touching packages/demo')
            self.assertEqual(supply_chain.read_build_record(path)['sourceDateEpoch'], 1793974631)
        with TemporaryDirectory() as d:
            (path,) = buildrecord.record([make_deb(d)], environ=dict(HOST))
            self.assertNotIn('sourceDateEpoch', json.loads(path.read_text()))

    def test_one_fact_alone_is_the_init_path_not_the_missing_call(self):
        with TemporaryDirectory() as d:
            (path,) = buildrecord.record([make_deb(d)], environ={'SPARKY_BUILD_STARTED': HOST['SPARKY_BUILD_STARTED']})
            self.assertIn('recipeCommit', json.loads(path.read_text())['unrecorded'])


class OptOut(TestCase):
    def test_the_reason_is_in_the_record_and_the_gaps_stay_listed(self):
        with TemporaryDirectory() as d:
            (path,) = buildrecord.record([make_deb(d)], environ={'SPARKY_PROVENANCE_OPTOUT': 'built inside a VM, no docker image'})
            obj = json.loads(path.read_text())
            self.assertEqual(obj['provenanceOptOut'], 'built inside a VM, no docker image')
            for fact in FACTS:
                self.assertIn(fact, obj['unrecorded'])
            self.assertEqual(supply_chain.read_build_record(path)['provenanceOptOut'], obj['provenanceOptOut'])

    def test_an_empty_reason_stops(self):
        with TemporaryDirectory() as d:
            deb = make_deb(d)
            for reason in ('', '   '):
                with self.assertRaisesRegex(buildrecord.Incomplete, 'empty'):
                    buildrecord.record([deb], environ={'SPARKY_PROVENANCE_OPTOUT': reason})

    def test_opt_out_beside_the_init_call_stops(self):
        with TemporaryDirectory() as d:
            with self.assertRaisesRegex(buildrecord.Incomplete, 'also called'):
                buildrecord.record([make_deb(d)], environ=dict(HOST, SPARKY_PROVENANCE_OPTOUT='x'))

    def test_required_still_stops_an_opt_out(self):
        with TemporaryDirectory() as d:
            with self.assertRaisesRegex(buildrecord.Incomplete, 'provenance required'):
                buildrecord.record([make_deb(d)], environ={'SPARKY_PROVENANCE_OPTOUT': 'x', 'SPARKY_PROVENANCE_REQUIRED': '1'})


class PythonDrivers(TestCase):
    """release/provenance_args.py hands the shell function's arguments to the Python build drivers."""
    def run_helper(self, body):
        with TemporaryDirectory() as d:
            stub = Path(d) / 'stub.sh'
            stub.write_text(body)
            with mock.patch.object(provenance_args, 'SCRIPT', stub):
                return provenance_args.provenance_args('img:1')

    def test_arguments_come_back_as_docker_run_words(self):
        words = self.run_helper('sparky_provenance_init() { SPARKY_PROV_ARGS=(-e "A=1 2" -e B=3 "$1"); }\n')
        self.assertEqual(words, ['-e', 'A=1 2', '-e', 'B=3', 'img:1'])

    def test_a_stopped_init_stops_the_driver(self):
        with self.assertRaisesRegex(SystemExit, 'stopped'):
            self.run_helper('sparky_provenance_init() { return 1; }\n')
