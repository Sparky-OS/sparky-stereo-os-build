#!/usr/bin/python3
# The service starts at boot: no ordering on a unit that is itself ordered after multi-user.target, which wants this one.
# power-profiles-daemon.service is After=multi-user.target display-manager.target, so "After=power-profiles-daemon.service"
# here made a cycle, and systemd deleted this unit's start job at boot ("Job ... deleted to break ordering cycle", seen on
# the bench). The service follows the daemons on the bus instead.
# It is ready before lactd starts: lactd (After=multi-user.target) turns power-profiles-daemon's amdgpu_dpm action off at
# its start, and the service must already watch who changes the action (Type=notify, READY once its bus monitor listens;
# Before=lactd.service). It reads CoreCtrl's profiles in the person's settings folder (ProtectHome=read-only).
import configparser
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
UNIT = os.environ.get("KNOB_UNIT", os.path.join(HERE, "..", "share", "sparky-stereo-knob-owner.service"))
LATE = {"power-profiles-daemon.service", "display-manager.service", "graphical.target", "multi-user.target", "lactd.service"}
unit = configparser.ConfigParser(strict=False, interpolation=None)
unit.optionxform = str
unit.read(UNIT)
after = set(unit.get("Unit", "After", fallback="").split())
before = set(unit.get("Unit", "Before", fallback="").split())
wanted = unit.get("Install", "WantedBy", fallback="")
checks = [
    ("After=%s, WantedBy=%s" % (" ".join(sorted(after)), wanted), not (after & LATE),
     "ordered after %s, which is ordered after the target that wants this unit" % ", ".join(sorted(after & LATE))),
    ("Before=%s" % " ".join(sorted(before)), "lactd.service" in before, "not ordered before lactd.service"),
    ("Type=%s, NotifyAccess=%s" % (unit.get("Service", "Type", fallback=""), unit.get("Service", "NotifyAccess", fallback="")),
     unit.get("Service", "Type", fallback="") == "notify" and unit.get("Service", "NotifyAccess", fallback="") == "main",
     "lactd could start before the monitor listens"),
    ("ProtectHome=%s" % unit.get("Service", "ProtectHome", fallback=""), unit.get("Service", "ProtectHome", fallback="") == "read-only",
     "CoreCtrl's profiles in the person's folder cannot be read"),
]
failed = 0
for name, ok, why in checks:
    print("%s  %s" % ("ok  " if ok else "FAIL", name))
    if not ok:
        failed += 1
        print("      " + why)
sys.exit(1 if failed else 0)
