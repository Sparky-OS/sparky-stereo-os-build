#!/usr/bin/python3
"""Private working directory proves argument/cwd delegation, with a swallowing negative control."""
from pathlib import Path
import os
import subprocess
import sys
import tempfile

source = Path(sys.argv[1])
with tempfile.TemporaryDirectory() as directory:
    root=Path(directory)
    (root/'original').mkdir()
    (root/'common.py').write_text("ACTION='/nonexistent'\n")
    original=root/'original/handler'
    original.write_text('#!/bin/sh\nprintf "%s\\n" "$PWD" "$@"\nexit 77\n')
    original.chmod(0o755)
    uri='aptus://sysoth_bleachbit'
    for name, code, expected in [('good',source.read_text().replace('/usr/lib/sparky-aptus-appcenter',str(root/'original')),True),
                                  ('swallowed','import sys; sys.exit(1)',False)]:
        script=root/name
        script.write_text(code)
        result=subprocess.run([sys.executable,str(script),uri,'unchanged second argument'],capture_output=True,text=True)
        passed=result.returncode==77 and result.stdout.splitlines()==[str(root/'original'),uri,'unchanged second argument']
        print(f'{name}: exit={result.returncode}; delegation assertion={passed}')
        assert passed==expected
print('PASS forwarding preserves URI, arguments and original working directory; swallowing fails')
