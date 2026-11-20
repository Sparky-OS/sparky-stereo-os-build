#!/usr/bin/python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
"""A stand-in for com.feralinteractive.GameMode on the session bus: ListGames answers after DELAY_MS with one game.
Only the calls the applet makes are answered; no game is run and no gamemoded is touched."""
import os
import sys

import gi
gi.require_version('Gio', '2.0')
from gi.repository import Gio, GLib

DELAY = int(os.environ.get('DELAY_MS', '600'))
PATH = '/com/feralinteractive/GameMode/Game/1234'
XML = '''<node>
 <interface name="com.feralinteractive.GameMode">
  <method name="ListGames"><arg type="a(io)" direction="out"/></method>
  <signal name="GameRegistered"><arg type="i"/><arg type="o"/></signal>
  <signal name="GameUnregistered"><arg type="i"/><arg type="o"/></signal>
 </interface>
 <interface name="com.feralinteractive.GameMode.Game">
  <property name="ProcessId" type="i" access="read"/>
  <property name="Executable" type="s" access="read"/>
  <property name="Requester" type="i" access="read"/>
  <property name="Timestamp" type="t" access="read"/>
 </interface>
</node>'''
info = Gio.DBusNodeInfo.new_for_xml(XML)
calls = 0


def method_call(connection, sender, path, interface, name, params, invocation):
    global calls
    calls += 1
    print('standin: ListGames call %d' % calls, flush=True)
    GLib.timeout_add(DELAY, lambda: invocation.return_value(GLib.Variant('(a(io))', ([(1234, PATH)],))) or False)


def get_property(connection, sender, path, interface, prop):
    return {'ProcessId': GLib.Variant('i', 1234), 'Executable': GLib.Variant('s', '/usr/bin/standin-game'),
            'Requester': GLib.Variant('i', 1), 'Timestamp': GLib.Variant('t', 1)}[prop]


def on_bus(connection, name):
    connection.register_object('/com/feralinteractive/GameMode', info.lookup_interface('com.feralinteractive.GameMode'), method_call, None, None)
    connection.register_object(PATH, info.lookup_interface('com.feralinteractive.GameMode.Game'), None, get_property, None)


def on_name(connection, name):
    print('standin: ready', flush=True)


loop = GLib.MainLoop()
Gio.bus_own_name(Gio.BusType.SESSION, 'com.feralinteractive.GameMode', Gio.BusNameOwnerFlags.NONE, on_bus, on_name, lambda *a: loop.quit())
loop.run()
