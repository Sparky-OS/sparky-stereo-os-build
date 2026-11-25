#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-2.0-or-later
"""The loopback proof's scenario (session.sh starts it): discovery, a Throw and its stream, the pair on the thrown
network screen, the failures said, the unknown model told once, and what a device lets the PC read and set without an
account. Each claim is a row of OUT/rows.tsv; the exit status is the number of rows not as expected.

Usage: scenario.py OUT_DIR CLI
"""
import json
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


def probe(id_, n):
    for e in events(id_, "probe"):
        if e.get("file", "").endswith(f"capture-{n}.mkv"):
            streams = e.get("info", {}).get("streams", [])
            return streams[0] if streams else {}
    return None


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


def place_fixture(screen_name):
    kwin_script("const s = workspace.screens.find(o => o.name == '%s');"
                "for (const w of workspace.windowList()) { if (w.desktopFileName == 'org.kde.kwin.capturefixture') {"
                " workspace.sendClientToScreen(w, s); w.frameGeometry = {x: s.geometry.x, y: s.geometry.y, width: w.frameGeometry.width,"
                " height: w.frameGeometry.height}; workspace.activeWindow = w; } }" % screen_name)


def last_frame(id_, n, name):
    src = os.path.join(DEV, id_, f"capture-{n}.mkv")
    dst = os.path.join(OUT, "frames", name + ".png")
    run("ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-sseof", "-0.5", "-i", src, "-frames:v", "1", "-update", "1", dst)
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
    found = wait_for(lambda: (lambda d: d if len(d) >= 5 else None)(devices()), 30) or devices()
    row("D1", "the five devices announced on the network are found by themselves (ids)",
        sorted([LIVING, BEDROOM, STUDY, HALL, DEN]), sorted(found))
    d = found.get(LIVING, {})
    row("D2", "a device as it names itself: name, model, address", ("Living room TV", "Chromecast", "10.81.0.1"),
        (d.get("name"), d.get("model"), d.get("address")))
    row("D3", "the device table's rows: Chromecast, Ultra, unknown model, Google TV Streamer (mode, known)",
        [("1920x1080@30", True), ("1920x1080@30", True), ("1920x1080@30", False), ("3840x2160@30", True)],
        [(found.get(i, {}).get("mode"), found.get(i, {}).get("known")) for i in (LIVING, BEDROOM, STUDY, DEN)])
    rc, out, _ = run(CLI, "list")
    try:
        names = [d["name"] for d in json.loads(out)]
    except (json.JSONDecodeError, KeyError):
        names = []
    row("D4", "the devices are listed in the order of their names", ["Bedroom TV", "Den TV", "Hall TV", "Living room TV", "Study screen"],
        names)

    # --- a Throw to a first-generation Chromecast
    name = f"Virtual-{LIVING}"
    row("T0", "no network screen for the device before the Throw", False, name in screens())
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
    time.sleep(8)
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
    if fixture:
        fixture.terminate()

    # --- failures said (red rows on purpose)
    rc, out = throw(BEDROOM, 30)
    row("F1", "a device that refuses to launch the player: the Throw fails and says so", (1, True),
        (rc, "refused to start its media player: NOT_FOUND" in out))
    row("F2", "its network screen is removed after the failure", False, bool(wait_for(lambda: f"Virtual-{BEDROOM}" in screens(), 2) and
                                                                         f"Virtual-{BEDROOM}" in screens()))
    pr = problems()
    row("F3", "the failure is kept in the problems engine for that device", True, f"throw:{BEDROOM}" in pr)
    rc, out = throw(HALL, 30)
    lost = wait_for(lambda: devices().get(HALL, {}).get("state") == "failed", 45)
    row("F4", "a device that stops answering the heartbeat: the Throw ends and says so (state, detail)", (True, True),
        (bool(lost), "stopped answering" in devices().get(HALL, {}).get("detail", "")))
    row("F5", "its network screen is gone", False, f"Virtual-{HALL}" in screens())

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

    # --- a Google TV Streamer: 4K in H.264
    rc, out = throw(DEN, 60)
    # software H.264 at 3840x2160 can take a while for its first keyframe on a loaded machine: wait for it, then 4 s
    keyframe = wait_for(lambda: 'the first keyframe went to "Den TV"' in open(os.path.join(OUT, "throwd.log")).read(), 90)
    log(f"4K first keyframe seen: {bool(keyframe)}")
    time.sleep(4)
    stop(DEN)
    s = wait_for(lambda: probe(DEN, 1), 60) or {}
    row("K1", "a Google TV Streamer gets 3840x2160 H.264 (codec, size)", (0, "h264", 3840, 2160),
        (rc, s.get("codec_name"), s.get("width"), s.get("height")))

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
    row("I4", "no request carried an account token", 0, len(tokens))
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
        return [w.get("caption", "") for w in json.loads(out.strip().splitlines()[-1])]
    except (json.JSONDecodeError, IndexError, AttributeError):
        return []


def page(name, args=(), lang=None):
    """The Throw page in System Settings, as the person opens it; a capture of the screen it shows on, the window
    captions while it is open, and the device setup requests made while it is open."""
    env = dict(os.environ, QT_QPA_PLATFORM="wayland")
    if os.path.isdir("/tools/plugins"):
        env["QT_PLUGIN_PATH"] = "/tools/plugins"
    if lang:
        # gettext translates nothing while LC_ALL is C (the image's environment sets it): all three together
        env["LANGUAGE"] = lang
        env["LANG"] = env["LC_ALL"] = f"{lang}.UTF-8"
    before = len(events(LIVING, "eureka"))
    shell = subprocess.Popen(["systemsettings", "kcm_sparkystereo_throw", *args], env=env, stdout=subprocess.DEVNULL,
                             stderr=open(os.path.join(OUT, f"page-{name}.log"), "w"))
    time.sleep(12)
    png = os.path.join(OUT, "frames", f"page-{name}.png")
    rc, out, err = run("python3", "-I", "/rigtools/capture.py", png, timeout=60)
    shown = captions()
    asked = len(events(LIVING, "eureka")) - before
    shell.terminate()
    try:
        shell.wait(10)
    except subprocess.TimeoutExpired:
        shell.kill()
    log(f"page {name}: captured {rc == 0 and os.path.exists(png)}, captions {shown}, setup requests to Living room TV {asked}")
    return {"captured": rc == 0 and os.path.exists(png), "captions": shown, "asked": asked}


def pages():
    first = page("devices")
    row("C1", "the Throw page opens in System Settings (its window's caption) and is captured", (True, True),
        (any(c.startswith("Throw") and "System Settings" in c for c in first["captions"]), first["captured"]))
    second = page("living-room", ["--args", f"device={LIVING}"])
    row("C2", "a device's page opens from the page's argument: it asks the device for its information (setup requests) "
        "and is captured", (True, True), (second["asked"] > 0, second["captured"]))
    third = page("living-room-pt_BR", ["--args", f"device={LIVING}"], "pt_BR")
    row("C3", "the device's page in Brazilian Portuguese (caption \"Throw (jogar)\", setup requests) is captured",
        (True, True, True), (any(c.startswith("Throw (jogar)") for c in third["captions"]), third["asked"] > 0, third["captured"]))


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
    main()
    pages()
finally:
    with open(os.path.join(OUT, "rows.tsv"), "w") as f:
        f.write("row\tclaim\texpected\tmeasured\tresult\n")
        for r in rows:
            f.write("\t".join(r) + "\n")
sys.exit(failed)
