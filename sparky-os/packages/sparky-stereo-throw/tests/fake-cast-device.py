#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-2.0-or-later
"""A software Cast device for the loopback proof of sparky-stereo-throw; never pointed at a real network.

Grown from the cast study's receiver (row 81's study, skills/stereo-serving/scripts/cast-handshake/receiver.py): the
CASTv2 channel (TLS, each message a 4-byte big-endian length and a CastMessage from pychromecast's generated module) with
the connection, heartbeat, receiver and media namespaces. Added for the proof:
- on LOAD it fetches the URL it was told with ffmpeg (-c copy into capture.mkv) the way a device's player would, and
  logs what ffprobe reads from it;
- /setup/eureka_info on HTTPS 8443 and HTTP 8008, answered without any account for params device_info, name and
  build_info (the read pychromecast 14.1.1 dial.py makes); any other /setup path answers 401, as a device that wants
  its cast-local-authorization-token;
- SET_VOLUME on the receiver namespace changes and reports the volume;
- modes for the red rows: launch-error (LAUNCH answered with LAUNCH_ERROR), load-failed (LOAD answered with
  LOAD_FAILED), no-pong (the heartbeat goes unanswered).
Every message and event is a JSON line in the log.

Usage: fake-cast-device.py --bind ADDR --log FILE --cert PEM --key PEM --out DIR [--mode MODE] [--name N] [--model M]
"""
import argparse
import http.server
import json
import socket
import ssl
import struct
import subprocess
import threading
import time

from pychromecast.generated import cast_channel_pb2 as pb

NS_CONNECTION = "urn:x-cast:com.google.cast.tp.connection"
NS_HEARTBEAT = "urn:x-cast:com.google.cast.tp.heartbeat"
NS_RECEIVER = "urn:x-cast:com.google.cast.receiver"
NS_MEDIA = "urn:x-cast:com.google.cast.media"
APP_DMR = "CC1AD845"
TRANSPORT_ID = "web-1"

args = None
log_lock = threading.Lock()
stop_event = threading.Event()


def log(entry):
    entry["t"] = round(time.time(), 3)
    with log_lock:
        with open(args.log, "a") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")


class Session:
    def __init__(self):
        self.app_running = False
        self.session_id = "7E2F0E77-0000-0000-0000-000000000081"
        self.media = None
        self.volume = {"controlType": "attenuation", "level": 0.5, "muted": False, "stepInterval": 0.05}
        self.lock = threading.Lock()

    def receiver_status(self, request_id):
        apps = []
        if self.app_running:
            apps.append({"appId": APP_DMR, "displayName": "Default Media Receiver", "isIdleScreen": False,
                         "namespaces": [{"name": NS_MEDIA}], "sessionId": self.session_id,
                         "statusText": "Default Media Receiver", "transportId": TRANSPORT_ID, "universalAppId": APP_DMR})
        return {"requestId": request_id, "type": "RECEIVER_STATUS",
                "status": {"applications": apps, "isActiveInput": True, "isStandBy": False, "volume": dict(self.volume)}}

    def media_status(self, request_id, state="PLAYING", idle_reason=None):
        status = []
        if self.media is not None:
            entry = {"mediaSessionId": 1, "playbackRate": 1, "playerState": state, "currentTime": 0.0,
                     "supportedMediaCommands": 274447, "media": self.media}
            if idle_reason:
                entry["idleReason"] = idle_reason
            status.append(entry)
        return {"type": "MEDIA_STATUS", "requestId": request_id, "status": status}


def send(conn, src, dst, ns, payload):
    msg = pb.CastMessage()
    msg.protocol_version = msg.CASTV2_1_0
    msg.source_id = src
    msg.destination_id = dst
    msg.namespace = ns
    msg.payload_type = msg.STRING
    msg.payload_utf8 = json.dumps(payload)
    data = msg.SerializeToString()
    conn.sendall(struct.pack(">I", len(data)) + data)
    log({"dir": "send", "src": src, "dst": dst, "ns": ns, "payload": payload})


