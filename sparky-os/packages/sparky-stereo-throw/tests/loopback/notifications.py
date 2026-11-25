#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-2.0-or-later
"""A stand-in for the desktop's notification server (org.freedesktop.Notifications, Desktop Notifications
Specification 1.2) on the session bus of the loopback proof: it answers as a server would and writes every Notify it
receives as one JSON line (application, summary, body, urgency), so the rows read what the person would be told.
Usage: notifications.py LOG_FILE"""
import json
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

LOG = sys.argv[1]
XML = """<node><interface name="org.freedesktop.Notifications">
<method name="Notify"><arg type="s" direction="in"/><arg type="u" direction="in"/><arg type="s" direction="in"/>
<arg type="s" direction="in"/><arg type="s" direction="in"/><arg type="as" direction="in"/><arg type="a{sv}" direction="in"/>
<arg type="i" direction="in"/><arg type="u" direction="out"/></method>
<method name="CloseNotification"><arg type="u" direction="in"/></method>
<method name="GetCapabilities"><arg type="as" direction="out"/></method>
<method name="GetServerInformation"><arg type="s" direction="out"/><arg type="s" direction="out"/><arg type="s" direction="out"/>
<arg type="s" direction="out"/></method>
<signal name="NotificationClosed"><arg type="u"/><arg type="u"/></signal>
<signal name="ActionInvoked"><arg type="u"/><arg type="s"/></signal>
</interface></node>"""
counter = [0]


def call(connection, sender, path, interface, method, params, invocation):
    if method == "Notify":
        app, replaces, icon, summary, body, actions, hints, timeout = params.unpack()
        counter[0] += 1
        with open(LOG, "a") as f:
            f.write(json.dumps({"app": app, "summary": summary, "body": body, "urgency": hints.get("urgency"),
                                "event": hints.get("x-kde-eventId")}, ensure_ascii=False) + "\n")
        invocation.return_value(GLib.Variant("(u)", (counter[0],)))
    elif method == "CloseNotification":
        invocation.return_value(None)
    elif method == "GetCapabilities":
        invocation.return_value(GLib.Variant("(as)", (["body", "actions"],)))
    elif method == "GetServerInformation":
        invocation.return_value(GLib.Variant("(ssss)", ("loopback-notifications", "Sparky Stereo OS", "1.0", "1.2")))


bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
bus.register_object("/org/freedesktop/Notifications", Gio.DBusNodeInfo.new_for_xml(XML).interfaces[0], call, None, None)
Gio.bus_own_name_on_connection(bus, "org.freedesktop.Notifications", Gio.BusNameOwnerFlags.NONE, None, None)
GLib.MainLoop().run()
