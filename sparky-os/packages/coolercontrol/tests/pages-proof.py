#!/usr/bin/python3
# Created by Daniel Ramos (Capitain Jack) 2026/11/18
# Copyright 2026 under the GNU GPL3 License
"""Every page of the interface opened in a browser against the running daemon, and what each one shows.

Run inside the proof container with chromium and python3-websockets installed, the daemon up on 127.0.0.1:11987 (the recorded machine mounted over
/sys/class/hwmon). Usage: pages-proof.py OUTDIR. The browser is driven over its DevTools protocol: it logs in (the interface's own login form is not
used: the daemon's /login with the default password sets the session cookie, as the form does), opens each route of the interface (hash routes, the ones with
a device, a channel, a profile, a function, a mode, a dashboard or an alert filled in from the daemon's own answers), waits for the page to settle, and
records for each the visible text length, the number of page errors and console errors, and a screenshot. A route that shows no text, or a page error,
is a FAIL. Exit status 0 only when every route passes."""
import asyncio, base64, json, os, subprocess, sys, time, urllib.request
import websockets

OUT = sys.argv[1]; os.makedirs(OUT, exist_ok=True)
BASE = 'http://127.0.0.1:11987'


COOKIE = ''


PASS = 'ProofPass-2026'


def login_as(password):
    req = urllib.request.Request(BASE + '/login', method='POST', headers={'Authorization': 'Basic ' + base64.b64encode(('CCAdmin:' + password).encode()).decode()})
    return urllib.request.urlopen(req, timeout=20).headers.get('Set-Cookie', '').split(';')[0]


def set_password():
    # a first start has the default password and the interface then asks for a new one (a dialog over every page): set one, as a person does
    try:
        cookie = login_as('coolAdmin')
    except urllib.error.HTTPError:
        return  # a password was set by an earlier run
    req = urllib.request.Request(BASE + '/set-passwd', method='POST', data=json.dumps({'current_password': 'coolAdmin'}).encode(),
                                 headers={'Content-Type': 'application/json', 'Cookie': cookie, 'Authorization': 'Basic ' + base64.b64encode(('CCAdmin:' + PASS).encode()).decode()})
    try:
        urllib.request.urlopen(req, timeout=20)
    except urllib.error.HTTPError as e:
        print('set-passwd:', e.code, e.read()[:100])


def login():
    global COOKIE
    req = urllib.request.Request(BASE + '/login', method='POST', headers={'Authorization': 'Basic ' + base64.b64encode(('CCAdmin:' + PASS).encode()).decode()})
    resp = urllib.request.urlopen(req, timeout=20)
    COOKIE = resp.headers.get('Set-Cookie', '').split(';')[0]


def api(path, method='GET', body=None):
    req = urllib.request.Request(BASE + path, method=method, data=None if body is None else json.dumps(body).encode(), headers={'Content-Type': 'application/json', 'Cookie': COOKIE})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read() or b'null')


set_password()
login()
devices = api('/devices')['devices']
profiles = api('/profiles')['profiles']
functions = api('/functions')['functions']
modes = api('/modes')['modes']
routes = ['home', 'home/logs', 'cooling', 'cooling/modes', 'monitoring', 'monitoring/alerts', 'monitoring/alerts/new', 'devices', 'devices/manage-sensors',
          'controls', 'app-info', 'settings', 'settings/0', 'settings/1', 'settings/2', 'dashboards', 'alerts-overview', 'custom-sensors', 'plugins-overview']
for m in modes[:1]:
    routes.append(f"modes/{m['uid']}")
for p in profiles[:3]:
    routes.append(f"profiles/{p['uid']}")
for f in functions[:2]:
    routes.append(f"functions/{f['uid']}")
for d in devices:
    routes.append(f"devices/{d['uid']}")
    for name, ch in (d.get('info') or {}).get('channels', {}).items():
        routes.append(f"controls/{d['uid']}/{name}")
        routes.append(f"cooling/{d['uid']}/{name}")
        routes.append(f"monitoring/sensors/{d['uid']}/{name}")
        break
print(f'{len(routes)} routes from {len(devices)} devices, {len(profiles)} profiles, {len(functions)} functions, {len(modes)} modes')

chrome = subprocess.Popen(['chromium', '--headless=new', '--no-sandbox', '--disable-gpu', '--remote-debugging-port=9333', '--window-size=1400,900', '--user-data-dir=/tmp/chrome-proof', 'about:blank'],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


async def main():
    for _ in range(60):
        try:
            tabs = json.loads(urllib.request.urlopen('http://127.0.0.1:9333/json').read()); break
        except Exception:
            time.sleep(0.5)
    ws_url = [t for t in tabs if t['type'] == 'page'][0]['webSocketDebuggerUrl']
    results = []
    async with websockets.connect(ws_url, max_size=2**26) as ws:
        counter = [0]
        errors = []

        async def call(method, **params):
            counter[0] += 1; i = counter[0]
            await ws.send(json.dumps({'id': i, 'method': method, 'params': params}))
            while True:
                msg = json.loads(await ws.recv())
                if msg.get('id') == i:
                    return msg.get('result', {})
                if msg.get('method') == 'Runtime.exceptionThrown':
                    errors.append(msg['params']['exceptionDetails'].get('text', '') + ' ' + str(msg['params']['exceptionDetails'].get('exception', {}).get('description', ''))[:200])
                if msg.get('method') == 'Runtime.consoleAPICalled' and msg['params']['type'] == 'error':
                    errors.append('console: ' + ' '.join(str(a.get('value', a.get('description', ''))) for a in msg['params']['args'])[:200])
        await call('Runtime.enable'); await call('Page.enable'); await call('Network.enable')
        # the session cookie, as the interface's login form obtains it
        name, _, value = COOKIE.partition('=')
        if name:
            await call('Network.setCookie', name=name, value=value, url=BASE + '/')
        for n, route in enumerate(routes):
            errors.clear()
            await call('Page.navigate', url=f'{BASE}/#/{route}')
            await asyncio.sleep(4)
            text = (await call('Runtime.evaluate', expression='document.body.innerText.length', returnByValue=True)).get('result', {}).get('value', 0)
            title = (await call('Runtime.evaluate', expression="(document.querySelector('h1,h2,[class*=title]')||{}).innerText||''", returnByValue=True)).get('result', {}).get('value', '')
            shot = await call('Page.captureScreenshot', format='png')
            open(os.path.join(OUT, f'{n:02d}-' + route.replace('/', '_')[:60] + '.png'), 'wb').write(base64.b64decode(shot['data']))
            ok = text > 40 and not [e for e in errors if 'console: ' not in e]
            results.append((route, text, len(errors), ok))
            print(('PASS' if ok else 'FAIL'), route, f'text={text}', f'errors={len(errors)}', repr(title)[:50], errors[:2])
    return results

res = asyncio.run(main())
chrome.terminate()
bad = [r for r in res if not r[3]]
print(f'{len(res) - len(bad)} of {len(res)} routes pass')
sys.exit(1 if bad else 0)
