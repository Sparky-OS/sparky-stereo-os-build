#!/usr/bin/python3
# The service starts at boot: no ordering on a unit that is itself ordered after multi-user.target, which wants this one.
# power-profiles-daemon.service is After=multi-user.target display-manager.target, so "After=power-profiles-daemon.service"
# here made a cycle, and systemd deleted this unit's start job at boot ("Job ... deleted to break ordering cycle", seen on
# the bench). The service follows the daemons on the bus instead.
import configparser
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
UNIT = os.environ.get("KNOB_UNIT", os.path.join(HERE, "..", "share", "sparky-stereo-knob-owner.service"))
LATE = {"power-profiles-daemon.service", "display-manager.service", "graphical.target", "multi-user.target"}
unit = configparser.ConfigParser(strict=False, interpolation=None)
unit.optionxform = str
unit.read(UNIT)
after = set(unit.get("Unit", "After", fallback="").split())
wanted = unit.get("Install", "WantedBy", fallback="")
bad = sorted(after & LATE)
print("%s  After=%s, WantedBy=%s" % ("ok  " if not bad else "FAIL", " ".join(sorted(after)), wanted))
if bad:
    print("      ordered after %s, which is ordered after the target that wants this unit" % ", ".join(bad))
sys.exit(1 if bad else 0)