def read_exact(conn, n):
    buf = b""
    while len(buf) < n:
        chunk = conn.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("peer closed")
        buf += chunk
    return buf


fetches = [0]


def fetch(url):
    """What a device's player does: fetch the live stream; kept (capture-N.mkv, one per LOAD) for ffprobe and frames."""
    fetches[0] += 1
    out = f"{args.out}/capture-{fetches[0]}.mkv"
    log({"event": "fetch-start", "url": url, "file": out})
    proc = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-rw_timeout", "15000000", "-i", url,
                           "-c", "copy", "-t", str(args.capture_seconds), out], capture_output=True, text=True)
    log({"event": "fetch-end", "status": proc.returncode, "stderr": proc.stderr[-400:]})
    probe = subprocess.run(["ffprobe", "-v", "error", "-show_streams", "-show_format", "-count_frames", "-of", "json", out],
                           capture_output=True, text=True)
    try:
        info = json.loads(probe.stdout)
    except json.JSONDecodeError:
        info = {"error": probe.stderr[-400:]}
    log({"event": "probe", "file": out, "info": info})


def handle(conn, peer, session):
    log({"event": "tls-accepted", "peer": peer[0], "tls": conn.version()})
    try:
        while not stop_event.is_set():
            (length,) = struct.unpack(">I", read_exact(conn, 4))
            msg = pb.CastMessage()
            msg.ParseFromString(read_exact(conn, length))
            if msg.payload_type == msg.BINARY:
                log({"dir": "recv", "ns": msg.namespace, "binary_bytes": len(msg.payload_binary)})
                continue
            payload = json.loads(msg.payload_utf8)
            log({"dir": "recv", "src": msg.source_id, "dst": msg.destination_id, "ns": msg.namespace, "payload": payload})
            mtype = payload.get("type")
            rid = payload.get("requestId", 0)
            if msg.namespace == NS_HEARTBEAT and mtype == "PING":
                if args.mode != "no-pong":
                    send(conn, msg.destination_id, msg.source_id, NS_HEARTBEAT, {"type": "PONG"})
            elif msg.namespace == NS_CONNECTION and mtype == "CLOSE":
                if msg.destination_id == "receiver-0":
                    log({"event": "sender-closed-channel"})
                    return
            elif msg.namespace == NS_RECEIVER and mtype == "GET_STATUS":
                send(conn, "receiver-0", msg.source_id, NS_RECEIVER, session.receiver_status(rid))
            elif msg.namespace == NS_RECEIVER and mtype == "LAUNCH":
                log({"event": "launch", "appId": payload.get("appId")})
                if payload.get("appId") == APP_DMR and args.mode != "launch-error":
                    session.app_running = True
                    send(conn, "receiver-0", msg.source_id, NS_RECEIVER, session.receiver_status(rid))
                else:
                    send(conn, "receiver-0", msg.source_id, NS_RECEIVER, {"requestId": rid, "type": "LAUNCH_ERROR", "reason": "NOT_FOUND"})
            elif msg.namespace == NS_RECEIVER and mtype == "STOP":
                log({"event": "stop", "sessionId": payload.get("sessionId")})
                session.app_running = False
                session.media = None
                send(conn, "receiver-0", msg.source_id, NS_RECEIVER, session.receiver_status(rid))
            elif msg.namespace == NS_RECEIVER and mtype == "SET_VOLUME":
                vol = payload.get("volume", {})
                with session.lock:
                    if "level" in vol:
                        session.volume["level"] = max(0.0, min(1.0, float(vol["level"])))
                    if "muted" in vol:
                        session.volume["muted"] = bool(vol["muted"])
                send(conn, "receiver-0", msg.source_id, NS_RECEIVER, session.receiver_status(rid))
            elif msg.namespace == NS_MEDIA and mtype == "LOAD":
                session.media = payload.get("media")
                log({"event": "load", "contentId": session.media.get("contentId"), "contentType": session.media.get("contentType"),
                     "streamType": session.media.get("streamType")})
                if args.mode == "load-failed":
                    send(conn, TRANSPORT_ID, msg.source_id, NS_MEDIA, {"type": "LOAD_FAILED", "requestId": rid})
                    continue
                send(conn, TRANSPORT_ID, msg.source_id, NS_MEDIA, session.media_status(rid, "BUFFERING"))
                threading.Thread(target=fetch, args=(session.media.get("contentId"),), daemon=True).start()
                send(conn, TRANSPORT_ID, msg.source_id, NS_MEDIA, session.media_status(0, "PLAYING"))
            elif msg.namespace == NS_MEDIA and mtype == "GET_STATUS":
                send(conn, TRANSPORT_ID, msg.source_id, NS_MEDIA, session.media_status(rid))
            else:
                log({"event": "unhandled", "ns": msg.namespace, "type": mtype})
    except (ConnectionError, ssl.SSLError, OSError, json.JSONDecodeError) as exc:
        log({"event": "connection-ended", "error": str(exc)})
    finally:
        try:
            conn.close()
        except OSError:
            pass


