#!/usr/bin/python3 -I
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
# A stand-in for the session's systemd on a private bus (ORDER 467): the units a test describes in a JSON file, answered the
# way systemd answers GetUnit and the Unit and Service properties the handler reads. The real systemd is run by
# died-systemd-test.sh. Usage: fake-systemd.py UNITS.json
import json
import sys

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

units = json.load(open(sys.argv[1]))
MANAGER = "org.freedesktop.systemd1.Manager"
paths = {name: "/org/freedesktop/systemd1/unit/u%d" % i for i, name in enumerate(sorted(units))}


class Unit(dbus.service.Object):
    def __init__(self, bus, name):
        super().__init__(bus, paths[name])
        self.u = units[name]

    def props(self, iface):
        u = self.u
        if iface == "org.freedesktop.systemd1.Unit":
            return {
                "SourcePath": dbus.String(u.get("SourcePath", "")),
                "ActiveEnterTimestampMonotonic": dbus.UInt64(int(u.get("start", 0) * 1e6)),
                "InactiveEnterTimestampMonotonic": dbus.UInt64(int((u.get("start", 0) + u.get("ran", 0)) * 1e6)),
            }
        if iface == "org.freedesktop.systemd1.Service":
            return {
                "Result": dbus.String(u.get("Result", "success")),
                "ExecMainStatus": dbus.Int32(u.get("Status", 0)),
                "Environment": dbus.Array([dbus.String(e) for e in u.get("Environment", [])], signature="s"),
            }
        return {}

    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, iface):
        return self.props(iface)


class Manager(dbus.service.Object):
    @dbus.service.method(MANAGER, in_signature="s", out_signature="o")
    def GetUnit(self, name):
        if name not in paths:
            raise dbus.exceptions.DBusException("org.freedesktop.systemd1.NoSuchUnit", "Unit %s not loaded." % name)
        return dbus.ObjectPath(paths[name])


dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
name = dbus.service.BusName("org.freedesktop.systemd1", bus)
Manager(bus, "/org/freedesktop/systemd1")
objs = [Unit(bus, n) for n in units]
print("ready", flush=True)
GLib.MainLoop().run()
