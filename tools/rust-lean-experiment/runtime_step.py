#!/usr/bin/env python3
"""Measure packaged compilers on a pinned offline regex subject and a std panic."""
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
from measure import run


def main(task):
    out=Path('/work/result');out.mkdir()
    env=os.environ
    env.update(SOURCE_DATE_EPOCH='1794523022',LC_ALL='C',CARGO_NET_OFFLINE='true',CARGO_HOME='/work/cargo-home',
               CARGO_BUILD_JOBS=env['RL541_CPUS'],CARGO_INCREMENTAL='0')
    if task=='startup':
        run(['rustc','--version'],out/'version')
        run(['rustc','-vV'],out/'verbose-version')
        with (out/'loader-statistics.txt').open('w') as f:
            subprocess.run(['rustc','--version'],env=dict(env,LD_DEBUG='libs,statistics'),stdout=f,stderr=f,check=True)
        loader=(out/'loader-statistics.txt').read_text()
        cycles=re.findall(r'total startup time in dynamic loader:\s*([0-9.,]+) clock cycles',loader)
        if len(cycles)!=1:
            cycles=re.findall(r'total startup time in dynamic loader:\s*([0-9.,]+) cycles',loader)
        expected_counts=2 if os.environ.get('RL541_FIXTURE') else 1
        if len(cycles)!=expected_counts:raise RuntimeError('loader startup cycle counts differ from the named process model')
        from measure import number
        (out/'loader.json').write_text(json.dumps({'total_startup_cycles':sum(number(c) for c in cycles),
            'scope':'total dynamic loader, with librustc_driver in the loaded DSO list; not driver alone'})+'\n')
        if 'librustc_driver' not in loader:
            raise RuntimeError('loader log does not show librustc_driver')
    elif task=='hello':
        src=Path('/work/main.rs');src.write_text('fn main() { println!("hello"); }\n')
        run(['rustc','--edition=2024','-O','--remap-path-prefix=/work=/experiment',str(src),'-o','/work/hello'],out/'compile')
        run(['/work/hello'],out/'program')
        shutil.copy2('/work/hello',out/'hello')
    elif task in ('check','release'):
        shutil.copytree('/subject','/work/subject')
        os.chdir('/work/subject')
        argv=['cargo',task if task=='check' else 'build','--offline','--frozen','--jobs',env['RL541_CPUS']]
        if task=='release':argv.append('--release')
        env['RUSTFLAGS']='--remap-path-prefix=/work=/experiment'
        run(argv,out/'compile')
        if task=='release':
            exe=Path('/work/subject/target/release/regex-subject')
            run([str(exe)],out/'program');shutil.copy2(exe,out/'regex-subject')
    elif task=='panic':
        if os.environ.get('RL541_FIXTURE'):
            from fixture import panic
            panic(out)
            (out/'step.json').write_text('{"complete":true,"fixture":true}\n')
            return
        # /dev/full makes std::io::stdio::print_to panic with ENOSPC inside std.
        src=Path('/work/panic.rs');src.write_text('''use std::os::fd::AsRawFd;
unsafe extern "C" { fn dup2(old: i32, new: i32) -> i32; }
fn main() {
    let f = std::fs::OpenOptions::new().write(true).open("/dev/full").unwrap();
    assert!(unsafe { dup2(f.as_raw_fd(), 1) } >= 0);
    println!("trigger standard library print failure");
}
''')
        run(['rustc','--edition=2024',str(src),'-o','/work/panic'],out/'compile')
        env['RUST_BACKTRACE']='0'
        run(['/work/panic'],out/'panic',expected=101)
        text=(out/'panic/stderr').read_text()
        if 'library/std/src/io/stdio.rs:' not in text:
            raise RuntimeError('panic did not originate in standard-library stdio')
    else:raise ValueError(task)
    (out/'step.json').write_text(json.dumps({'complete':True,'task':task})+'\n')


if __name__=='__main__': main(sys.argv[1])