class Eureka(http.server.BaseHTTPRequestHandler):
    """The device's own HTTP setup interface, as far as it answers without the person's account."""

    def do_GET(self):
        path, _, query = self.path.partition("?")
        params = dict(p.split("=", 1) for p in query.split("&") if "=" in p)
        log({"event": "eureka", "secure": isinstance(self.connection, ssl.SSLSocket), "path": path, "query": query,
             "host": self.headers.get("Host"), "token": bool(self.headers.get("cast-local-authorization-token"))})
        if path != "/setup/eureka_info":
            self.send_response(401)
            self.end_headers()
            return
        wanted = params.get("params", "").split(",")
        body = {}
        if "name" in wanted:
            body["name"] = args.name
        if "device_info" in wanted:
            body["device_info"] = {"name": args.name, "model_name": args.model, "manufacturer": "Google Inc.",
                                   "ssdp_udn": args.udn, "capabilities": {"display_supported": True, "multizone_supported": False}}
        if "build_info" in wanted:
            body["build_info"] = {"cast_build_revision": "1.56.500000", "system_build_number": "500000", "release_track": "stable-channel"}
        data = json.dumps(body).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *a):
        pass


def serve_eureka():
    plain = http.server.ThreadingHTTPServer((args.bind, 8008), Eureka)
    secure = http.server.ThreadingHTTPServer((args.bind, 8443), Eureka)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(args.cert, args.key)
    secure.socket = ctx.wrap_socket(secure.socket, server_side=True)
    for server in (plain, secure):
        threading.Thread(target=server.serve_forever, daemon=True).start()


def main():
    global args
    parser = argparse.ArgumentParser()
    parser.add_argument("--bind", required=True)
    parser.add_argument("--log", required=True)
    parser.add_argument("--cert", required=True)
    parser.add_argument("--key", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--mode", default="normal", choices=["normal", "launch-error", "load-failed", "no-pong"])
    parser.add_argument("--name", default="Living room TV")
    parser.add_argument("--model", default="Chromecast")
    parser.add_argument("--udn", default="5d7a9c4e-81ab-4c3d-9e2f-000000000081")
    parser.add_argument("--capture-seconds", type=int, default=30)
    parser.add_argument("--seconds", type=int, default=300)
    args = parser.parse_args()
    serve_eureka()
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(args.cert, args.key)
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((args.bind, 8009))
    srv.listen(8)
    srv.settimeout(1.0)
    log({"event": "listening", "addr": f"{args.bind}:8009", "mode": args.mode, "model": args.model})
    session = Session()
    deadline = time.monotonic() + args.seconds
    while time.monotonic() < deadline:
        try:
            raw, peer = srv.accept()
        except socket.timeout:
            continue
        try:
            conn = ctx.wrap_socket(raw, server_side=True)
        except ssl.SSLError as exc:
            log({"event": "tls-failed", "error": str(exc)})
            continue
        threading.Thread(target=handle, args=(conn, peer, session), daemon=True).start()
    log({"event": "device-exit"})


if __name__ == "__main__":
    main()
