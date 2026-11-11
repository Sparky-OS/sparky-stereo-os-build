#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Campos Ramos <Capitain_Jack@yahoo.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Isolated UMS API and strict UPnP renderers for the controller's wire tests."""
import json
import socket
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from xml.etree import ElementTree as ET
from xml.sax.saxutils import escape

STATES = {str(n): dict(status='STOPPED', position='0:00:00', volume=30, uri='') for n in (1, 2, 3)}
CALLS = []
MODE = 'normal'
ACTIONS = {'AVTransport': ['GetTransportInfo', 'GetPositionInfo', 'Play', 'Pause', 'Stop', 'Seek'],
           'RenderingControl': ['GetVolume', 'SetVolume', 'SetBrightness']}


def response(kind, action, values):
    body = ''.join(f'<{k}>{escape(str(v))}</{k}>' for k, v in values.items())
    return ('<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body>'
            f'<u:{action}Response xmlns:u="urn:schemas-upnp-org:service:{kind}:3">{body}</u:{action}Response>'
            '</s:Body></s:Envelope>').encode()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send(self, data, status=200, content='application/json'):
        if not isinstance(data, bytes):
            data = json.dumps(data).encode()
        self.send_response(status)
        self.send_header('Content-Type', content)
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        global MODE
        if self.path.startswith('/mode/'):
            MODE = self.path.split('/')[-1]
            return self.send({})
        if self.path == '/records':
            return self.send({'calls': CALLS, 'states': STATES})
        if self.path == '/v1/api/renderers/':
            if MODE == 'auth' and self.headers.get('Authorization') != 'Bearer proof-only':
                return self.send({}, 403)
            return self.send({'renderers': [
                {'id': 1, 'uuid': 'ums-94-headset', 'name': 'Flat Headset 94', 'isActive': True, 'isAllowed': True},
                {'id': 2, 'uuid': 'ums-94-tv', 'name': 'Proof TV', 'isActive': True, 'isAllowed': True},
                {'id': 3, 'uuid': 'ums-94-limited', 'name': 'Limited TV', 'isActive': True, 'isAllowed': True},
                {'id': 4, 'uuid': 'ums-94-blocked', 'name': 'Blocked TV', 'isActive': True, 'isAllowed': False}]})
        if self.path.startswith('/device/'):
            n = self.path.split('/')[-1]
            uuid = {'1': 'ums-94-headset', '2': 'ums-94-tv', '3': 'ums-94-limited'}[n]
            body = f'<root xmlns="urn:schemas-upnp-org:device-1-0"><device><UDN>uuid:{uuid}</UDN><serviceList>'
            for kind in ACTIONS:
                body += (f'<service><serviceType>urn:schemas-upnp-org:service:{kind}:3</serviceType>'
                         f'<controlURL>/control/{n}/{kind}</controlURL><SCPDURL>/scpd/{n}/{kind}</SCPDURL></service>')
            return self.send((body + '</serviceList></device></root>').encode(), content='text/xml')
        if self.path.startswith('/scpd/'):
            _, _, n, kind = self.path.split('/')
            actions = ACTIONS[kind]
            if n == '3':
                actions = [a for a in actions if a not in ('Pause', 'Seek', 'SetBrightness')]
            body = '<scpd xmlns="urn:schemas-upnp-org:service-1-0"><actionList>'
            body += ''.join(f'<action><name>{a}</name></action>' for a in actions)
            return self.send((body + '</actionList></scpd>').encode(), content='text/xml')
        self.send({}, 404)

    def do_POST(self):
        raw = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        if self.path.startswith('/v1/api/'):
            data = json.loads(raw)
            CALLS.append({'path': self.path, 'data': data})
            if self.path == '/v1/api/auth/login':
                return self.send({'token': 'proof-only'} if data == {'username': 'proof', 'password': 'proof'} else {},
                                 200 if data == {'username': 'proof', 'password': 'proof'} else 403)
            if self.path == '/v1/api/renderers/browse':
                n, media = str(data['id']), data['media']
                assert n in STATES, data
                if media == '0':
                    items = [{'value': n + '-folder', 'label': 'media', 'browsable': True}]
                elif media == n + '-folder':
                    items = [{'value': n + '-clip', 'label': 'clip.mkv', 'browsable': False}]
                    if MODE == 'ambiguous':
                        items.append({'value': n + '-other', 'label': 'clip', 'browsable': False})
                else:
                    items = []
                return self.send({'childrens': items})
            if self.path == '/v1/api/renderers/control':
                n = str(data['id'])
                assert data['action'] == 'mediaid' and data['value'] == n + '-clip', data
                STATES[n]['uri'] = f'http://127.0.0.1:19494/ums/media/renderer-{n}/clip.mkv'
                return self.send({})
            return self.send({}, 404)
        _, _, n, kind = self.path.split('/')
        action = self.headers['SOAPACTION'].strip('"').split('#')[-1]
        tree = ET.fromstring(raw)
        element = list(list(tree)[0])[0]
        assert element.tag == f'{{urn:schemas-upnp-org:service:{kind}:3}}{action}', element.tag
        names = [e.tag for e in element]
        args = {e.tag: e.text for e in element}
        expected = {'Seek': ['InstanceID', 'Unit', 'Target'], 'Play': ['InstanceID', 'Speed'],
                    'GetVolume': ['InstanceID', 'Channel'], 'SetVolume': ['InstanceID', 'Channel', 'DesiredVolume'],
                    'SetBrightness': ['InstanceID', 'DesiredBrightness']}.get(action, ['InstanceID'])
        assert names == expected and args['InstanceID'] == '0', (action, names)
        CALLS.append({'renderer': n, 'action': action, 'arguments': args})
        state = STATES[n]
        if MODE == 'fault' and action == 'Play':
            return self.send(b'<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><s:Fault><detail><errorCode>701</errorCode><errorDescription>Transition unavailable</errorDescription></detail></s:Fault></s:Body></s:Envelope>', 500, 'text/xml')
        if action in ('Play', 'Pause', 'Stop'):
            state['status'] = {'Play': 'PLAYING', 'Pause': 'PAUSED_PLAYBACK', 'Stop': 'STOPPED'}[action]
        if action == 'Seek':
            assert args['Unit'] == 'REL_TIME'
            state['position'] = args['Target']
        if action == 'SetVolume':
            assert args['Channel'] == 'Master'
            state['volume'] = int(args['DesiredVolume'])
        values = {}
        if action == 'GetTransportInfo':
            values = {'CurrentTransportState': state['status'], 'CurrentTransportStatus': 'OK', 'CurrentSpeed': '1'}
        if action == 'GetPositionInfo':
            values = {'Track': '1', 'TrackDuration': '0:02:00', 'TrackURI': state['uri'], 'RelTime': state['position']}
        if action == 'GetVolume':
            values = {'CurrentVolume': state['volume']}
        self.send(response(kind, action, values), content='text/xml')


def ssdp():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(('', 1900))
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, socket.inet_aton('239.255.255.250') + socket.inet_aton(socket.gethostbyname(socket.gethostname())))
    while True:
        data, address = sock.recvfrom(65536)
        if data.startswith(b'M-SEARCH'):
            for n, uuid in [('1', 'ums-94-headset'), ('2', 'ums-94-tv'), ('3', 'ums-94-limited')]:
                answer = (f'HTTP/1.1 200 OK\r\nLOCATION: http://127.0.0.1:19494/device/{n}\r\n'
                          f'USN: uuid:{uuid}::urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n')
                sock.sendto(answer.encode(), address)


threading.Thread(target=ssdp, daemon=True).start()
server = ThreadingHTTPServer(('127.0.0.1', 19494), Handler)
print('READY', flush=True)
server.serve_forever()
