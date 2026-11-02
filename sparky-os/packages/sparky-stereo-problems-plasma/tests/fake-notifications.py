#!/usr/bin/python3 -I
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
# A stand-in for the session's notification server (org.freedesktop.Notifications, Desktop Notifications
# Specification 1.2) on the session bus: it writes each Notify and CloseNotification call to a JSON file, and its
# test interface (org.sparkylinux.Test.Invoke on /test) clicks an action of a notification, as a person would.
# Usage: fake-notifications.py OUT
import json
import sys

import dbus
import dbus.mainloop.glib
import dbus.service
from gi.repository import GLib

out = sys.argv[1]
IFACE = "org.freedesktop.Notifications"
log = {"notify": [], "closed": []}


def save():
    with open(out + ".tmp", "w") as f:
        json.dump(log, f, ensure_ascii=False)
    import os
    os.replace(out + ".tmp", out)


class Server(dbus.service.Object):
    @dbus.service.method(IFACE, in_signature="susssasa{sv}i", out_signature="u")
    def Notify(self, app, replaces, icon, summary, body, actions, hints, timeout):
        nid = len(log["notify"]) + 1
        log["notify"].append({"id": nid, "app": str(app), "replaces": int(replaces), "icon": str(icon), "summary": str(summary),
                              "body": str(body), "actions": [str(a) for a in actions],
                              "urgency": int(hints.get("urgency", -1)), "timeout": int(timeout)})
        save()
        return dbus.UInt32(nid)

    @dbus.service.method(IFACE, in_signature="u", out_signature="")
    def CloseNotification(self, nid):
        log["closed"].append(int(nid))
        save()
        self.NotificationClosed(nid, dbus.UInt32(3))

    @dbus.service.method(IFACE, in_signature="", out_signature="as")
    def GetCapabilities(self):
        return ["actions", "body", "body-markup", "persistence"]

    @dbus.service.method(IFACE, in_signature="", out_signature="ssss")
    def GetServerInformation(self):
        return ("fake", "test", "1", "1.2")

    @dbus.service.signal(IFACE, signature="us")
    def ActionInvoked(self, nid, action):
        pass

    @dbus.service.signal(IFACE, signature="uu")
    def NotificationClosed(self, nid, reason):
        pass


class Test(dbus.service.Object):
    def __init__(self, bus, server):
        super().__init__(bus, "/test")
        self.server = server

    # clicks the action whose label is LABEL on notification NID (as Plasma does: ActionInvoked, then closed)
    @dbus.service.method("org.sparkylinux.Test", in_signature="us", out_signature="s")
    def Invoke(self, nid, label):
        actions = log["notify"][int(nid) - 1]["actions"]
        for i in range(0, len(actions) - 1, 2):
            if actions[i + 1] == label:
                self.server.ActionInvoked(nid, actions[i])
                self.server.NotificationClosed(nid, dbus.UInt32(2))
                return actions[i]
        return ""


dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
name = dbus.service.BusName(IFACE, bus)
server = Server(bus, "/org/freedesktop/Notifications")
Test(bus, server)
save()
print("ready", flush=True)
GLib.MainLoop().run()
