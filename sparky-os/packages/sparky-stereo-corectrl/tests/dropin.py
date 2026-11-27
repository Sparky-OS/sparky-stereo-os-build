#!/usr/bin/python3
# The runtime drop-in's text: power-profiles-daemon's own command line, then the blocks; quoting by systemd.service(5).
import importlib.machinery
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OWNER = os.environ.get("KNOB_OWNER", os.path.join(HERE, "..", "bin", "knob-owner"))
loader = importlib.machinery.SourceFileLoader("knob_owner", OWNER)
spec = importlib.util.spec_from_loader("knob_owner", loader)
ko = importlib.util.module_from_spec(spec)
loader.exec_module(ko)

failed = 0


def check(name, got, want):
    global failed
    ok = got == want
    failed += not ok
    print("%s  %s" % ("ok  " if ok else "FAIL", name))
    if not ok:
        print("      want %r\n      got  %r" % (want, got))


ko.ppd_command = lambda: ["/usr/libexec/power-profiles-daemon"]
text = ko.ppd_dropin(["--block-driver=amd_pstate", "--block-driver=intel_pstate"])
check("the blocks follow the daemon's own command", text.splitlines()[-1],
      "ExecStart=/usr/libexec/power-profiles-daemon --block-driver=amd_pstate --block-driver=intel_pstate")
check("ExecStart is reset first", text.splitlines()[-2], "ExecStart=")
check("nothing to block, no drop-in", ko.ppd_dropin([]), None)
ko.ppd_command = lambda: ["/usr/libexec/power-profiles-daemon", "-v"]
check("a person's own option is kept", ko.ppd_dropin(["--block-action=amdgpu_dpm"]).splitlines()[-1],
      "ExecStart=/usr/libexec/power-profiles-daemon -v --block-action=amdgpu_dpm")
check("a space is quoted", ko.quote("a b"), '"a b"')
check("a percent sign is doubled", ko.quote("50%"), "50%%")
check("a plain word stays", ko.quote("--block-driver=amd_pstate"), "--block-driver=amd_pstate")
print("%d failed" % failed)
sys.exit(1 if failed else 0)
