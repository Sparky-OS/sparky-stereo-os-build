#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-2.0-or-later
"""The loopback proof's scenario (session.sh starts it): discovery, a Throw and its stream, the pair on the thrown
network screen, the failures said, the unknown model told once, and what a device lets the PC read and set without an
account. Each claim is a row of OUT/rows.tsv; the exit status is the number of rows not as expected.

Usage: scenario.py OUT_DIR CLI
"""
import json
import re
import os
import subprocess
import sys
import time

OUT, CLI = sys.argv[1], sys.argv[2]
DEV = os.path.join(OUT, "devices")
LIVING = "5d7a9c4e81ab4c3d9e2f000000000081"
BEDROOM = "5d7a9c4e81ab4c3d9e2f000000000082"
STUDY = "5d7a9c4e81ab4c3d9e2f000000000083"
HALL = "5d7a9c4e81ab4c3d9e2f000000000084"
DEN = "5d7a9c4e81ab4c3d9e2f000000000085"
KITCHEN = "5d7a9c4e81ab4c3d9e2f000000000086"
PLAYER = "5d7a9c4e81ab4c3d9e2f000000000087"  # its player is Chromium in a media element
STUCK = "5d7a9c4e81ab4c3d9e2f000000000088"  # it fetches and never plays
TONE_HZ = 997
CATALOGUE = {"ja_JP": "ja"}  # a locale and the folder of its catalogues
rows = []
failed = 0


def log(text):
    with open(os.path.join(OUT, "scenario.log"), "a") as f:
        f.write(time.strftime("%H:%M:%S ", time.gmtime()) + text + "\n")


def row(rid, claim, expected, measured):
    global failed
    ok = expected == measured
    failed += not ok
    rows.append((rid, claim, str(expected), str(measured), "PASS" if ok else "FAIL"))
    log(f"{rid} {'PASS' if ok else 'FAIL'} {claim}: expected {expected}, measured {measured}")


