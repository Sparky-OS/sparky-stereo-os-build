#!/usr/bin/python3 -I
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
# A stand-in for power-profiles-daemon on a private bus (the real one needs root and the system bus):
# the same interface, properties and method the page uses. Usage: fake-ppd.py PROFILE STATEFILE
import sys

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

profile = sys.argv[1]
state = sys.argv[2]
actions = {
    "trickle_charge": ("Configure power supply to trickle charge", True),
    "amdgpu_panel_power": ("Panel Power Savings (may affect color quality)", False),
    "amdgpu_dpm": ("Adjust GPU dynamic power management", False),
}
IFACE = "net.hadess.PowerProfiles"


def save():
    with open(state, "w") as f:
        for name, (_, enabled) in sorted(actions.items()):
            f.write("%s=%s\n" % (name, "true" if enabled else "false"))


class Ppd(dbus.service.Object):
    def props(self):
        info = dbus.Array(
            [dbus.Dictionary({"Name": n, "Description": d, "Enabled": dbus.Boolean(e)}, signature="sv") for n, (d, e) in sorted(actions.items())],
            signature="a{sv}",
        )
        return {"ActiveProfile": dbus.String(profile), "ActionsInfo": info, "Actions": dbus.Array([n for n, (_, e) in actions.items() if e], signature="s")}

    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="ss", out_signature="v")
    def Get(self, iface, name):
        return self.props()[name]

    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, iface):
        return self.props()

    @dbus.service.method(IFACE, in_signature="sb", out_signature="")
    def SetActionEnabled(self, name, enabled):
        if name not in actions:
            raise dbus.exceptions.DBusException("net.hadess.PowerProfiles.Error", "no such action")
        actions[name] = (actions[name][0], bool(enabled))
        save()


dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus = dbus.SystemBus()
name = dbus.service.BusName(IFACE, bus)
Ppd(bus, "/net/hadess/PowerProfiles")
save()
print("ready", flush=True)
GLib.MainLoop().run()
