#!/usr/bin/python3
# A stand-in for NetworkManager on the system bus: it owns org.freedesktop.NetworkManager and answers the property Metered
# (NMMetered: 0 unknown, 1 yes, 2 no, 3 guess-yes, 4 guess-no) with the number in /run/fake-nm-metered, read at every question.
# The questioner is the real busctl on the real bus; only NetworkManager itself is not there.
import dbus, dbus.service, dbus.mainloop.glib
from gi.repository import GLib

dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
bus = dbus.SystemBus()
name = dbus.service.BusName('org.freedesktop.NetworkManager', bus)


def value():
    try:
        return dbus.UInt32(int(open('/run/fake-nm-metered').read().strip()))
    except (OSError, ValueError):
        return dbus.UInt32(0)


class NM(dbus.service.Object):
    @dbus.service.method('org.freedesktop.DBus.Properties', in_signature='ss', out_signature='v')
    def Get(self, interface, prop):
        if prop == 'Metered':
            return value()
        raise dbus.exceptions.DBusException('no such property ' + prop)

    @dbus.service.method('org.freedesktop.DBus.Properties', in_signature='s', out_signature='a{sv}')
    def GetAll(self, interface):
        return {'Metered': value()}


NM(bus, '/org/freedesktop/NetworkManager')
GLib.MainLoop().run()