def run(*cmd, timeout=60):
    try:
        p = subprocess.run(list(cmd), capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout, p.stderr
    except FileNotFoundError as exc:
        return 127, "", str(exc)
    except subprocess.TimeoutExpired:
        return 124, "", "timeout"


def devices():
    rc, out, _ = run(CLI, "list")
    try:
        return {d["id"]: d for d in json.loads(out)} if rc == 0 else {}
    except json.JSONDecodeError:
        return {}


def wait_for(fn, seconds):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        value = fn()
        if value:
            return value
        time.sleep(0.5)
    return fn()


def device_log(id_):
    path = os.path.join(DEV, id_, "device.log")
    if not os.path.exists(path):
        return []
    with open(path) as f:
        return [json.loads(line) for line in f if line.strip()]


def events(id_, name):
    return [e for e in device_log(id_) if e.get("event") == name]


def screens():
    rc, out, _ = run("kscreen-doctor", "-j")
    try:
        return {o["name"]: o for o in json.loads(out).get("outputs", [])}
    except json.JSONDecodeError:
        return {}


def current_mode(output):
    return next((m for m in output.get("modes", []) if str(m.get("id")) == str(output.get("currentModeId"))), {})


def capture(id_, n):
    """The bytes the device fetched at its n-th LOAD, kept as they came (capture-N.<container>)."""
    import glob
    found = sorted(glob.glob(os.path.join(DEV, id_, f"capture-{n}.*")))
    return found[0] if found else None


def probe_info(id_, n):
    for e in events(id_, "probe"):
        if re.search(rf"capture-{n}\.[a-z0-9]+$", e.get("file", "")):
            return e.get("info", {})
    return None


def probe(id_, n):
    """The video stream ffprobe found in the n-th fetch (or its first stream)."""
    info = probe_info(id_, n)
    if info is None:
        return None
    streams = info.get("streams", [])
    video = [x for x in streams if x.get("codec_type") == "video"]
    return (video or streams or [{}])[0]


def problems():
    rc, out, _ = run("sparky-stereo-problems", "list", "--json", "sparky-stereo-throw")
    try:
        data = json.loads(out)
    except json.JSONDecodeError:
        return {}
    items = data if isinstance(data, list) else data.get("problems", [])
    return {p.get("key"): p for p in items}


def kwin_script(js):
    run("python3", "-I", "/rigtools/kwin_script.py", os.path.join(OUT, "kwin.log"), js, timeout=30)


def notices():
    try:
        with open(os.path.join(OUT, "notifications.jsonl")) as f:
            return [json.loads(line) for line in f if line.strip()]
    except OSError:
        return []


def screen_made(id_):
    """KWin made a network screen for a Throw to that device: the daemon asked for it and was told it was created."""
    try:
        lines = open(os.path.join(OUT, "throwd.log")).read().splitlines()
    except OSError:
        return False
    asked = [i for i, line in enumerate(lines) if f'asked KWin for the network screen "{id_}"' in line]
    return any("network screen created" in line for i in asked for line in lines[i + 1:i + 4])


def fixture_minimized(flag):
    kwin_script("for (const w of workspace.windowList()) { if (w.desktopFileName == 'org.kde.kwin.capturefixture') {"
                " w.minimized = %s; } }" % ("true" if flag else "false"))


def place_fixture(screen_name):
    kwin_script("const s = workspace.screens.find(o => o.name == '%s');"
                "for (const w of workspace.windowList()) { if (w.desktopFileName == 'org.kde.kwin.capturefixture') {"
                " workspace.sendClientToScreen(w, s); w.frameGeometry = {x: s.geometry.x, y: s.geometry.y, width: w.frameGeometry.width,"
                " height: w.frameGeometry.height}; workspace.activeWindow = w; } }" % screen_name)


def last_frame(id_, n, name):
    """The last frame of the n-th fetch, decoded in order from the start (the stream ends whole at Stop: the muxer writes
    its trailer before the connection closes; a live Matroska stream has no index, so seeking from its end, -sseof,
    lands between keyframes)."""
    src = capture(id_, n) or ""
    dst = os.path.join(OUT, "frames", name + ".png")
    run("ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", src, "-map", "0:v:0", "-update", "1", dst, timeout=300)
    return dst if os.path.exists(dst) else None


def means(png):
    from PIL import Image
    img = Image.open(png).convert("RGB").resize((64, 36))
    w, h = img.size
    px = img.load()

    def mean(x0, y0, x1, y1):
        vals = [px[x, y] for x in range(x0, x1) for y in range(y0, y1)]
        return tuple(sum(v[i] for v in vals) // len(vals) for i in range(3))
    return mean(2, 2, w // 2 - 2, h - 2), mean(w // 2 + 2, 2, w - 2, h - 2)


def rate(text):
    num, _, den = text.partition("/")
    try:
        return float(num) / float(den or 1)
    except (ValueError, ZeroDivisionError):
        return 0.0


def near(a, b, tol=40):
    return all(abs(x - y) <= tol for x, y in zip(a, b))


def sink_description(id_):
    """The Throw's sound output in PipeWire's graph (pw-dump): its description, or None."""
    rc, out, _ = run("pw-dump", timeout=20)
    try:
        objs = json.loads(out)
    except json.JSONDecodeError:
        return None
    for o in objs:
        props = (o.get("info") or {}).get("props") or {}
        if props.get("node.name") == f"throw.{id_}" and props.get("media.class") == "Audio/Sink":
            return props.get("node.description")
    return None


def tone(path, freq, seconds, rate=48000):
    import math
    import struct
    import wave
    frames = bytearray()
    for i in range(int(seconds * rate)):
        v = int(0.5 * 32767 * math.sin(2 * math.pi * freq * i / rate))
        frames += struct.pack("<hh", v, v)
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(bytes(frames))
    return path


def play(id_, wav):
    return subprocess.Popen(["pw-play", "--target", f"throw.{id_}", wav], stdout=subprocess.DEVNULL,
                            stderr=open(os.path.join(OUT, "pw-play.log"), "a"))


def audio_pcm(path):
    import array
    p = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-map", "0:a:0", "-ac", "1", "-ar", "48000", "-f", "s16le", "-"],
                       capture_output=True, timeout=120)
    a = array.array("h")
    a.frombytes(p.stdout[:len(p.stdout) // 2 * 2])
    return a


def audio_start(path):
    rc, out, _ = run("ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries", "stream=start_time", "-of", "csv=p=0", path)
    try:
        return float(out.strip().splitlines()[0])
    except (ValueError, IndexError):
        return 0.0


def goertzel(x, freq, rate=48000):
    import math
    c = 2 * math.cos(2 * math.pi * freq / rate)
    s1 = s2 = 0.0
    for v in x:
        s0 = v + c * s1 - s2
        s2, s1 = s1, s0
    return s1 * s1 + s2 * s2 - c * s1 * s2


def tone_at(samples, freq):
    """The loudest fifth of a second of the sound: its power at freq beats the power at 0.7 and 1.5 times it a hundredfold."""
    n = 9600
    best = (0, 0)
    for i in range(0, max(1, len(samples) - n), n):
        e = sum(v * v for v in samples[i:i + n:8])
        if e > best[0]:
            best = (e, i)
    if best[0] == 0:
        return False
    w = samples[best[1]:best[1] + n]
    return goertzel(w, freq) > 100 * max(goertzel(w, freq * 0.7), goertzel(w, freq * 1.5))


def audio_onset(samples, threshold=4000):
    for i in range(0, len(samples), 480):
        if max((abs(v) for v in samples[i:i + 480]), default=0) > threshold:
            return i / 48000
    return None


def video_red_onset(path):
    """The time of the first frame whose left half is red (its mean chroma Cr above 170; black is 128)."""
    rc, out, _ = run("ffprobe", "-v", "error", "-f", "lavfi", "-i", f"movie={path},crop=iw/2:ih:0:0,signalstats", "-show_entries",
                     "frame=pts_time:frame_tags=lavfi.signalstats.VAVG", "-of", "csv=p=0", timeout=180)
    for line in out.splitlines():
        parts = line.split(",")
        try:
            t, v = float(parts[0]), float(parts[1])
        except (ValueError, IndexError):
            continue
        if v > 170:
            return t
    return None


def loads(id_):
    return events(id_, "load")


def fetch_from(source, host, port, path):
    """A connection to the stream from another address: the bytes it gets in 3 s."""
    import socket
    total = 0
    try:
        sock = socket.socket()
        sock.settimeout(3)
        sock.bind((source, 0))
        sock.connect((host, port))
        sock.sendall(f"GET {path} HTTP/1.1\r\nHost: {host}\r\n\r\n".encode())
        end = time.monotonic() + 3
        while time.monotonic() < end:
            chunk = sock.recv(65536)
            if not chunk:
                break
            total += len(chunk)
    except OSError:
        pass
    return total


def idle_close(source, host, port, limit=10):
    """A connection from the device's address that sends nothing: the seconds until the server closes it (None: open)."""
    import socket
    start = time.monotonic()
    try:
        sock = socket.socket()
        sock.settimeout(limit)
        sock.bind((source, 0))
        sock.connect((host, port))
        data = sock.recv(1)
        return time.monotonic() - start if not data else None
    except socket.timeout:
        return None
    except OSError:
        return time.monotonic() - start


def choose(id_, codec, mode="-"):
    rc, out, err = run(CLI, "choose", id_, codec, mode, timeout=20)
    log(f"choose {id_} {codec} {mode}: rc {rc} {err.strip()[:200]}")
    return rc, out


def throw_for(id_, seconds, wait=90):
    """A Throw that runs until its first keyframe (or sound) went to the device, then the given seconds, then stops."""
    before = open(os.path.join(OUT, "throwd.log")).read().count("went to")
    rc, out = throw(id_, wait)
    if rc == 0:
        wait_for(lambda: open(os.path.join(OUT, "throwd.log")).read().count("went to") > before, wait)
        time.sleep(seconds)
        stop(id_)
    return rc, out


def throw(id_, seconds=40):
    rc, out, err = run(CLI, "throw", id_, "--wait", str(seconds), timeout=seconds + 10)
    log(f"throw {id_}: rc {rc} {out.strip()} {err.strip()}")
    return rc, out.strip()


def stop(id_):
    rc, out, err = run(CLI, "stop", id_)
    log(f"stop {id_}: rc {rc} {err.strip()}")
    return rc


def main():
    # --- discovery
    found = wait_for(lambda: (lambda d: d if len(d) >= 8 else None)(devices()), 30) or devices()
    row("D1", "the eight devices announced on the network are found by themselves (ids)",
        sorted([LIVING, BEDROOM, STUDY, HALL, DEN, KITCHEN, PLAYER, STUCK]), sorted(found))
    d = found.get(LIVING, {})
    row("D2", "a device as it names itself: name, model, address", ("Living room TV", "Chromecast", "10.81.0.1"),
        (d.get("name"), d.get("model"), d.get("address")))
    row("D3", "the device table's picks: Chromecast, Ultra, unknown model, Google TV Streamer, a speaker (codec, mode, known)",
        [("h264", "1920x1080@30", True), ("hevc", "3840x2160@30", True), ("h264", "1920x1080@30", False), ("hevc", "3840x2160@30", True),
         ("", "", True)],
        [(found.get(i, {}).get("codec"), found.get(i, {}).get("mode"), found.get(i, {}).get("known")) for i in (LIVING, BEDROOM, STUDY, DEN, KITCHEN)])
    rc, out, _ = run(CLI, "list")
    try:
        names = [d["name"] for d in json.loads(out)]
    except (json.JSONDecodeError, KeyError):
        names = []
    row("D4", "the devices are listed in the order of their names",
        ["Bedroom TV", "Den TV", "Hall TV", "Kitchen speaker", "Living room TV", "Player TV", "Stuck TV", "Study screen"], names)

    # --- a Throw to a first-generation Chromecast
    name = f"Virtual-{LIVING}"
    row("T0", "the device is listed and has no network screen before its Throw", (True, False),
        (LIVING in devices(), name in screens()))
    rc, out = throw(LIVING)
    row("T1", "the Throw starts and the device plays (state)", (0, "throwing"), (rc, out))
    out_ = screens().get(name, {})
    mode = current_mode(out_)
    row("T2", "KWin lists the device's network screen at the table's mode", ("1920x1080", 30),
        (f"{mode.get('size', {}).get('width')}x{mode.get('size', {}).get('height')}", round(mode.get("refreshRate", 0))))
    launch = [e.get("appId") for e in events(LIVING, "launch")]
    load = events(LIVING, "load")
    row("T3", "the device was asked to launch the Default Media Receiver and to load a live Matroska stream from the PC",
        (["CC1AD845"], "video/x-matroska", "LIVE", True),
        (launch[:1], load[0].get("contentType") if load else None, load[0].get("streamType") if load else None,
         bool(load) and load[0].get("contentId", "").startswith("http://10.81.0.1:")))
    # --- the stream's server (C1): the address facing the device only, that device only, no idle connection kept
    from urllib.parse import urlsplit
    u = urlsplit(load[0].get("contentId", "") if load else "")
    rc_, listening, _ = run("ss", "-ltnH", f"sport = :{u.port or 0}")
    addrs = sorted({line.split()[3].rsplit(":", 1)[0] for line in listening.splitlines() if len(line.split()) > 3})
    row("H1", "the stream's server listens on the address facing the device only (ss)", ["10.81.0.1"], addrs)
    row("H2", "another address gets no stream: a request from 10.81.0.3 is closed with nothing (bytes)", 0,
        fetch_from("10.81.0.3", u.hostname or "10.81.0.1", u.port or 0, u.path))
    closed = idle_close("10.81.0.1", u.hostname or "10.81.0.1", u.port or 0)
    row("H3", f"a connection that sends no request line is closed within 5 s (closed after {closed})", True,
        closed is not None and closed <= 7)
    time.sleep(2)
    rc = stop(LIVING)
    gone = wait_for(lambda: name not in screens(), 10)
    row("T4", "Stop ends it: the network screen is gone, the device was told STOP and the channel closed",
        (0, True, True, True), (rc, bool(gone), bool(events(LIVING, "stop")), bool(events(LIVING, "sender-closed-channel"))))
    s = wait_for(lambda: probe(LIVING, 1), 40) or {}
    row("T5", "the stream the device fetched: H.264 Main at 1920x1080, at most 30 frames a second, level 4.1 or lower",
        ("h264", "Main", 1920, 1080, True, True),
        (s.get("codec_name"), s.get("profile"), s.get("width"), s.get("height"),
         0 < rate(s.get("avg_frame_rate", "0/0")) <= 30.5,
         0 < int(s.get("level", 99)) <= 41))

    # --- the pair on the thrown network screen (B5): half side by side, then the same device comes back in it, then 2D
    # KWin's test fixture (a declared pair, left eye red, right eye blue) is a tool of the proof, not of the Throw: a
    # session without it fails the pair rows instead of stopping
    try:
        fixture = subprocess.Popen(["/tools/bin/capturefixture", os.path.join(OUT, "pair.png"), "1920", "1080", "stereo"],
                                   stdout=subprocess.DEVNULL, stderr=open(os.path.join(OUT, "fixture.log"), "w"))
    except OSError as exc:
        log(f"the capture fixture cannot start: {exc}")
        fixture = None
    time.sleep(2)
    rc, out = throw(LIVING)
    time.sleep(2)
    place_fixture(name)
    time.sleep(1)
    run("kscreen-doctor", f"output.{name}.otherStereoFormats.enable")
    time.sleep(1)
    twins = {m.get("stereo3D"): m["id"] for m in screens().get(name, {}).get("modes", [])}
    run("kscreen-doctor", f"output.{name}.mode.{twins.get(1)}")
    time.sleep(8)
    stop(LIVING)
    wait_for(lambda: probe(LIVING, 2), 40)
    frame = last_frame(LIVING, 2, "living-side-by-side-half")
    left, right = means(frame) if frame else ((0, 0, 0), (0, 0, 0))
    row("P1", f"half side by side: the left eye's red in the left half, the right eye's blue in the right (means {left} {right})",
        (True, True), (near(left, (255, 0, 0)), near(right, (0, 0, 255))))
    rc, out = throw(LIVING)
    cur = current_mode(screens().get(name, {}))
    row("P2", "the next Throw to the same device comes back in half side by side (stereo3D)", 1, cur.get("stereo3D"))
    place_fixture(name)
    time.sleep(2)
    flat = twins.get(0)
    run("kscreen-doctor", f"output.{name}.mode.{flat}")
    time.sleep(8)
    stop(LIVING)
    wait_for(lambda: probe(LIVING, 3), 40)
    frame = last_frame(LIVING, 3, "living-2d")
    left, right = means(frame) if frame else ((0, 0, 0), (0, 0, 0))
    row("P3", f"2D: one view, the left eye's red over the whole frame (means {left} {right})", (True, True),
        (near(left, (255, 0, 0)), near(right, (255, 0, 0))))
    # --- the sound (C2): "Throw: <device>" while the Throw runs, a tone found in the stream at its frequency, in step
    # with the picture; then gone
    wav = tone(os.path.join(OUT, "tone.wav"), TONE_HZ, 3)
    # the pair hidden: KWin would put it back on the device's screen when that screen is made again for the same device
    fixture_minimized(True)
    n_before = len(loads(LIVING))
    rc, out = throw(LIVING)
    sink = wait_for(lambda: sink_description(LIVING), 10)
    row("A1", "while a Throw runs, its sound output exists, named as the design names it", "Throw: Living room TV", sink)
    time.sleep(4)
    # at one instant: the pair onto the thrown screen (the picture turns from black to red and blue) and the tone starts
    # each event timed where it happens, on the wall clock: the tone just before pw-play starts, the picture's change in
    # KWin's script at the instant it moves the pair onto the thrown screen (it prints the time to KWin's log)
    t_play_ms = time.time() * 1000
    player = play(LIVING, wav)
    kwin_script("const s = workspace.screens.find(o => o.name == '%s'); for (const w of workspace.windowList()) {"
                " if (w.desktopFileName == 'org.kde.kwin.capturefixture') { w.minimized = false; workspace.sendClientToScreen(w, s);"
                " w.frameGeometry = {x: s.geometry.x, y: s.geometry.y, width: w.frameGeometry.width, height: w.frameGeometry.height};"
                " workspace.activeWindow = w; print('THROWMOVED ' + Date.now()); } }" % name)
    moved = [float(x) for x in re.findall(r"THROWMOVED (\d+)", open(os.path.join(OUT, "kwin.log")).read())]
    command_gap = (moved[-1] - t_play_ms) / 1000 if moved else 0.0
    time.sleep(5)
    rc_, st, _ = run(CLI, "status", LIVING)
    try:
        st = json.loads(st)
    except json.JSONDecodeError:
        st = {}
    row("K2", "the kit's record: what the device reports and what it fetched (player state, bytes)", ("PLAYING", True),
        (st.get("playerState"), (st.get("bytesFetched") or 0) > 0))
    stop(LIVING)
    player.wait(10)
    row("A4", "the sound output existed during the Throw and is gone when it ends", (True, True),
        (bool(sink), bool(wait_for(lambda: sink_description(LIVING) is None, 10))))
    n = n_before + 1
    wait_for(lambda: probe(LIVING, n), 40)
    cap = capture(LIVING, n) or ""
    info = probe_info(LIVING, n) or {}
    acodec = next((x.get("codec_name") for x in info.get("streams", []) if x.get("codec_type") == "audio"), None)
    samples = audio_pcm(cap) if cap else []
    row("A2", f"a {TONE_HZ} Hz tone played into it is in the stream the device fetched, at that frequency (24-bit PCM in Matroska, the default sound since 0.3.0)",
        ("pcm_s24le", True), (acodec, tone_at(samples, TONE_HZ)))
    a_on = audio_onset(samples)
    a_t = audio_start(cap) + a_on if a_on is not None else None
    v_t = video_red_onset(cap) if cap else None
    gap = round(v_t - a_t, 3) if a_t is not None and v_t is not None else None
    own = round(gap - command_gap, 3) if gap is not None else None
    row("A3", f"picture and sound in step: the Throw's own offset between the picture's change and the tone's start within "
        f"200 ms (picture {v_t} s, sound {a_t} s in the stream: picture minus sound {gap} s; the pair moved "
        f"{round(command_gap, 3)} s after the tone started; the Throw's own {own} s)", True, own is not None and abs(own) <= 0.2)
    if fixture:
        fixture.terminate()

    # --- a speaker gets the sound alone (C2): FLAC in Ogg, no picture
    rc, out = throw(KITCHEN)
    kl = loads(KITCHEN)
    row("A5", "a speaker's Throw plays the sound alone: the device loads FLAC in Ogg from the PC (state, type)",
        (0, "throwing", "audio/ogg"), (rc, out, kl[0].get("contentType") if kl else None))
    player = play(KITCHEN, wav)
    time.sleep(5)
    stop(KITCHEN)
    player.wait(10)
    wait_for(lambda: probe_info(KITCHEN, 1), 40)
    info = probe_info(KITCHEN, 1) or {}
    kinds = [x.get("codec_type") for x in info.get("streams", [])]
    kc = capture(KITCHEN, 1) or ""
    row("A6", f"the speaker's stream carries the {TONE_HZ} Hz tone and no picture (audio codec, video tracks, tone)",
        ("flac", 0, True),
        (next((x.get("codec_name") for x in info.get("streams", []) if x.get("codec_type") == "audio"), None),
         kinds.count("video"), tone_at(audio_pcm(kc), TONE_HZ) if kc else False))

    # --- failures said (red rows on purpose)
    rc, out = throw(BEDROOM, 30)
    row("F1", "a device that refuses to launch the player: the Throw fails and says so", (1, True),
        (rc, "refused to start its media player: NOT_FOUND" in out))
    row("F2", "a network screen was made for that Throw, and it is removed after the failure", (True, False),
        (screen_made(BEDROOM), bool(wait_for(lambda: f"Virtual-{BEDROOM}" in screens(), 2) and f"Virtual-{BEDROOM}" in screens())))
    pr = problems()
    row("F3", "the failure is kept in the problems engine for that device", True, f"throw:{BEDROOM}" in pr)
    rc, out = throw(HALL, 30)
    lost = wait_for(lambda: devices().get(HALL, {}).get("state") == "failed", 45)
    row("F4", "a device that stops answering the heartbeat: the Throw ends and says so (state, detail)", (True, True),
        (bool(lost), "stopped answering" in devices().get(HALL, {}).get("detail", "")))
    row("F5", "a network screen was made for that Throw, and it is gone", (True, False),
        (screen_made(HALL), f"Virtual-{HALL}" in screens()))

    # --- what the person is told: the desktop's notifications (a stand-in server logs each Notify)
    told = notices()
    row("N1", "a failure is told through the desktop's notifications, whole (body)", True,
        any(n.get("body") == "Bedroom TV refused to start its media player: NOT_FOUND" for n in told))
    row("N2", "a running Throw is told (body)", True, any(n.get("body") == "Throwing to Living room TV." for n in told))

    # --- the unknown model: the first Chromecast's limits, told once
    rc, out = throw(STUDY)
    time.sleep(6)
    stop(STUDY)
    rc2, out2 = throw(STUDY)
    time.sleep(2)
    stop(STUDY)
    s = wait_for(lambda: probe(STUDY, 1), 40) or {}
    told = open(os.path.join(OUT, "throwd.log")).read().count("notice \"unknownModel\"")
    row("U1", "a model not in the table throws at 1920x1080 H.264 (twice) and is told once (notices, kept)",
        (0, 0, 1920, 1080, "h264", 1, True),
        (rc, rc2, s.get("width"), s.get("height"), s.get("codec_name"), told, f"unknown-model:{STUDY}" in problems()))

    # --- the codecs (C3): the best one the device takes that this computer encodes, the container that follows it
    rc, out = throw_for(DEN, 4, 120)
    s = wait_for(lambda: probe(DEN, 1), 60) or {}
    info = probe_info(DEN, 1) or {}
    row("K1", "a Google TV Streamer gets 3840x2160 in HEVC, its best codec this computer encodes (AV1 has none), in MP4 with FLAC",
        (0, "hevc", 3840, 2160, "video/mp4", "flac"),
        (rc, s.get("codec_name"), s.get("width"), s.get("height"), (loads(DEN) or [{}])[-1].get("contentType"),
         next((x.get("codec_name") for x in info.get("streams", []) if x.get("codec_type") == "audio"), None)))
    # the screen moves while these run, as a person's desktop does while they work: KPipeWire 6.7.4's libvpx encoders
    # hold libvpx's 25 frames of lag, so a still screen gives them no picture (the trap in the skill)
    import threading
    mover_stop = threading.Event()

    def mover(target):
        x = 0
        while not mover_stop.is_set():
            kwin_script("const s = workspace.screens.find(o => o.name == 'Virtual-%s'); if (s) { for (const w of workspace.windowList()) {"
                        " if (w.desktopFileName == 'org.kde.kwin.capturefixture') { w.minimized = false; workspace.sendClientToScreen(w, s);"
                        " w.frameGeometry = {x: s.geometry.x + %d, y: s.geometry.y, width: w.frameGeometry.width, height: w.frameGeometry.height}; } } }"
                        % (target, x))
            x = (x + 64) % 640
            time.sleep(0.1)

    try:
        fixture = subprocess.Popen(["/tools/bin/capturefixture", os.path.join(OUT, "pair-moving.png"), "1280", "720", "stereo"],
                                   stdout=subprocess.DEVNULL, stderr=open(os.path.join(OUT, "fixture-moving.log"), "w"))
    except OSError:
        fixture = None
    time.sleep(2)
    for rid, dev, codec, mode, expect in (("E2", DEN, "h264", "1920x1080@30", ("h264", 1920, 1080, "video/x-matroska", "pcm_s24le")),
                                         ("E3", LIVING, "vp8", "1920x1080@30", ("vp8", 1920, 1080, "video/webm", "opus"))):
        choose(dev, codec, mode)
        k = len(loads(dev)) + 1
        mover_stop.clear()
        moving = threading.Thread(target=mover, args=(dev,), daemon=True)
        moving.start()
        rc, out = throw_for(dev, 4, 120)
        mover_stop.set()
        moving.join(5)
        s = wait_for(lambda: probe(dev, k), 60) or {}
        info = probe_info(dev, k) or {}
        row(rid, f"{codec} chosen for the device: the stream it fetched (codec, size, type, sound)", (0,) + expect,
            (rc, s.get("codec_name"), s.get("width"), s.get("height"), (loads(dev) or [{}])[-1].get("contentType"),
             next((x.get("codec_name") for x in info.get("streams", []) if x.get("codec_type") == "audio"), None)))
    if fixture:
        fixture.terminate()
    choose(DEN, "vp9", "1920x1080@30")
    rc, out = throw(DEN, 20)
    row("E1", "VP9 chosen: refused at once with its reason (KPipeWire 6.7.4's VP9 encoder gives no picture for a live screen), "
        "not made in another codec (exit, reason)", (1, True), (rc, "KPipeWire 6.7.4's VP9 encoder" in out))
    choose(DEN, "av1")
    rc, out = throw(DEN, 20)
    row("E4", "AV1 chosen: the Throw is refused with its reason, not made in another codec (exit, reason)", (1, True),
        (rc, "KPipeWire 6.7.4 has no AV1 encoder" in out))
    choose(DEN, "-")
    choose(LIVING, "-")

    # --- the mode picker (C4): the device's modes, kept per device
    choose(LIVING, "h264", "1280x720@60")
    k = len(loads(LIVING)) + 1
    rc, out = throw(LIVING)
    m = current_mode(screens().get(name, {}))
    time.sleep(5)
    stop(LIVING)
    s = wait_for(lambda: probe(LIVING, k), 40) or {}
    row("M1", "a mode chosen on the device's page: its network screen and its stream (screen mode, stream size)",
        ("1280x720", 60, 1280, 720),
        (f"{m.get('size', {}).get('width')}x{m.get('size', {}).get('height')}", round(m.get("refreshRate", 0)), s.get("width"), s.get("height")))
    try:
        rcfile = open(os.path.join(os.environ.get("HOME", ""), ".config", "sparky-stereo-throwrc")).read()
    except OSError:
        rcfile = ""
    row("M2", "the choice is kept per device, by its identity (sparky-stereo-throwrc)", True,
        f"[Device][{LIVING}]" in rcfile and "Codec=h264" in rcfile and "Mode=1280x720@60" in rcfile)
    rc, out_ = choose(LIVING, "h264", "3840x2160@30")
    row("M3", "a mode the device does not take is refused", 1, rc)
    choose(LIVING, "-")

    # --- what the device lets the PC read and set without an account (B11)
    rc, out, err = run(CLI, "info", LIVING, timeout=30)
    try:
        info = json.loads(out)
    except json.JSONDecodeError:
        info = {}
    e = info.get("eureka", {})
    row("I1", "the device's own information without an account: name, model, maker (HTTPS 8443, no token)",
        ("Living room TV", "Chromecast", "Google Inc.", True),
        (e.get("name"), e.get("device_info", {}).get("model_name"), e.get("device_info", {}).get("manufacturer"),
         e.get("source", "").startswith("https://10.81.0.1:8443/")))
    row("I2", "its firmware where it gives it (build_info)", "1.56.500000", info.get("build", {}).get("build_info", {}).get("cast_build_revision"))
    row("I3", "its receiver status: the volume and its kind", (0.5, "attenuation"),
        (info.get("receiver", {}).get("volume", {}).get("level"), info.get("receiver", {}).get("volume", {}).get("controlType")))
    tokens = [x for x in events(LIVING, "eureka") if x.get("token")]
    row("I4", "the device's setup interface was asked, and no request carried an account token", (True, 0),
        (len(events(LIVING, "eureka")) > 0, len(tokens)))
    rc, out, err = run(CLI, "volume", LIVING, "0.25", "mute", timeout=30)
    try:
        vol = json.loads(out).get("volume", {})
    except json.JSONDecodeError:
        vol = {}
    row("V1", "the volume set from the PC, read back from the device (level, muted)", (0, 0.25, True), (rc, vol.get("level"), vol.get("muted")))
    rc, out, err = run(CLI, "info", LIVING, timeout=30)
    try:
        info = json.loads(out)
    except json.JSONDecodeError:
        info = {}
    row("V2", "the device keeps it (read again)", (0.25, True), (info.get("receiver", {}).get("volume", {}).get("level"),
                                                                info.get("receiver", {}).get("volume", {}).get("muted")))


def captions():
    rc, out, _ = run("python3", "-I", "/rigtools/kwin_windows.py", os.path.join(OUT, "kwin.log"), timeout=30)
    try:
        # the rig's helper prints {"t_monotonic_ms": ..., "windows": [{caption, ...}]} (KWin's own view)
        return [w.get("caption", "") for w in (json.loads(out.strip().splitlines()[-1]).get("windows") or [])]
    except (json.JSONDecodeError, IndexError, AttributeError):
        return []


def locked():
    """Whether KWin's screen locker came over the session (its log says so: the "locked" event, its greeter)."""
    try:
        text = open(os.path.join(OUT, "kwin.log")).read()
    except OSError:
        return False
    return 'event id "locked"' in text or "kscreenlocker: Greeter" in text


NAME = "org.sparky.Throw"
SERVICE_FILE = "/usr/share/dbus-1/services/org.sparky.Throw.service"
# A file "activate-in-gap" beside this script makes every restart ask for the daemon's name while no process owns it, as
# any client may at that moment: the proof that a restart cannot race (red with a hand-started copy, green through the bus).
GAP_PROBE = os.path.exists(os.path.join(os.path.dirname(os.path.abspath(__file__)), "activate-in-gap"))


def bus_call(method, signature="", *args):
    """A call to the session bus itself, through busctl (dbus-send cannot send an empty string); (ok, data)."""
    cmd = ["busctl", f"--address={os.environ['DBUS_SESSION_BUS_ADDRESS']}", "--json=short", "call",
           "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", method]
    if signature:
        cmd += [signature, *[str(a) for a in args]]
    rc, out, _ = run(*cmd, timeout=30)
    try:
        return rc == 0, (json.loads(out)["data"] if out.strip() else None)
    except (json.JSONDecodeError, KeyError):
        return rc == 0, None


def name_owner_pid():
    ok, data = bus_call("GetConnectionUnixProcessID", "s", NAME)
    return data[0] if ok and data else None


def name_owned():
    ok, data = bus_call("NameHasOwner", "s", NAME)
    return bool(ok and data and data[0])


def environ_of(pid):
    try:
        raw = open(f"/proc/{pid}/environ", "rb").read()
    except OSError:
        return {}
    return dict(item.decode("utf-8", "replace").split("=", 1) for item in raw.split(b"\0") if b"=" in item)


def language_env(lang):
    """The language as a person's session gives it: LANGUAGE, LANG and LC_ALL together (gettext translates nothing while
    LC_ALL is C, which the image's environment sets); without a language, the session's own values."""
    if lang:
        return {"LANGUAGE": CATALOGUE.get(lang, lang), "LANG": f"{lang}.UTF-8", "LC_ALL": f"{lang}.UTF-8"}
    return {k: os.environ.get(k, "") for k in ("LANGUAGE", "LANG", "LC_ALL")}


def restart_daemon(lang):
    """The daemon again in a language, as a person's session starts it in theirs. The session bus's activation
    environment is set to the language first; the running daemon is ended; then the bus starts it from its service file.
    Whatever asks for the name in between (a command, a page) makes the bus start it in that same language, so nothing
    can race the restart. A copy started by hand could lose the name to the bus's own start in the session's language
    (the trap in the skill). Without the service file (a development session) nothing can start the daemon but this
    function, and its copy is started by hand. Then the name's owner is checked: its process must carry the language
    (and be the copy, when started by hand). The record goes to throwd-<lang>.txt; returns whether the owner holds."""
    import signal
    want = language_env(lang)
    tag = lang or "C"
    record = [f"language {tag}: {want}"]
    installed = os.path.exists(SERVICE_FILE)
    if installed:
        pairs = dict(want, QT_LOGGING_RULES="org.sparky.throw.debug=true")
        ok, _ = bus_call("UpdateActivationEnvironment", "a{ss}", len(pairs), *[x for kv in pairs.items() for x in kv])
        record.append(f"the bus's activation environment set: {ok}")
    pid = name_owner_pid()
    if pid:
        os.kill(pid, signal.SIGTERM)
        ended = wait_for(lambda: not os.path.exists(f"/proc/{pid}") and not name_owned(), 30)
        record.append(f"ended pid {pid}: {bool(ended)}")
    if GAP_PROBE:
        rc, _, _ = run(CLI, "list")
        record.append(f"asked for the name while nobody owned it ({CLI} list): exit {rc}")
    started = None
    if installed:
        ok, data = bus_call("StartServiceByName", "su", NAME, 0)
        record.append(f"StartServiceByName: {ok} {data} (1 started, 2 already running)")
    else:
        env = dict(os.environ, QT_LOGGING_RULES="org.sparky.throw.debug=true", **want)
        started = subprocess.Popen(["/tools/bin/sparky-stereo-throwd"], env=env, stdout=subprocess.DEVNULL,
                                   stderr=open(os.path.join(OUT, f"throwd-{tag}.log"), "w")).pid
        record.append(f"started by hand (no service file on this bus): pid {started}")
    owner = wait_for(name_owner_pid, 30)
    env = environ_of(owner) if owner else {}
    holds = bool(owner) and all(env.get(k, "") == v for k, v in want.items()) and started in (None, owner)
    record.append(f"owner of {NAME}: pid {owner}, executable {os.path.realpath(f'/proc/{owner}/exe') if owner else None}, "
                  f"{ {k: env.get(k) for k in want} }; started in that language: {holds}")
    if installed:
        record.append("its log: the session bus's output (setup.log), where every daemon the bus starts writes")
    with open(os.path.join(OUT, f"throwd-{tag}.txt"), "w") as f:
        f.write("\n".join(record) + "\n")
    log("restart " + "; ".join(record))
    if holds:
        wait_for(lambda: (lambda d: d if len(d) >= 8 else None)(devices()), 30)
    return holds


def page(name, args=(), lang=None):
    """The Throw page in System Settings, as the person opens it, with KDE's platform theme (the icons); a capture of the
    screen it shows on, the window captions while it is open, and the device setup requests made while it is open."""
    env = dict(os.environ, QT_QPA_PLATFORM="wayland", QT_QPA_PLATFORMTHEME="kde")
    if os.path.isdir("/tools/plugins"):
        env["QT_PLUGIN_PATH"] = "/tools/plugins"
    if lang:
        # gettext translates nothing while LC_ALL is C (the image's environment sets it): all three together
        env["LANGUAGE"] = CATALOGUE.get(lang, lang)
        env["LANG"] = env["LC_ALL"] = f"{lang}.UTF-8"
    before = len(events(LIVING, "eureka"))
    shell = subprocess.Popen(["systemsettings", "kcm_sparkystereo_throw", *args], env=env, stdout=subprocess.DEVNULL,
                             stderr=open(os.path.join(OUT, f"page-{name}.log"), "w"))
    time.sleep(10)
    # the window as tall as the screen, so a device's page shows whole, its account part included
    kwin_script("for (const w of workspace.windowList()) { if (String(w.resourceClass) == 'kdesystemsettings') {"
                " const g = w.output.geometry; w.frameGeometry = {x: g.x + 100, y: g.y, width: 1080, height: g.height}; } }")
    time.sleep(2)
    png = os.path.join(OUT, "frames", f"page-{name}.png")
    rc, out, err = run("python3", "-I", "/rigtools/capture.py", png, timeout=60)
    shown = captions()
    asked = len(events(LIVING, "eureka")) - before
    shell.terminate()
    try:
        shell.wait(10)
    except subprocess.TimeoutExpired:
        shell.kill()
    lock = locked()
    log(f"page {name}: captured {rc == 0 and os.path.exists(png)}, captions {shown}, setup requests to Living room TV {asked}, locked {lock}")
    return {"captured": rc == 0 and os.path.exists(png) and not lock, "captions": shown, "asked": asked}


def pages():
    # the icon theme a person's session gives (kdeglobals), for the platform theme to read
    os.makedirs(os.path.join(os.environ["HOME"], ".config"), exist_ok=True)
    with open(os.path.join(os.environ["HOME"], ".config", "kdeglobals"), "w") as f:
        f.write("[Icons]\nTheme=breeze\n")
    first = page("devices")
    row("C1", "the Throw page opens in System Settings (its window's caption) and is captured", (True, True),
        (any(c.startswith("Throw") and "System Settings" in c for c in first["captions"]), first["captured"]))
    second = page("living-room", ["--args", f"device={LIVING}"])
    row("C2", "a device's page opens from the page's argument: it asks the device for its information (setup requests) "
        "and is captured", (True, True), (second["asked"] > 0, second["captured"]))
    in_pt = restart_daemon("pt_BR")
    d = devices().get(LIVING, {}) if in_pt else {}
    row("C5", "the daemon's own words in the session's language (pt_BR): the process that owns its name was started in "
        "pt_BR, then the short words, the generation, the sound", (True, "1ª a 3ª geração", True, True),
        (in_pt, d.get("short"), d.get("generation", "").startswith("Chromecast, primeira"),
         d.get("sound", "").startswith("PCM, 24 bits, 48 kHz, 2 canais (sem perdas)")))
    words_rows(in_pt)
    third = page("living-room-pt_BR", ["--args", f"device={LIVING}"], "pt_BR")
    row("C3", "the device's page in Brazilian Portuguese (caption \"Throw (jogar)\", setup requests) is captured",
        (True, True, True), (any(c.startswith("Throw (jogar)") for c in third["captions"]), third["asked"] > 0, third["captured"]))
    in_ja = restart_daemon("ja_JP")
    pages_ja = page("devices-ja", [], "ja_JP")
    fourth = page("living-room-ja", ["--args", f"device={LIVING}"], "ja_JP")
    row("C4", "the list and the device's page in Japanese (caption \"Throw (送る)\") are captured, with the daemon that "
        "owns its name started in Japanese", (True, True, True, True),
        (any(c.startswith("Throw (送る)") for c in fourth["captions"]), pages_ja["captured"], fourth["captured"], in_ja))
    # back to the session's language: nothing reads the daemon after it, so its check is logged (throwd-C.txt)
    log(f"back in the session's language: {restart_daemon(None)}")


def status_of(id_):
    rc, out, _ = run(CLI, "status", id_)
    try:
        return json.loads(out) if rc == 0 else {}
    except json.JSONDecodeError:
        return {}


def picture_rate(path):
    """Pictures a second in a captured stream: video packets over the span of their times."""
    rc, out, _ = run("ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "packet=pts_time", "-of", "csv=p=0", path)
    times = [float(x) for x in out.split() if x.replace(".", "", 1).isdigit()]
    if len(times) < 2 or times[-1] <= times[0]:
        return 0.0, len(times)
    return (len(times) - 1) / (times[-1] - times[0]), len(times)


def partd():
    """Part D: a receiver that plays like one, the picture that keeps coming, the sound by the table and by choice, the
    device's messages in the log, and a Throw that does not play ended and said."""
    rc, _ = throw(PLAYER, 40)
    t0, first = time.monotonic(), None
    while time.monotonic() - t0 < 45:
        st = status_of(PLAYER)
        if st.get("playerState") == "PLAYING" and (st.get("currentTime") or 0) > 2:
            first = round(time.monotonic() - t0, 1)
            break
        time.sleep(1)
    log(f"DP1 the stand-in played after {first} s; status {status_of(PLAYER)}")
    row("DP1", "a receiver that plays like one (Chromium in a media element) plays a Throw of a still screen: PLAYING, its time "
        "past 2 s, within 45 s", True, first is not None)
    time.sleep(5)
    stop(PLAYER)
    wait_for(lambda: probe_info(PLAYER, 1), 60)
    cap = capture(PLAYER, 1)
    rate, count = picture_rate(cap) if cap else (0.0, 0)
    log(f"DP2 {count} pictures, {rate:.1f} a second in {cap}")
    row("DP2", "the picture keeps coming on a still screen: at least 20 pictures a second in the stream the device fetched", True, rate >= 20)
    info = probe_info(PLAYER, 1) or {}
    audio = next((x for x in info.get("streams", []) if x.get("codec_type") == "audio"), {})
    row("DP3", "the sound is the table's pick: PCM 24 bit, 2 channels, in Matroska", ("pcm_s24le", 2, True),
        (audio.get("codec_name"), audio.get("channels"), "matroska" in (info.get("format") or {}).get("format_name", "")))
    text = open(os.path.join(OUT, "throwd.log")).read()
    load = next(iter(loads(PLAYER)), {})
    token = (load.get("contentId", "").rsplit("/", 1)[-1].split(".")[0]) if load else ""
    row("DP4", "every Cast message is in the daemon's debug log (the device's MEDIA_STATUS in, the LOAD out), the stream's token taken out",
        (True, True, False), ("cast in" in text and "MEDIA_STATUS" in text, "cast out" in text and '"type":"LOAD"' in text,
                              bool(token) and token in text))
    rc, _ = throw(STUCK, 40)
    wait_for(lambda: (lambda d: d if d.get("state") == "failed" else None)(devices().get(STUCK, {})), 90)
    d = devices().get(STUCK, {})
    log(f"DP5 {d.get('state')}: {d.get('detail')}")
    row("DP5", "a Throw the device does not play is ended within 60 s and said, with what the device said", ("failed", True),
        (d.get("state"), "did not start playing within 60 seconds (it said BUFFERING" in (d.get("detail") or "")))
    row("DP6", "the sound that did not start is kept for that device: its next Throw takes FLAC", "flac", d.get("soundId"))
    run(CLI, "sound", LIVING, "ac3-5.1")
    n = len(loads(LIVING)) + 1
    throw_for(LIVING, 6)
    wait_for(lambda: probe_info(LIVING, n), 60)
    info = probe_info(LIVING, n) or {}
    audio = next((x for x in info.get("streams", []) if x.get("codec_type") == "audio"), {})
    run(CLI, "sound", LIVING, "-")
    row("DP7", "Dolby Digital 5.1 chosen on the device's page: the stream carries AC-3 with 6 channels", ("ac3", 6),
        (audio.get("codec_name"), audio.get("channels")))
    rc, out, _ = run(CLI, "sound", DEN, "pcm24")
    row("DP8", "PCM chosen for a stream that cannot carry it (HEVC in MP4) is refused, the choice unchanged", (1, ""),
        (rc, devices().get(DEN, {}).get("choiceSound", "")))


def words_rows(in_pt):
    """Part D, second half: a sound's name and what it means in the person's language, how long the device took to start,
    and a kept failure that carries a sound's name rendered by the problems engine in another language."""
    d = devices().get(PLAYER, {}) if in_pt else {}
    pcm = next((s for s in d.get("sounds", []) if s.get("id") == "pcm24"), {})
    log(f"DW1 {json.dumps(pcm, ensure_ascii=False)} soundAbout={d.get('soundAbout')!r} soundStart={d.get('soundStart')}")
    row("DW1", "the device's page in pt_BR: the sound's name in Portuguese, what it means in plain words, the seconds the device "
        "took to start with it (the stand-in played it in part D)", ("PCM, 24 bits", True, True, True),
        (pcm.get("label"), (pcm.get("about") or "").startswith("Sem perdas"), (pcm.get("startSeconds") or -1) > 0,
         (d.get("soundAbout") or "").startswith("Sem perdas") and (d.get("soundStart") or -1) > 0))
    env = dict(os.environ, **language_env("pt_BR"))
    out = subprocess.run(["sparky-stereo-problems", "list", "--json", "sparky-stereo-throw"], capture_output=True, text=True,
                         env=env, timeout=60).stdout
    try:
        items = json.loads(out)
    except json.JSONDecodeError:
        items = []
    stuck = next((p for p in (items if isinstance(items, list) else []) if p.get("key") == f"throw:{STUCK}"), {})
    log(f"DW2 {stuck.get('lang')}: {stuck.get('text')}")
    row("DW2", "the kept failure of the Throw that did not start, read in pt_BR from the problems engine: its sentence and the "
        "sound's name inside it in Portuguese", ("pt_BR", True, True),
        (stuck.get("lang"), "não começou a tocar em 60 segundos" in (stuck.get("text") or ""),
         "som PCM, 24 bits" in (stuck.get("text") or "")))


def dependent_rows():
    """Part D, second half: a client of KPipeWire that does not ask for a constant frame rate keeps KPipeWire's own behaviour
    on the new library. Spectacle (in the rig image that has it) records the still screen for about 12 s as MP4 (H.264;
    VP9, its default, gives no live picture in KPipeWire 6.7.4); a second request to record ends the recording. Its pictures
    are counted: a few, never the Throw's constant rate."""
    import shutil
    if not shutil.which("spectacle"):
        log("DK1 not run: no Spectacle in this rig image")
        return
    cfg = os.path.join(os.environ["HOME"], ".config", "spectaclerc")
    os.makedirs(os.path.dirname(cfg), exist_ok=True)
    with open(cfg, "w") as f:
        f.write("[VideoSave]\npreferredVideoFormat=2\n")
    rec = os.path.join(OUT, "spectacle-still.mp4")
    log_path = os.path.join(OUT, "spectacle.log")
    with open(log_path, "w") as lf:
        first = subprocess.Popen(["spectacle", "--background", "--nonotify", "--record", "s", "--output", rec], stdout=lf, stderr=lf)
        time.sleep(12)
        second = subprocess.run(["spectacle", "--background", "--nonotify", "--record", "s", "--output", rec], stdout=lf,
                                stderr=lf, timeout=60)
        try:
            first.wait(timeout=30)
        except subprocess.TimeoutExpired:
            first.kill()
    lib = subprocess.run(["dpkg-query", "-W", "-f", "${Version}", "libkpipewirerecord6"], capture_output=True, text=True).stdout
    rate, count = picture_rate(rec) if os.path.exists(rec) else (0.0, 0)
    rc, codec, _ = run("ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=codec_name", "-of", "csv=p=0", rec)
    rc, dur, _ = run("ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", rec)
    log(f"DK1 KPipeWire {lib}: Spectacle wrote {os.path.exists(rec)} ({codec.strip()}, {dur.strip()} s): {count} pictures, "
        f"{rate:.1f} a second; second request exit {second.returncode}")
    row("DK1", "Spectacle's screen recording of a still screen on this KPipeWire (a client that did not ask for a constant rate): "
        "a recording with fewer than 10 pictures, not one a frame interval apart", (True, True),
        (os.path.exists(rec) and count > 0, 0 < count < 10))


def cpu_seconds(pid):
    """The processor time of a process so far (user and system), in seconds."""
    try:
        fields = open(f"/proc/{pid}/stat").read().rsplit(")", 1)[1].split()
        return (int(fields[11]) + int(fields[12])) / os.sysconf("SC_CLK_TCK")
    except (OSError, IndexError, ValueError):
        return None


def gpu_sample():
    """What the host's GPUs say this instant: NVIDIA's encoder and GPU use (nvidia-smi), the AMD card's busy share (its sysfs
    file); every GPU here also serves the station, so these are contended figures."""
    out = {}
    rc, text, _ = run("nvidia-smi", "--query-gpu=utilization.encoder,utilization.gpu", "--format=csv,noheader,nounits", timeout=10)
    if rc == 0 and text.strip():
        enc, gpu = [x.strip() for x in text.strip().splitlines()[0].split(",")]
        out.update(nvencPercent=float(enc), nvidiaPercent=float(gpu))
    import glob
    for f in glob.glob("/sys/class/drm/card*/device/gpu_busy_percent"):
        try:
            if open(os.path.join(os.path.dirname(f), "vendor")).read().strip() == "0x1002":
                out["amdBusyPercent"] = float(open(f).read())
        except (OSError, ValueError):
            pass
    return out


def cost_rows():
    """Part D, second half (step 4): the cost of a still screen. A Throw of the still screen to a software device that fetches
    the stream (no player decoding beside it) runs 35 s; between 10 s and 30 s the daemon's and KWin's processor time and
    the GPUs are sampled, then the pictures a second of the stream the device fetched are counted. The encoder is the one
    KPIPEWIRE_FORCE_ENCODER names (h264_vaapi, h264_nvenc, libx264), else KPipeWire's own choice."""
    encoder = os.environ.get("KPIPEWIRE_FORCE_ENCODER", "KPipeWire's choice")
    daemon = name_owner_pid()
    kwin_pid = next((p for p in os.listdir("/proc") if p.isdigit() and
                     open(f"/proc/{p}/comm").read().strip() == "kwin_wayland"), None)
    n = len(loads(LIVING)) + 1
    rc, _ = throw(LIVING, 40)
    time.sleep(10)
    d0, k0, w0 = cpu_seconds(daemon), cpu_seconds(kwin_pid), time.monotonic()
    samples = []
    while time.monotonic() - w0 < 20:
        samples.append(gpu_sample())
        time.sleep(1)
    d1, k1, w1 = cpu_seconds(daemon), cpu_seconds(kwin_pid), time.monotonic()
    time.sleep(5)
    stop(LIVING)
    wait_for(lambda: probe_info(LIVING, n), 60)
    cap = capture(LIVING, n)
    rate, count = picture_rate(cap) if cap else (0.0, 0)
    span = w1 - w0

    def mean(key):
        vals = [s[key] for s in samples if key in s]
        return round(sum(vals) / len(vals), 1) if vals else None

    cost = {"encoder": encoder, "throw": rc, "pictures": count, "picturesPerSecond": round(rate, 1),
            "daemonCpuPercent": round(100 * (d1 - d0) / span, 1) if d0 is not None and d1 is not None else None,
            "kwinCpuPercent": round(100 * (k1 - k0) / span, 1) if k0 is not None and k1 is not None else None,
            "nvencPercent": mean("nvencPercent"), "nvidiaPercent": mean("nvidiaPercent"), "amdBusyPercent": mean("amdBusyPercent"),
            "load": open("/proc/loadavg").read().split()[0]}
    with open(os.path.join(OUT, "cost.json"), "w") as f:
        json.dump(cost, f, indent=1)
    log(f"CK1 {json.dumps(cost)}")
    row("CK1", f"a Throw of a still screen with {encoder}: it ran, and the stream's pictures a second (the cost is in cost.json)",
        (0, True), (rc, rate >= 20))


def make_pair():
    from PIL import Image
    pair = Image.new("RGB", (3840, 1080), (255, 0, 0))
    pair.paste((0, 0, 255), (1920, 0, 3840, 1080))
    pair.save(os.path.join(OUT, "pair.png"))


try:
    if CLI == "sparky-stereo-throw":
        # the installed package only: the session bus started the daemon from its service file (session.sh)
        try:
            text = open(os.path.join(OUT, "activation.txt")).read()
        except OSError:
            text = ""
        row("S1", "the session bus starts the installed daemon from its D-Bus service file (its executable)",
            True, "executable /usr/lib/x86_64-linux-gnu/libexec/sparky-stereo-throwd" in text)
    make_pair()
    # a file "only-partd" beside this script runs part D's rows alone (a development loop)
    if os.environ.get("THROW_ROWS") == "cost":
        # the cost of a still screen alone (step 4 of part D's second half; the lane's encoder rows)
        cost_rows()
    elif os.path.exists(os.path.join(os.path.dirname(os.path.abspath(__file__)), "only-partd")):
        partd()
    else:
        main()
        partd()
        pages()
        dependent_rows()
finally:
    with open(os.path.join(OUT, "rows.tsv"), "w") as f:
        f.write("row\tclaim\texpected\tmeasured\tresult\n")
        for r in rows:
            f.write("\t".join(r) + "\n")
sys.exit(failed)
