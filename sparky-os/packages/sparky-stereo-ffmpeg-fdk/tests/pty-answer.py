#!/usr/bin/env python3
# Test helper: runs a command on a pseudo-terminal and answers its questions when they are asked (never before: a program that
# changes the terminal, as sudo and apt do, throws away what was typed ahead).
# Usage: pty-answer.py 'text to wait for=answer' ['text=answer' ...] -- command args...
# Prints everything the command wrote; exits with the command's exit code. Gives up after 20 minutes.
import os, pty, select, sys, time
args = sys.argv[1:]
i = args.index('--')
rules = [a.split('=', 1) for a in args[:i]]
cmd = args[i + 1:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(cmd[0], cmd)
seen = b''
done = [False] * len(rules)
end = time.time() + 1200
while time.time() < end:
    r, _, _ = select.select([fd], [], [], 1.0)
    if r:
        try:
            data = os.read(fd, 65536)
        except OSError:
            data = b''
        if not data:
            break
        sys.stdout.buffer.write(data)
        sys.stdout.buffer.flush()
        seen += data
        for n, (text, answer) in enumerate(rules):
            if not done[n] and text.encode() in seen:
                done[n] = True
                seen = b''
                os.write(fd, (answer + '\n').encode())
                break
if time.time() >= end:
    os.kill(pid, 15)
_, st = os.waitpid(pid, 0)
sys.exit(os.waitstatus_to_exitcode(st))
