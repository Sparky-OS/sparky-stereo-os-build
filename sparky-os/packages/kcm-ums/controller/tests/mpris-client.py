#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
import dbus
import json
import sys
bus = dbus.SessionBus()
names = [str(n) for n in bus.list_names() if str(n).startswith('org.mpris.MediaPlayer2.ums_renderer_')]
assert len(names) == 1, names
obj = bus.get_object(names[0], '/org/mpris/MediaPlayer2')
player = dbus.Interface(obj, 'org.mpris.MediaPlayer2.Player')
props = dbus.Interface(obj, 'org.freedesktop.DBus.Properties')
interface = 'org.mpris.MediaPlayer2.Player'
mode = sys.argv[1]
if mode == 'controls':
    assert props.Get(interface, 'PlaybackStatus') == 'Playing'
    assert props.Get(interface, 'CanSeek')
    player.Pause()
    assert props.Get(interface, 'PlaybackStatus') == 'Paused'
    player.Play()
    player.Seek(dbus.Int64(15000000))
    assert props.Get(interface, 'Position') == 15000000
    metadata = props.Get(interface, 'Metadata')
    player.SetPosition(metadata['mpris:trackid'], dbus.Int64(30000000))
    assert props.Get(interface, 'Position') == 30000000
    player.SetPosition(dbus.ObjectPath('/stale'), dbus.Int64(50000000))
    assert props.Get(interface, 'Position') == 30000000
    props.Set(interface, 'Volume', dbus.Double(0.57))
    assert abs(props.Get(interface, 'Volume') - .57) < .001
    player.Stop()
    assert props.Get(interface, 'PlaybackStatus') == 'Stopped'
elif mode == 'limited':
    assert not props.Get(interface, 'CanSeek')
    assert not props.Get(interface, 'CanPause')
elif mode == 'fault':
    try:
        player.Play()
    except dbus.DBusException as error:
        assert '701' in str(error), str(error)
    else:
        raise AssertionError('SOAP fault was acknowledged as success')
print(json.dumps({'pass': mode, 'name': names[0]}))
