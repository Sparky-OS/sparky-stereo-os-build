#!/usr/bin/env python3
"""Fault injection for decimal collection, source guards and whole-step receipts."""
import contextlib
import io
import json
import os
from pathlib import Path
import signal
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
import guard
from measure import number,parse_perf
from inputs import census
from package_wrapper import restore
from runner import Runner,extract,inventory
from summary import summarize

PERF=''' 100000 instructions:u
 11 page-faults
 1,250 seconds time elapsed
 2,000 seconds user
 0,125 seconds sys
'''


class CollectorTests(unittest.TestCase):
    def test_comma_and_point(self):
        self.assertEqual(number('1,25'),number('1.25'))
        self.assertEqual(parse_perf(PERF)['wall_seconds'],1.25)
        self.assertEqual(parse_perf(PERF.replace(',','.'))['user_seconds'],2)
        with self.assertRaises(ValueError):number('1,234.5')
        with self.assertRaises(ValueError):number('1e999')
    def test_no_empty_perf(self):
        for text in (PERF.replace('100000','0'),PERF.replace('instructions:u','instructions'),PERF.replace('1,250','0'),PERF.replace('100000','1,25'),PERF.replace('2,000','-1,00')):
            with self.assertRaises(ValueError):parse_perf(text)
    def test_rust_src_exact_restoration(self):
        with tempfile.TemporaryDirectory() as d:
            a,b,s=[Path(d)/p for p in 'abs']
            for p in (a,b,s):p.mkdir()
            (a/'main.rs').write_text('// authored\nfn main() {}\n')
            for p in (b,s):(p/'main.rs').write_text('fn main() {}\n')
            import hashlib
            for p in (a,b,s):
                meta={'files':{'main.rs':hashlib.sha256((p/'main.rs').read_bytes()).hexdigest()},'package':'fixture'}
                (p/'.cargo-checksum.json').write_text(json.dumps(meta))
            self.assertEqual(restore(s,a,b),['main.rs','.cargo-checksum.json'])
            self.assertEqual((s/'.cargo-checksum.json').read_bytes(),(a/'.cargo-checksum.json').read_bytes())
            self.assertEqual((s/'main.rs').read_bytes(),(a/'main.rs').read_bytes())
            (s/'main.rs').write_text('unexpected')
            with self.assertRaises(RuntimeError):restore(s,a,b)


class InputTests(unittest.TestCase):
    def test_real_depinfo_alias_and_spaces(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);tree=root/'tree';ref=root/'ref'
            for p in (tree,ref):
                (p/'src/nested').mkdir(parents=True)
                (p/'src/space file.rs').write_text('// source\nfn main() {}\n')
            (tree/'build').mkdir()
            path=str(tree/'src/space file.rs').replace(' ','\\ ')
            alias=str(tree/'src/nested/../space file.rs').replace(' ','\\ ')
            (tree/'build/unit.d').write_text('output: '+path+' '+alias+'\n')
            data=census(tree,root/'inputs.json',ref)
            self.assertEqual(data['unique_files'],1)
            self.assertEqual(data['lines'],2)
            (tree/'src/space file.rs').write_text('changed')
            with self.assertRaisesRegex(RuntimeError,'changed after source sealing'):census(tree,root/'bad.json',ref)


    def test_build_owned_rust_outside_build_is_bound(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);tree=root/'tree';(tree/'build').mkdir(parents=True);(tree/'vendor').mkdir()
            producer=tree/'generate.sh';producer.write_text('generate the pinned literal')
            src=tree/'vendor/generated.rs';src.write_text('// generated literal\npub fn f() {}\n')
            (tree/'build/unit.d').write_text('out: '+str(src)+'\n')
            import hashlib
            spec={'files':{'vendor/generated.rs':{'sha256':hashlib.sha256(src.read_bytes()).hexdigest(),
                         'producer':'generate.sh','producer_sha256':hashlib.sha256(producer.read_bytes()).hexdigest()}}}
            data=census(tree,root/'input.json',tree,spec)
            self.assertTrue(data['files']['vendor/generated.rs']['generated'])
            src.write_text('unexpected generated source')
            with self.assertRaisesRegex(RuntimeError,'prepared literal'):census(tree,root/'bad.json',tree,spec)


