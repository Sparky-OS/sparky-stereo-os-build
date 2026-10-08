import re,sys
from pathlib import Path
case=sys.argv[1]; root=Path(sys.argv[2] if len(sys.argv)>2 else 'work/runtime-'+case)
ready=float((root/'ready-real-time').read_text())
power=(root/'powerdevil.log').read_text(); dpms=(root/'dpms.log').read_text(); logind=(root/'logind.log').read_text()
assert 'SUPPORTED 1' in dpms,'native DPMS unsupported'
offs=re.findall(r'^DPMS (\d+) 3 (\S+) (\d+)$',dpms,re.M)
assert len(offs)==1,offs
off=float(offs[0][2])/1000
expected_off={'desktop':165,'laptop':165,'battery':20,'eco':5}[case]
assert expected_off-1 <= off-ready <= expected_off+4,(case,'off',off-ready)
locks=[float(x) for x in re.findall(r'^([\d.]+) SetLockedHint True$',logind,re.M)]
assert len(locks)==1,locks
assert ready+expected_off-1 <= locks[0] <= off,(case,'lock',locks[0]-ready,off-ready)
sleeps=[float(x) for x in re.findall(r'^([\d.]+) Suspend True$',logind,re.M)]
assert not re.search(r'^([\d.]+) (Hibernate|HybridSleep|SuspendThenHibernate) ',logind,re.M)
if case=='desktop': assert not sleeps,sleeps
else:
 expected_sleep={'laptop':240,'battery':30,'eco':10}[case]
 assert len(sleeps)==1,sleeps
 assert expected_sleep-1 <= sleeps[0]-ready <= expected_sleep+4,(case,'sleep',sleeps[0]-ready)
 assert sleeps[0]>off
assert 'No suitable displays detected. Brightness controls are unsupported' in power
profile={'desktop':'AC','laptop':'AC','battery':'Battery','eco':'LowBattery'}[case]
assert f'DPMS: registering idle timeout after {expected_off*60000}ms' in power
print(f'PASS {case}: off={off-ready:.3f}s lock={locks[0]-ready:.3f}s sleeps={[round(t-ready,3) for t in sleeps]}; native 60x idle timeline and lock ordering')
