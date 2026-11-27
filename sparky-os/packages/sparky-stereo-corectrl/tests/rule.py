#!/usr/bin/python3
# Which rule made by hand the package sets aside (`knob-owner same-rule`): the code of CoreCtrl's guide for the group sudo,
# whatever its comments and spacing; nothing else. And the shipped rule is that code too.
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
OWNER = os.environ.get("KNOB_OWNER", os.path.join(HERE, "..", "bin", "knob-owner"))
SHIPPED = os.path.join(HERE, "..", "share", "90-sparky-stereo-corectrl.rules")

# the hand-made file of the bench machines (537 bytes, 2026-11-15), word for word
HANDMADE = """// CoreCtrl: a local, active user who is an administrator (group sudo) starts
// its helper without typing a password. This is the rule CoreCtrl own setup
// guide gives ("Don t ask for user password"), with the group set to sudo.
polkit.addRule(function(action, subject) {
    if ((action.id == "org.corectrl.helper.init" ||
         action.id == "org.corectrl.helperkiller.init") &&
        subject.local == true &&
        subject.active == true &&
        subject.isInGroup("sudo")) {
            return polkit.Result.YES;
    }
});
"""
GUIDE = HANDMADE.split("\n", 3)[3]
CASES = [
    ("the bench machines' hand-made rule", HANDMADE, True),
    ("the guide's rule for sudo, no comments", GUIDE, True),
    ("the same on one line with single quotes", GUIDE.replace("\n", " ").replace('"', "'"), True),
    ("the same with a block comment", "/* mine */\n" + GUIDE, True),
    ("Debian's README hint as written (your-user-group)", GUIDE.replace('"sudo"', '"your-user-group"'), False),
    ("the guide's rule for wheel", GUIDE.replace('"sudo"', '"wheel"'), False),
    ("without the active check", GUIDE.replace("subject.active == true &&\n", ""), False),
    ("an extra rule after it", GUIDE + 'polkit.addRule(function(a, s) { return polkit.Result.YES; });\n', False),
    ("an empty file", "", False),
]


def same(text):
    with tempfile.NamedTemporaryFile("w", suffix=".rules", delete=False) as f:
        f.write(text)
    try:
        return subprocess.run([sys.executable, OWNER, "same-rule", f.name]).returncode == 0
    finally:
        os.unlink(f.name)


def main():
    failed = 0
    for name, text, want in CASES + [("the shipped rule", open(SHIPPED).read(), True)]:
        ok = same(text) == want
        failed += not ok
        print("%s  %s" % ("ok  " if ok else "FAIL", name))
    print("%d of %d cases failed" % (failed, len(CASES) + 1))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
