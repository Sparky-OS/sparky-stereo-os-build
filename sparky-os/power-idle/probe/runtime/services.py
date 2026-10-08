import os, signal, time, subprocess
from pathlib import Path
import dbus, dbusmock
from dbusmock import DBusTestCase, MOCK_IFACE
case=os.environ['TIMELINE_CASE']
logs=Path(os.environ['TIMELINE_RUN']); logs.mkdir(exist_ok=True)
children=[]
try:
    f=open(logs/'logind.log','w')
    proc, manager=DBusTestCase.spawn_server_template('logind', {'CanHibernate':'no', 'CanHybridSleep':'no', 'CanSuspendThenHibernate':'no'}, stdout=f)
    children.append(proc)
    session=manager.AddSession('timeline','seat0',dbus.UInt32(os.getuid()),'fixture',True,dbus_interface=MOCK_IFACE)
    manager.AddMethods('org.freedesktop.login1.Manager',[
        ('GetSession','s','o',f'ret = "{session}"'),
        ('GetSessionByPID','u','o',f'ret = "{session}"'),
    ],dbus_interface=MOCK_IFACE)
    battery=case in ('battery','eco')
    lid=case!='desktop'
    f=open(logs/'upower.log','w')
    proc, upower=DBusTestCase.spawn_server_template('upower', {'OnBattery':battery,'LidIsPresent':lid,'LidIsClosed':False}, stdout=f)
    children.append(proc)
    if lid:
        percent=8 if case=='eco' else 70
        upower.AddDischargingBattery('BAT0','fixture',float(percent),dbus.Int64(3600),dbus_interface=MOCK_IFACE)
        bus=DBusTestCase.get_dbus(True)
        display=bus.get_object('org.freedesktop.UPower','/org/freedesktop/UPower/devices/DisplayDevice')
        display.AddProperties('org.freedesktop.UPower.Device',{'PowerSupply':True,'UpdateTime':dbus.UInt64(int(time.time()))},dbus_interface=MOCK_IFACE)
        display.UpdateProperties('org.freedesktop.UPower.Device',{
            'Type':dbus.UInt32(2),'State':dbus.UInt32(2),'Percentage':dbus.Double(percent),
            'Energy':dbus.Double(percent),'EnergyFull':dbus.Double(100),'EnergyRate':dbus.Double(10),
            'IsPresent':True,'PowerSupply':True,'UpdateTime':dbus.UInt64(int(time.time())),
        },dbus_interface=MOCK_IFACE)
    print('READY private logind and UPower',flush=True)
    signal.signal(signal.SIGTERM,lambda *_:exit(0))
    while True: signal.pause()
finally:
    for proc in children:
        proc.terminate()
        try: proc.wait(timeout=2)
        except subprocess.TimeoutExpired: proc.kill()
