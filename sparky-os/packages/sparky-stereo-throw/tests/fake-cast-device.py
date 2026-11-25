#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-2.0-or-later
"""A software Cast device for the loopback proof of sparky-stereo-throw; never pointed at a real network.

Grown from the cast study's receiver (row 81's study, skills/stereo-serving/scripts/cast-handshake/receiver.py): the
CASTv2 channel (TLS, each message a 4-byte big-endian length and a CastMessage from pychromecast's generated module) with
the connection, heartbeat, receiver and media namespaces. Added for the proof:
- on LOAD it fetches the URL it was told over HTTP from its own address, the way a device's player would, keeps the bytes
  as they came (capture-N.<container>) and logs what ffprobe reads from them;
- /setup/eureka_info on HTTPS 8443 and HTTP 8008, answered without any account for params device_info, name and
  build_info (the read pychromecast 14.1.1 dial.py makes); any other /setup path answers 401, as a device that wants
  its cast-local-authorization-token;
- SET_VOLUME on the receiver namespace changes and reports the volume;
- modes for the red rows: launch-error (LAUNCH answered with LAUNCH_ERROR), load-failed (LOAD answered with
  LOAD_FAILED), no-pong (the heartbeat goes unanswered), never-plays (it fetches the stream and stays BUFFERING), false-start (it says PLAYING once at its time 0, then BUFFERING
  at time 0 for ever, as a real Chromecast did with E-AC-3 and Vorbis).
- with --player chromium (part D) it is a receiver that plays like one: on LOAD a headless Chromium plays the stream in
  a media element (relayed from the device's own address), and the media status says what that player does: PLAYING
  only while its current time advances, BUFFERING while it waits, IDLE with ERROR or FINISHED; currentTime is the
  player's own. Without it the device says PLAYING at LOAD, which proves nothing about a real player.
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
        self.player = None
        self.loaded_at = None  # when the LOAD came: a normal device's time runs from it
        self.false_start_said = False
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
        current = 0.0
        if self.media is not None and self.player is not None:
            state, idle_reason, current = self.player.cast_state()
        elif self.media is not None and args.mode == "never-plays":
            state = "BUFFERING"
        elif self.media is not None and args.mode == "false-start":
            # as a real Chromecast did with E-AC-3 and Vorbis (row 81, part D2): PLAYING once, at its time 0, then
            # BUFFERING at time 0 for ever
            if state == "PLAYING" and not self.false_start_said:
                self.false_start_said = True
            else:
                state = "BUFFERING"
        elif self.media is not None and state == "PLAYING" and self.loaded_at is not None:
            # a playing device's time runs from its LOAD
            current = round(time.monotonic() - self.loaded_at, 2)
        if self.media is not None:
            entry = {"mediaSessionId": 1, "playbackRate": 1, "playerState": state, "currentTime": current,
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


EXT = {"video/x-matroska": "mkv", "video/mp4": "mp4", "video/webm": "webm", "audio/ogg": "ogg"}


def fetch(url, content_type):
    """What a device's player does: fetch the live stream over HTTP, from the device's own address; the bytes are kept as
    they came (capture-N.<container>, one per LOAD) for ffprobe and frames."""
    import http.client
    import time
    from urllib.parse import urlsplit
    fetches[0] += 1
    out = f"{args.out}/capture-{fetches[0]}.{EXT.get(content_type, 'bin')}"
    log({"event": "fetch-start", "url": url, "file": out})
    parts = urlsplit(url)
    status, total, error = None, 0, ""
    try:
        conn = http.client.HTTPConnection(parts.hostname, parts.port, timeout=15, source_address=(args.bind, 0))
        conn.request("GET", parts.path)
        resp = conn.getresponse()
        status = resp.status
        end = time.monotonic() + args.capture_seconds
        with open(out, "wb") as f:
            while time.monotonic() < end and not stop_event.is_set():
                chunk = resp.read1(65536)
                if not chunk:
                    break
                f.write(chunk)
                total += len(chunk)
        conn.close()
    except OSError as exc:
        error = str(exc)
    log({"event": "fetch-end", "status": status, "bytes": total, "error": error, "contentType": content_type})
    probe_file(out)


def probe_file(out):
    """What ffprobe reads from a capture, logged as the "probe" event the rows read."""
    probe = subprocess.run(["ffprobe", "-v", "error", "-show_streams", "-show_format", "-count_frames", "-of", "json", out],
                           capture_output=True, text=True)
    try:
        info = json.loads(probe.stdout)
    except json.JSONDecodeError:
        info = {"error": probe.stderr[-400:]}
    log({"event": "probe", "file": out, "info": info})


PLAYER_PAGE = """<!doctype html><html><head><meta charset="utf-8"><title>player</title></head>
<body style="margin:0;background:#000"><video id="v" autoplay playsinline style="width:100vw;height:100vh"></video>
<script>
const v = document.getElementById("v");
let waiting = false, events = [];
for (const e of ["loadstart", "loadedmetadata", "loadeddata", "canplay", "canplaythrough", "playing", "waiting", "stalled",
                 "pause", "ended", "error"]) {
  v.addEventListener(e, () => { events.push([e, Math.round(performance.now())]); if (e === "waiting") waiting = true;
                                if (e === "playing") waiting = false; });
}
v.src = "/relay";
// a screen that carries the wall clock as a code (the kit's clock page: 28 cells across the top band, white first, black
// last, 26 bits of the milliseconds mod 2^26 between them) is read back here: this machine's clock minus the code is the
// delay from the computer's screen to this player's picture; null when the picture carries no such code
const canvas = document.createElement("canvas"), g = canvas.getContext("2d", {willReadFrequently: true});
function clockLag() {
  const w = v.videoWidth, h = v.videoHeight;
  if (!w || !h || v.readyState < 2) return null;
  canvas.width = w; canvas.height = h; g.drawImage(v, 0, 0, w, h);
  const cells = 28, y = Math.round(h * 0.06), row = g.getImageData(0, y, w, 1).data, bits = [];
  for (let i = 0; i < cells; i++) {
    const x = Math.floor((i + 0.5) * w / cells) * 4;
    bits.push((row[x] + row[x + 1] + row[x + 2]) / 3 > 128 ? 1 : 0);
  }
  if (bits[0] !== 1 || bits[cells - 1] !== 0) return null;
  let value = 0;
  for (let i = 1; i < cells - 1; i++) value = value * 2 + bits[i];
  const lag = ((Date.now() % 67108864) - value + 67108864) % 67108864;
  return lag < 600000 ? lag : null;
}
function report() {
  const b = v.buffered.length ? v.buffered.end(v.buffered.length - 1) : 0;
  const body = {readyState: v.readyState, networkState: v.networkState, currentTime: v.currentTime, paused: v.paused,
    waiting, ended: v.ended, buffered: b, width: v.videoWidth, height: v.videoHeight, events: events.splice(0),
    error: v.error ? (v.error.code + " " + v.error.message) : null, clockLagMs: clockLag()};
  fetch("/report", {method: "POST", body: JSON.stringify(body)}).catch(() => {});
}
setInterval(report, 250);
</script></body></html>"""


class Player:
    """A real player for the stand-in: Debian's Chromium in headless mode plays the stream in a media element. The
    stream reaches it through the device's own relay, so the PC's server still sees the device's address."""

    def __init__(self, url, number, capture):
        # the player's own fetch is the device's one reader: the stream's server answers the newest connection of a
        # device, so a second fetch beside it would cut it; the bytes are kept as they pass (capture-N) and probed
        self.url, self.lock, self.last, self.capture, self.captured = url, threading.Lock(), {}, capture, False
        self.advanced_at, self.last_time, self.started = 0.0, None, time.monotonic()
        player = self

        class Handler(http.server.BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, *a):
                pass

            def do_GET(self):
                if self.path == "/player.html":
                    data = PLAYER_PAGE.encode()
                    self.send_response(200)
                    self.send_header("Content-Type", "text/html")
                    self.send_header("Content-Length", str(len(data)))
                    self.end_headers()
                    self.wfile.write(data)
                elif self.path == "/relay":
                    player.relay(self)
                else:
                    self.send_error(404)

            def do_POST(self):
                body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
                self.send_response(204)
                self.send_header("Content-Length", "0")
                self.end_headers()
                try:
                    player.report(json.loads(body))
                except json.JSONDecodeError:
                    pass

        self.server = http.server.ThreadingHTTPServer((args.bind, 0), Handler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        page = f"http://{args.bind}:{self.server.server_address[1]}/player.html"
        profile = f"{args.out}/chromium-{number}"
        import os
        home = f"{args.out}/chromium-home"
        os.makedirs(home, exist_ok=True)
        # Chromium needs a home it can write and no crash reporter (crashpad wants a database it cannot make here)
        self.proc = subprocess.Popen(["chromium", "--headless=new", "--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage",
                                      "--disable-crash-reporter", "--disable-breakpad", "--no-first-run",
                                      "--no-default-browser-check", "--autoplay-policy=no-user-gesture-required",
                                      f"--user-data-dir={profile}", page],
                                     stdout=subprocess.DEVNULL, stderr=open(f"{args.out}/chromium-{number}.log", "w"),
                                     env=dict(os.environ, HOME=home))
        log({"event": "player-start", "page": page, "pid": self.proc.pid})

    def relay(self, handler):
        import http.client
        from urllib.parse import urlsplit
        parts = urlsplit(self.url)
        log({"event": "player-request", "headers": {k: v for k, v in handler.headers.items() if k.lower() != "user-agent"}})
        try:
            conn = http.client.HTTPConnection(parts.hostname, parts.port, timeout=30, source_address=(args.bind, 0))
            conn.request("GET", parts.path)
            resp = conn.getresponse()
        except OSError as exc:
            log({"event": "player-relay-failed", "error": str(exc)})
            handler.send_error(502)
            return
        handler.send_response(resp.status)
        handler.send_header("Content-Type", resp.getheader("Content-Type", "application/octet-stream"))
        handler.send_header("Cache-Control", "no-cache")
        handler.send_header("Connection", "close")
        handler.end_headers()
        total = 0
        keep = None if self.captured else open(self.capture, "wb")
        self.captured = True
        try:
            while not stop_event.is_set():
                chunk = resp.read1(65536)
                if not chunk:
                    break
                if keep:
                    keep.write(chunk)
                handler.wfile.write(chunk)
                total += len(chunk)
        except OSError:
            pass
        log({"event": "player-relay-end", "bytes": total})
        conn.close()
        if keep:
            keep.close()
            log({"event": "fetch-end", "status": resp.status, "bytes": total, "error": "", "contentType": "player"})
            probe_file(self.capture)

    def report(self, state):
        now = time.monotonic()
        with self.lock:
            ct = state.get("currentTime") or 0.0
            if self.last_time is not None and ct > self.last_time + 0.01:
                self.advanced_at = now
            self.last_time = ct
            changed = {k: state.get(k) for k in ("readyState", "paused", "waiting", "error", "ended")} != \
                {k: self.last.get(k) for k in ("readyState", "paused", "waiting", "error", "ended")}
            self.last = state
        lag = state.get("clockLagMs")
        if lag is not None and now - getattr(self, "lag_logged", 0.0) >= 1.0:
            # the delay read back from a picture that carries the clock (the kit's clock page), once a second
            self.lag_logged = now
            log({"event": "clock", "t": round(now - self.started, 2), "lagMs": lag, "currentTime": state.get("currentTime")})
        if changed or state.get("events"):
            log({"event": "player", "t": round(now - self.started, 2), **{k: state.get(k) for k in
                 ("readyState", "networkState", "currentTime", "paused", "waiting", "ended", "buffered", "width", "height",
                  "error", "events")}})

    def cast_state(self):
        """The Cast player state of what the player does: PLAYING only while its time advances."""
        with self.lock:
            st, advanced = dict(self.last), time.monotonic() - self.advanced_at < 1.5
        if st.get("error"):
            return "IDLE", "ERROR", st.get("currentTime") or 0.0
        if st.get("ended"):
            return "IDLE", "FINISHED", st.get("currentTime") or 0.0
        if advanced and not st.get("paused") and not st.get("waiting"):
            return "PLAYING", None, st.get("currentTime") or 0.0
        return "BUFFERING", None, st.get("currentTime") or 0.0

    def stop(self):
        try:
            self.proc.terminate()
            self.proc.wait(10)
        except (subprocess.TimeoutExpired, OSError):
            self.proc.kill()
        self.server.shutdown()
        log({"event": "player-stop"})


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
                if session.player is not None:
                    session.player.stop()
                    session.player = None
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
                session.loaded_at, session.false_start_said = time.monotonic(), False
                log({"event": "load", "contentId": session.media.get("contentId"), "contentType": session.media.get("contentType"),
                     "streamType": session.media.get("streamType")})
                if args.mode == "load-failed":
                    send(conn, TRANSPORT_ID, msg.source_id, NS_MEDIA, {"type": "LOAD_FAILED", "requestId": rid})
                    continue
                if args.player == "chromium":
                    if session.player is not None:
                        session.player.stop()
                    fetches[0] += 1
                    capture = f"{args.out}/capture-{fetches[0]}.{EXT.get(session.media.get('contentType'), 'bin')}"
                    log({"event": "fetch-start", "url": session.media.get("contentId"), "file": capture})
                    session.player = Player(session.media.get("contentId"), fetches[0], capture)
                send(conn, TRANSPORT_ID, msg.source_id, NS_MEDIA, session.media_status(rid, "BUFFERING"))
                if session.player is None:
                    threading.Thread(target=fetch, args=(session.media.get("contentId"), session.media.get("contentType")), daemon=True).start()
                if session.player is None and args.mode != "never-plays":
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
    parser.add_argument("--mode", default="normal", choices=["normal", "launch-error", "load-failed", "no-pong", "never-plays", "false-start"])
    parser.add_argument("--name", default="Living room TV")
    parser.add_argument("--model", default="Chromecast")
    parser.add_argument("--udn", default="5d7a9c4e-81ab-4c3d-9e2f-000000000081")
    parser.add_argument("--capture-seconds", type=int, default=30)
    parser.add_argument("--player", default="none", choices=["none", "chromium"])
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
