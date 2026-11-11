#!/usr/bin/python3
# Runs a command on a terminal (a pseudo-terminal), answers its "[Y/n]" question with ANSWER and prints everything it wrote.
# Usage: pty-answer.py ANSWER COMMAND [ARG...]; exit status is the command's.
import os, pty, select, sys, time

answer = sys.argv[1]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(sys.argv[2], sys.argv[2:])
out = b''
answered = False
deadline = time.time() + 600
while time.time() < deadline:
    r, _, _ = select.select([fd], [], [], 1)
    if r:
        try:
            data = os.read(fd, 4096)
        except OSError:
            break
        if not data:
            break
        out += data
        if not answered and b'[Y/n]' in out:
            os.write(fd, (answer + '\n').encode())
            answered = True
_, status = os.waitpid(pid, 0)
sys.stdout.write(out.decode(errors='replace').replace('\r\n', '\n'))
sys.stdout.write('\n[question %s]\n' % ('answered ' + answer if answered else 'never asked'))
sys.exit(os.waitstatus_to_exitcode(status))
