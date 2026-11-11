#!/usr/bin/python3 -I
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
# A stand-in for the session's notification server (org.freedesktop.Notifications, Desktop Notifications
# Specification 1.2) on a private bus: it writes each Notify call to a JSON file and answers the first one, half a
# second later, with the action it is given, as a person clicking it would. Usage: fake-notifications.py OUT ACTION
import json
import sys

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

out, answer = sys.argv[1], sys.argv[2]
IFACE = "org.freedesktop.Notifications"
calls = []


class Server(dbus.service.Object):
    @dbus.service.method(IFACE, in_signature="susssasa{sv}i", out_signature="u")
    def Notify(self, app, replaces, icon, summary, body, actions, hints, timeout):
        calls.append({"app": str(app), "icon": str(icon), "summary": str(summary), "body": str(body),
                      "actions": [str(a) for a in actions], "urgency": int(hints.get("urgency", -1)), "timeout": int(timeout)})
        with open(out, "w") as f:
            json.dump(calls, f, ensure_ascii=False)
        nid = len(calls)
        if nid == 1:
            GLib.timeout_add(500, lambda: (self.ActionInvoked(dbus.UInt32(nid), answer), False)[1])
        return dbus.UInt32(nid)

    @dbus.service.method(IFACE, in_signature="u", out_signature="")
    def CloseNotification(self, nid):
        self.NotificationClosed(nid, dbus.UInt32(3))

    @dbus.service.method(IFACE, in_signature="", out_signature="as")
    def GetCapabilities(self):
        return ["actions", "body"]

    @dbus.service.method(IFACE, in_signature="", out_signature="ssss")
    def GetServerInformation(self):
        return ("fake", "test", "1", "1.2")

    @dbus.service.signal(IFACE, signature="us")
    def ActionInvoked(self, nid, action):
        pass

    @dbus.service.signal(IFACE, signature="uu")
    def NotificationClosed(self, nid, reason):
        pass


dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
name = dbus.service.BusName(IFACE, bus)
Server(bus, "/org/freedesktop/Notifications")
print("ready", flush=True)
GLib.MainLoop().run()
