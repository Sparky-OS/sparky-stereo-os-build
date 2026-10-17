#!/usr/bin/env python3
"""vmctl.py : drive a running headless QEMU through its QMP socket, one action per call.

  vmctl.py SOCK shot FILE.png          screen to PNG (QMP screendump)
  vmctl.py SOCK key KEY[+KEY...]       one key or chord, QEMU qcodes (ret, tab, esc, ctrl+alt+t, f2 ...)
  vmctl.py SOCK type TEXT              types TEXT on the US layout (letters, digits, space and common signs)
  vmctl.py SOCK click X Y [W H]        left click at pixel X,Y of a W x H screen (default 1280 x 800); needs a usb-tablet
  vmctl.py SOCK dclick X Y [W H]       double click
  vmctl.py SOCK hmp "COMMAND"          a monitor command, its output printed
  vmctl.py SOCK quit                   stop QEMU

Nothing is shown on any display: QEMU runs with -display none; this only talks to its QMP socket.
"""
import json, os, socket, sys, time

SHIFTED = {'!': '1', '@': '2', '#': '3', '$': '4', '%': '5', '^': '6', '&': '7', '*': '8', '(': '9', ')': '0',
           '_': 'minus', '+': 'equal', '{': 'bracket_left', '}': 'bracket_right', ':': 'semicolon', '"': 'apostrophe',
           '<': 'comma', '>': 'dot', '?': 'slash', '|': 'backslash', '~': 'grave_accent'}
PLAIN = {' ': 'spc', '-': 'minus', '=': 'equal', '/': 'slash', '.': 'dot', ',': 'comma', ';': 'semicolon',
         "'": 'apostrophe', '[': 'bracket_left', ']': 'bracket_right', '\\': 'backslash', '`': 'grave_accent', '\n': 'ret'}


class Qmp:
    def __init__(self, path):
        self.s = socket.socket(socket.AF_UNIX)
        for _ in range(100):
            try:
                self.s.connect(path)
                break
            except OSError:
                time.sleep(0.1)
        else:
            raise SystemExit("no QMP socket at " + path)
        self.f = self.s.makefile("rw")
        json.loads(self.f.readline())
        self.cmd("qmp_capabilities")

    def cmd(self, name, **args):
        self.f.write(json.dumps({"execute": name, "arguments": args}) + "\n")
        self.f.flush()
        while True:
            msg = json.loads(self.f.readline())
            if "return" in msg or "error" in msg:
                return msg


def keys_for(ch):
    if ch.isupper():
        return ['shift', ch.lower()]
    if ch in SHIFTED:
        return ['shift', SHIFTED[ch]]
    if ch in PLAIN:
        return [PLAIN[ch]]
    return [ch]


def main():
    sock, action, *rest = sys.argv[1:]
    q = Qmp(sock)
    if action == "shot":
        r = q.cmd("screendump", filename=os.path.abspath(rest[0]), format="png")
    elif action == "key":
        r = q.cmd("send-key", keys=[{"type": "qcode", "data": k} for k in rest[0].split("+")])
    elif action == "type":
        for ch in " ".join(rest):
            q.cmd("send-key", keys=[{"type": "qcode", "data": k} for k in keys_for(ch)])
            time.sleep(0.04)
        r = {"return": {}}
    elif action in ("click", "dclick"):
        x, y = int(rest[0]), int(rest[1])
        w, h = (int(rest[2]), int(rest[3])) if len(rest) >= 4 else (1280, 800)
        ax, ay = x * 32767 // (w - 1), y * 32767 // (h - 1)
        q.cmd("input-send-event", events=[{"type": "abs", "data": {"axis": "x", "value": ax}},
                                           {"type": "abs", "data": {"axis": "y", "value": ay}}])
        time.sleep(0.15)
        for _ in range(2 if action == "dclick" else 1):
            q.cmd("input-send-event", events=[{"type": "btn", "data": {"down": True, "button": "left"}}])
            time.sleep(0.08)
            r = q.cmd("input-send-event", events=[{"type": "btn", "data": {"down": False, "button": "left"}}])
            time.sleep(0.12)
    elif action == "hmp":
        r = q.cmd("human-monitor-command", **{"command-line": rest[0]})
        print(r.get("return", r))
    elif action == "quit":
        r = q.cmd("quit")
    else:
        raise SystemExit(__doc__)
    if "error" in r:
        raise SystemExit(json.dumps(r))


if __name__ == "__main__":
    main()
