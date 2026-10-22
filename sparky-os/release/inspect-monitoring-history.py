#!/usr/bin/env python3
"""Read local monitoring history; retain observations without causal claims."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo
import json
import statistics
import subprocess
import urllib.parse
import urllib.request
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'config'))
import local_config as cfg

zone = ZoneInfo('America/Sao_Paulo')
out = cfg.path('SPARKY_RUN_RECORD') / 'monitoring-history'
out.mkdir(exist_ok=True)
now = datetime.now(zone)
raw = subprocess.check_output([
    'sudo', '-n', 'journalctl', '_PID=1', '--no-pager',
    '-g', 'Startup finished in', '-o', 'json'], text=True)
(out / 'boot-journal.jsonl').write_text(raw)
boots = [json.loads(line) for line in raw.splitlines()]
boot_rows = [dict(boot_id=row['_BOOT_ID'],
    recorded_at=datetime.fromtimestamp(int(row['__REALTIME_TIMESTAMP'])/1e6, zone).isoformat(),
    message=row['MESSAGE']) for row in boots]
(out / 'boots.json').write_text(json.dumps(boot_rows, indent=2)+'\n')
windows = []
for day in range(14, 21):
    start = datetime(2026, 10, day, tzinfo=zone)
    end = min(start + timedelta(days=1), now)
    windows.append((f'day-{day}', int(start.timestamp()), int(end.timestamp())))
for label, day, hour, minute, second in [
    ('previous-boot-first-hour', 15, 4, 5, 18),
    ('current-boot-first-hour', 17, 15, 25, 30)]:
    start = datetime(2026, 10, day, hour, minute, second, tzinfo=zone)
    windows.append((label, int(start.timestamp()), int((start+timedelta(hours=1)).timestamp())))
charts = ['system.cpu', 'system.load', 'system.io', 'system.memory_some_pressure',
          'system.io_some_pressure', 'system.cpu_some_pressure', 'system.ram', 'system.uptime']

def fetch(task):
    (label, start, end), chart = task
    params = dict(chart=chart, after=start, before=end,
                  points=max(12, (end-start)//300), format='json', group='average')
    url = 'http://127.0.0.1:19999/api/v1/data?' + urllib.parse.urlencode(params)
    with urllib.request.urlopen(url, timeout=30) as response:
        data = json.load(response)
    (out / f'{label}-{chart}.json').write_text(json.dumps(data)+'\n')
    metrics = {}
    for index, name in enumerate(data['labels'][1:], 1):
        values = [row[index] for row in data['data'] if row[index] is not None]
        metrics[name] = dict(samples=len(values), mean=statistics.mean(values) if values else None,
                             median=statistics.median(values) if values else None,
                             maximum=max(values) if values else None)
    if chart == 'system.cpu':
        indexes = [i for i, name in enumerate(data['labels']) if name in ('user','system','nice','irq','softirq','steal')]
        values = [sum(row[i] for i in indexes) for row in data['data'] if all(row[i] is not None for i in indexes)]
        metrics['busy_excluding_iowait'] = dict(samples=len(values), mean=statistics.mean(values) if values else None)
    return dict(window=label, after=start, before=end, chart=chart, metrics=metrics,
                received_rows=len(data['data']), source=url)

with ThreadPoolExecutor(max_workers=3) as pool:
    rows = list(pool.map(fetch, [(w, c) for w in windows for c in charts]))
(out / 'summary.json').write_text(json.dumps(dict(
    captured_at=now.isoformat(), averaging='Approximately five-minute bucket averages; means of returned buckets',
    limitations='Observational history, different workloads and incomplete startup coverage. Not an A/B benchmark or attribution to Lean Code.',
    rows=rows), indent=2)+'\n')
for label, _, _ in windows:
    subset = {row['chart']: row for row in rows if row['window']==label}
    def value(chart, metric):
        entry = subset[chart]['metrics'].get(metric, {})
        result = entry.get('mean')
        return round(result, 3) if result is not None else None
    print(json.dumps(dict(window=label,
        cpu_busy=value('system.cpu','busy_excluding_iowait'),
        iowait=value('system.cpu','iowait'),
        load1=value('system.load','load1'),
        memory_pressure=value('system.memory_some_pressure','some 10'),
        io_pressure=value('system.io_some_pressure','some 10'),
        cpu_pressure=value('system.cpu_some_pressure','some 10'),
        read_KiB_s=value('system.io','reads'), write_KiB_s=value('system.io','writes'),
        cpu_samples=subset['system.cpu']['metrics'].get('user',{}).get('samples'))))
print('Retained evidence:', out)
