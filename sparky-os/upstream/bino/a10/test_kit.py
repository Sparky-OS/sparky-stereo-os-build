#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
import copy
import csv
import json
from pathlib import Path
import tempfile
import unittest
from session import check_dimming, mode_ids, restore_args, setup_args, verify_setup, verify_restore
from kwinframes import measure
from summarize import summarize
from bench import keep_rows, telemetry


def fixture():
    result = []
    for name, ident, stereo, w, h, rate in [('eDP-1','72',5,1366,768,60.005), ('HDMI-A-1','13',3,1920,1080,30)]:
        result.append(dict(name=name, id=len(result)+1, connected=True, enabled=True,
                           currentModeId=ident, scale=1, rotation=1, replicationSource=0,
                           pos=dict(x=0 if name=='eDP-1' else 1366, y=0),
                           modes=[dict(id=ident, stereo3D=stereo, viewSize=dict(width=w,height=h), refreshRate=rate)]))
    return dict(outputs=result)


class KitTests(unittest.TestCase):
    def test_dimming_all_outputs(self):
        check_dimming('eDP dimming to 100% HDMI dimming to 100%')
        for text in ('eDP disabled dimming to 30% HDMI dimming to 100%',
                     'eDP dimming to 100% HDMI dimming to 99%', 'eDP dimming to 100% HDMI dimming to \x1b[31m30%\x1b[0m', 'eDP dimming to 100% HDMI dimming to unknown', 'no dimming diagnostics'):
            with self.assertRaises(RuntimeError): check_dimming(text)

    def test_three_setup_contract(self):
        snapshot=fixture(); ids=mode_ids(snapshot)
        self.assertEqual(ids, {'eDP-1':'72','HDMI-A-1':'13'})
        verify_setup(snapshot,ids,True)
        self.assertIn('output.eDP-1.disable',setup_args(ids,False))
        self.assertIn('output.HDMI-A-1.enable',setup_args(ids,True))
        self.assertIn('output.eDP-1.enable',setup_args(ids,True))
        wrong=copy.deepcopy(snapshot);wrong['outputs'][1]['enabled']=False
        with self.assertRaises(RuntimeError): verify_setup(wrong,ids,True)
        wrong=copy.deepcopy(snapshot);wrong['outputs'][1]['modes'][0]['stereo3D']=0
        with self.assertRaises(RuntimeError): mode_ids(wrong)

    def test_restore_preserves_disabled_and_mirror(self):
        snapshot=fixture();snapshot['outputs'][0]['enabled']=False
        snapshot['outputs'][1]['replicationSource']=1
        args=restore_args(snapshot)
        self.assertIn('output.eDP-1.disable',args)
        self.assertIn('output.HDMI-A-1.mirror.eDP-1',args)
        verify_restore(snapshot,copy.deepcopy(snapshot))
        wrong=copy.deepcopy(snapshot);wrong['outputs'][1]['scale']=2
        with self.assertRaises(RuntimeError):verify_restore(snapshot,wrong)

    def test_exact_case_boundaries_and_summary(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);(root/'kwin').mkdir()
            markrows=[];raw={'eDP-1':[],'HDMI-A-1':[]}
            index=0
            for setup,out in [('tv-3d','HDMI-A-1'),('extended-hdmi','HDMI-A-1'),('extended-edp','eDP-1')]:
                for variant in ('published','candidate'):
                    start=100+index*100;end=start+10;index+=1
                    name=f'{setup}/{out}/{variant}/3d';markrows += [(name,start),(name+'-end',end)]
                    n=100 if variant=='published' else 240
                    raw[out] += [[0,int((start+i*10/n)*1e9),0,0,0,0,0,0,0] for i in range(n)]
                    raw[out].append([0,int(end*1e9),0,0,0,0,0,0,0])
            with (root/'marks.csv').open('w') as f:csv.writer(f).writerows(markrows)
            for out,rows in raw.items():
                with (root/'kwin'/f'kwin perf statistics {out}.csv').open('w') as f:
                    writer=csv.writer(f);writer.writerow(['target pageflip timestamp','pageflip timestamp']+['x']*7);writer.writerows(rows)
            counts=measure(root/'kwin',root/'marks.csv')
            self.assertEqual([c['frames'] for c in counts],[100,240]*3)
            (root/'run.json').write_text(json.dumps(dict(status='complete',source_rate='24/1')))
            summarize(root)
            with (root/'comparison.csv').open() as f:summary=list(csv.DictReader(f))
            self.assertEqual(len(summary),3)
            self.assertEqual(float(summary[0]['published_drops_per_minute']),840)
            self.assertEqual(float(summary[0]['candidate_drops_per_minute']),0)
            (root/'run.json').write_text(json.dumps(dict(status='confounded',source_rate='24/1')))
            with self.assertRaises(ValueError): summarize(root)
            (root/'marks.csv').write_text('unfinished/HDMI-A-1/published/3d,1\n')
            with self.assertRaises(ValueError):measure(root/'kwin',root/'marks.csv')

    def test_retained_rows_and_timestamp_events(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);src=root/'live.csv';dest=root/'kept.csv'
            src.write_text('target pageflip timestamp,pageflip timestamp,a,b,c,d,e,f,g\n'+''.join(f'0,{i*1000000000},0,0,0,0,0,0,0\n' for i in range(1,6)))
            self.assertEqual(keep_rows(src,dest,0,2,5),3)
            with self.assertRaises(RuntimeError):keep_rows(src,dest,0,10,20)
            trace=root/'observer.csv';trace.write_text('event,start_ns,pts_us,arg1,arg2,output\nsource,2000000000,40,640,180,\ntexture_upload,3000000000,40,640,180,\nsource,5000000000,80,640,180,\n')
            self.assertEqual(telemetry(trace,2,5),{'source':1,'texture_upload':1,'unique_source_pts':1})