class GuardTests(unittest.TestCase):
    def config(self,root):
        sysroot=root/'sys';hw=sysroot/'class/hwmon/hwmon0';hw.mkdir(parents=True)
        (hw/'name').write_text('k10temp');(hw/'temp1_input').write_text('50000')
        cpu=sysroot/'devices/system/cpu/cpu0/cpufreq';cpu.mkdir(parents=True)
        (cpu/'scaling_cur_freq').write_text('1000000');(cpu/'scaling_governor').write_text('powersave')
        # This is a driver fixture, never a substitute sensor for production.
        engine=root/'engine.py'
        engine.write_text('''import sys,time
from pathlib import Path
root=Path(sys.argv[1]);action=sys.argv[2]
with (root/'actions').open('a') as f:f.write(action+'\\n')
if action=='run':time.sleep(0.25)
''')
        import sys
        e=[sys.executable,str(engine),str(root)]
        return {'name':'rl541-guard-test','engine':e,'argv':e+['run'],'output':str(root/'out'),
                'floors_gib':{str(root):0},'interval':0.02,'sysroot':str(sysroot)},hw/'temp1_input'
    def test_space_red_then_green(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);cfg,t=self.config(root)
            fake=type('Usage',(),{'free':4*1024**3})()
            with patch('guard.shutil.disk_usage',return_value=fake),self.assertRaisesRegex(RuntimeError,'space guard'):
                guard.guarded(cfg)
            self.assertFalse((root/'out/guard-result.json').exists())
            self.assertTrue((root/'out/failed.json').exists())
            guard.guarded(cfg)
            self.assertTrue((root/'out/guard-result.json').exists())
    def test_heat_pause_resume(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);cfg,t=self.config(root)
            def heat():
                time.sleep(0.05);t.write_text('95000');time.sleep(0.08);t.write_text('50000')
            worker=threading.Thread(target=heat);worker.start();r=guard.guarded(cfg);worker.join()
            actions=(root/'actions').read_text().splitlines()
            self.assertIn('pause',actions);self.assertIn('unpause',actions)
            self.assertLess(actions.index('pause'),actions.index('unpause'))
            self.assertGreater(r['thermal_paused_seconds'],0)
    def test_cooldown_timeout_red(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);cfg,t=self.config(root);t.write_text('70000');cfg['cooldown_timeout_seconds']=0.04
            with self.assertRaisesRegex(RuntimeError,'cool-down timeout'):guard.guarded(cfg)
            self.assertFalse((root/'actions').exists())
    def test_missing_sensor_red(self):
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaisesRegex(RuntimeError,'temperature unavailable'):guard.machine(Path(d))


class ReceiptTests(unittest.TestCase):
    def test_accept_finished_then_detect_corruption(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);plan={'version':'fixture','image_id':'sha256:fixture','cpus':2}
            (root/'plan.json').write_text(json.dumps(plan));(root/'SHA256SUMS').write_text('');runner=Runner(root)
            step={'id':'a','kind':'check','form':'A'};dest=root/'results/a';dest.mkdir();(dest/'value').write_text('whole')
            from runner import sha
            guard.atomic(dest/'receipt.json',{'complete':True,'plan_sha256':runner.digest,'payload_sha256':runner.payload,'step':step,
                                              'files':{'value':sha(dest/'value')},'completed_unix':1})
            self.assertTrue(runner.accepted(step));self.assertIn('a',runner.state['completed'])
            (dest/'value').write_text('corrupt')
            with self.assertRaisesRegex(RuntimeError,'finished result changed'):runner.accepted(step)
    def test_half_step_not_accepted(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);(root/'plan.json').write_text(json.dumps({'version':'fixture','image_id':'none','cpus':2}))
            (root/'SHA256SUMS').write_text('');runner=Runner(root);p=root/'results/a';p.mkdir();(p/'metrics.json').write_text('{}')
            self.assertFalse(runner.accepted({'id':'a','kind':'check','form':'A'}))
    def test_comma_summary_tables(self):
        with tempfile.TemporaryDirectory() as d:
            root=Path(d);steps=[]
            for i,f in enumerate('ABABC'):
                step={'id':str(i),'kind':'check','form':f};steps.append(step)
                p=root/'results'/str(i);(p/'result/compile').mkdir(parents=True)
                (p/'receipt.json').write_text('{"complete":true}')
                metrics={k:'1,25' for k in ('wall_seconds','user_seconds','system_seconds','instructions','page_faults','max_child_rss_kib','cgroup_peak_bytes')}
                (p/'result/compile/metrics.json').write_text(json.dumps(metrics))
            rows=summarize(root,{'version':'fixture','steps':steps})
            self.assertEqual(rows[0]['forms']['A']['mean'],1.25)
            text=(root/'summary/REPORT.md').read_text();self.assertIn('| A mean',text);self.assertIn('0 (0%)',text)
            self.assertIn('single observation',text);self.assertIn('inside observed spread',text)


if __name__=='__main__':unittest.main(verbosity=2)
