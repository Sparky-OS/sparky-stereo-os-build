# SPDX-License-Identifier: GPL-2.0-or-later
import dbus
import os
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

DBusGMainLoop(set_as_default=True)
class Power(dbus.service.Object):
    def __init__(self):
        self.name = dbus.service.BusName('org.freedesktop.UPower', dbus.SystemBus())
        super().__init__(self.name, '/org/freedesktop/UPower')
        self.battery = False
    @dbus.service.method('org.freedesktop.UPower', out_signature='ao')
    def EnumerateDevices(self): return []
    @dbus.service.method('org.freedesktop.DBus.Properties', in_signature='ss', out_signature='v')
    def Get(self, interface, name):
        if interface != 'org.freedesktop.UPower' or name != 'OnBattery': raise ValueError('property')
        return dbus.Boolean(self.battery)
    @dbus.service.signal('org.freedesktop.DBus.Properties', signature='sa{sv}as')
    def PropertiesChanged(self, interface, values, invalid): pass
    @dbus.service.method('org.sparky.Test', in_signature='b')
    def SetBattery(self, value):
        self.battery = bool(value)
        self.PropertiesChanged('org.freedesktop.UPower', {'OnBattery':dbus.Boolean(value)}, [])
class Locker(dbus.service.Object):
    def __init__(self):
        self.name = dbus.service.BusName('org.freedesktop.ScreenSaver', dbus.SessionBus())
        super().__init__(self.name, '/ScreenSaver')
        self.locked = False
    @dbus.service.method('org.freedesktop.ScreenSaver', out_signature='b')
    def GetActive(self): return self.locked
    @dbus.service.signal('org.freedesktop.ScreenSaver', signature='b')
    def ActiveChanged(self, value): pass
    @dbus.service.method('org.sparky.Test', in_signature='b')
    def SetLocked(self, value):
        self.locked = bool(value); self.ActiveChanged(value)
class Login(dbus.service.Object):
    def __init__(self):
        self.name = dbus.service.BusName('org.freedesktop.login1', dbus.SystemBus())
        super().__init__(self.name, '/org/freedesktop/login1')
        self.session = LoginSession(self.name)
    @dbus.service.method('org.freedesktop.login1.Manager', in_signature='s', out_signature='o')
    def GetSession(self, name): return '/org/freedesktop/login1/session/auto'
class LoginSession(dbus.service.Object):
    def __init__(self, name):
        super().__init__(name, '/org/freedesktop/login1/session/auto')
        self.locked = False
    @dbus.service.method('org.freedesktop.login1.Session', in_signature='b')
    def SetLockedHint(self, value): self.locked = bool(value)
    @dbus.service.method('org.freedesktop.DBus.Properties', in_signature='ss', out_signature='v')
    def Get(self, interface, name):
        if name == 'LockedHint': return dbus.Boolean(self.locked)
        if name == 'Active': return dbus.Boolean(True)
        raise ValueError('property')
    @dbus.service.signal('org.freedesktop.login1.Session')
    def Unlock(self): pass
    @dbus.service.method('org.sparky.Test')
    def RequestUnlock(self): self.Unlock()
login = Login()
power = Power()
locker = None if os.getenv('RIG_REAL_LOCK') == '1' else Locker()
print('READY', flush=True)
GLib.MainLoop().run()