class FieldRegressionTests(unittest.TestCase):
    def test_nearest_refresh_and_tie(self):
        snapshot = fixture()
        modes = snapshot['outputs'][1]['modes']
        fractional = dict(modes[0], id='fractional', refreshRate=29.97)
        modes.insert(0, fractional)
        self.assertEqual(mode_ids(snapshot)['HDMI-A-1'], '13')
        modes[0]['refreshRate'] = 30
        with self.assertRaises(RuntimeError): mode_ids(snapshot)

    def test_lock_hint(self):
        import session
        from unittest.mock import patch
        with patch.object(session, 'command', side_effect=['1 1000 user seat0 tty2\n', 'LockedHint=no\n']):
            session.assert_unlocked()
        for replies in (['1 1000 user seat0 tty2\n', 'LockedHint=yes\n'], ['']):
            with patch.object(session, 'command', side_effect=replies):
                with self.assertRaises(RuntimeError): session.assert_unlocked()

    def test_dpms_on_and_all_negative_reports(self):
        import session
        session.check_dpms('dpms mode for screen eDP-1: on\ndpms mode for screen HDMI-A-1: on\n', ('eDP-1','HDMI-A-1'))
        for text in ('dpms mode for screen HDMI-A-1: off\n', '', 'DPMS not supported in this system',
                     'dpms mode for screen HDMI-A-1: on\ndpms mode for screen eDP-1: unknown\n',
                     'dpms mode for screen HDMI-A-1: on\n'):
            with self.assertRaises(RuntimeError): session.check_dpms(text, ('eDP-1','HDMI-A-1'))

    def test_late_window_and_retry_bound(self):
        import session
        from unittest.mock import patch, Mock
        guard = Mock()
        with patch.object(session, 'assert_unlocked'), patch.object(session, 'place') as placement, patch.object(session, 'verify_window', side_effect=[RuntimeError('late')]*3+[None]):
            session.place_until_fullscreen(Path('.'), 42, 'HDMI-A-1', 'test', Path('observer.csv'), guard)
            self.assertEqual(placement.call_count, 4)
        with patch.object(session, 'assert_unlocked'), patch.object(session, 'place') as placement, patch.object(session, 'verify_window', side_effect=RuntimeError('absent')):
            with self.assertRaises(RuntimeError): session.place_until_fullscreen(Path('.'), 42, 'HDMI-A-1', 'test', Path('observer.csv'), guard)
            self.assertEqual(placement.call_count, 8)

    def test_wake_checks_lock_before_dpms(self):
        import session
        from unittest.mock import patch
        calls = []
        def command(*argv):
            calls.append(argv)
            return 'dpms mode for screen eDP-1: on\ndpms mode for screen HDMI-A-1: on\n'
        with patch.object(session, 'assert_unlocked', side_effect=lambda: calls.append(('unlocked',))), patch.object(session, 'outputs', return_value=fixture()), patch.object(session, 'command', side_effect=command):
            session.wake_outputs()
        self.assertEqual(calls, [('unlocked',), ('kscreen-doctor','--dpms','on'), ('kscreen-doctor','--dpms','show')])

    def test_guard_rejects_dpms_off_even_without_dimming(self):
        import session
        from unittest.mock import patch
        with tempfile.TemporaryDirectory() as temp, patch.object(session.Guard, 'process_identity', return_value='same'):
            guard = session.Guard(Path(temp), 42, Path(temp))
            with patch.object(session, 'assert_unlocked'), patch.object(session, 'command', return_value='dpms mode for screen HDMI-A-1: off\n') as command:
                with self.assertRaises(RuntimeError): guard.check()
                command.assert_called_once_with('kscreen-doctor','--dpms','show')

if __name__=='__main__':unittest.main()
