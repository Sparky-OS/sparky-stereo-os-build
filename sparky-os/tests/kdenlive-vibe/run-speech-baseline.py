#!/usr/bin/env python3
"""Drive the installed editor's automatic subtitling dialog on the fixed clip."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
import unicodedata

import gi
gi.require_version("Atspi", "2.0")
from gi.repository import Atspi
from PIL import ImageGrab


def xdo(*args):
    subprocess.run(("xdotool", *args), check=True, timeout=10)


def tree(node):
    yield node
    for index in range(node.get_child_count()):
        child = node.get_child_at_index(index)
        if child is not None:
            yield from tree(child)


def showing(node):
    return node.get_state_set().contains(Atspi.StateType.SHOWING)


def find(name, *, visible=True, roles=()):
    for node in tree(Atspi.get_desktop(0)):
        if roles and node.get_role() not in roles:
            continue
        if name.fullmatch((node.get_name() or "").replace("&", "")) and (not visible or showing(node)):
            return node


def wait(callback, seconds, what):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        value = callback()
        if value:
            return value
        time.sleep(0.15)
    raise TimeoutError(what)


def accessible(name, *, seconds=20, roles=()):
    return wait(lambda: find(re.compile(name), roles=roles), seconds, name)


def click(node):
    component = node.get_component_iface()
    point = component.get_extents(Atspi.CoordType.SCREEN)
    if point.width <= 0 or point.height <= 0:
        raise RuntimeError(f"{node.get_name()!r} has no screen rectangle")
    xdo("mousemove", str(point.x + point.width // 2), str(point.y + point.height // 2), "click", "1")


def screenshot(path):
    ImageGrab.grab().save(path)


def words(s):
    raw = unicodedata.normalize("NFKC", s).casefold()
    return re.findall(r"[^\W_]+", raw)


def read_subtitles(path):
    subtitles = []
    for line in path.read_text().splitlines():
        if line.startswith("Dialogue:"):
            fields = line.split(",", 9)
            if len(fields) == 10:
                subtitles.append(tuple(fields[i] for i in (1, 2, 9)))
    return subtitles


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("engine", choices=("vosk", "whisper"))
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    path = args.output
    home = path / "home"
    for subdir in (".config", ".local/share/kdenlive", ".cache", "runtime"):
        (home / subdir).mkdir(parents=True, exist_ok=True)
    speech = f"[speech]\nspeechEngine={args.engine}\nsubtitleMode=1\nwhisperModel=tiny.en\nwhisperDevice=cpu\n"
    speech += f"vosk_folder_path={home}/vosk\n"
    startup = (
        "[version]\nversion=26.08.1\n"
        "[env]\nkdenliverendererpath=/usr/bin/kdenlive_render\nffmpegpath=/usr/bin/ffmpeg\nmeltpath=/usr/bin/melt\n"
        "[startup]\nshowWelcome=false\n"
        "[sdl]\nsdlAudioBackend=dummy\n"
    )
    (home / ".config/kdenliverc").write_text(startup + speech)
    (home / "runtime").chmod(0o700)
    env = os.environ | {
        "HOME": str(home), "XDG_CONFIG_HOME": str(home / ".config"),
        "XDG_DATA_HOME": str(home / ".local/share"), "XDG_CACHE_HOME": str(home / ".cache"),
        "XDG_RUNTIME_DIR": str(home / "runtime"),
        "QT_LINUX_ACCESSIBILITY_ALWAYS_ON": "1", "QT_QPA_PLATFORM": "xcb",
        "LIBGL_ALWAYS_SOFTWARE": "1", "SDL_AUDIODRIVER": "dummy", "OMP_NUM_THREADS": "4", "MKL_NUM_THREADS": "4",
    }
    app_data = Path("/opt/kv74")
    scripts = Path("/usr/share/kdenlive/scripts")
    setup = time.monotonic()
    venv = home / ".local/share/kdenlive/venv"
    subprocess.run(("/usr/bin/python3", "-m", "venv", str(venv)), check=True, env=env)
    python = venv / "bin/python3"
    requirements = ("vosk", "srt") if args.engine == "vosk" else (str(scripts / "whisper/requirements-whisper.txt"),)
    env |= {"PIP_FIND_LINKS": str(app_data / "wheels" / args.engine), "PIP_NO_INDEX": "1", "PIP_DISABLE_PIP_VERSION_CHECK": "1"}
    subprocess.run((python, scripts / "checkpackages.py", "--install", *requirements), check=True, env=env, timeout=180)
    imports = "import vosk,srt" if args.engine == "vosk" else "import whisper,srt,torch"
    subprocess.run((python, "-c", imports), check=True, env=env)
    installed = time.monotonic()
    if args.engine == "vosk":
        model = app_data / "models/vosk-model-small-en-us-0.15.zip"
        model_dir = home / "vosk"
        subprocess.run(("unzip", "-q", model, "-d", model_dir), check=True)
    else:
        model = app_data / "models/tiny.en.pt"
        model_dir = home / ".cache/whisper"
        model_dir.mkdir()
        shutil.copyfile(model, model_dir / model.name)
    configured = time.monotonic()
    project = path / "speech.kdenlive"
    shutil.copyfile(app_data / "clip-en/speech.kdenlive", project)
    Atspi.init()
    with (path / "kdenlive.log").open("w") as log:
        app = subprocess.Popen(("kdenlive", "--no-welcome", project.name), cwd=path, env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            menu_roles = (Atspi.Role.MENU, Atspi.Role.MENU_ITEM)
            starting = wait(lambda: find(re.compile(r"The file or folder +does not exist\.")) or
                            find(re.compile(r"(?:Sequence|Timeline)"), roles=menu_roles), 45, "editor start")
            if starting.get_role() not in menu_roles:
                screenshot(path / "initial-dialog.png")
                click(accessible(r"OK"))
            accessible(r"(?:Sequence|Timeline)", roles=menu_roles)
            screenshot(path / "project.png")
            click(accessible(r"(?:Sequence|Timeline)", roles=menu_roles))
            click(accessible(r"Subtitles", roles=menu_roles))
            click(accessible(r"Speech Recognition[.…]*", roles=menu_roles))
            process = accessible(r"Process")
            wait(lambda: process.get_state_set().contains(Atspi.StateType.ENABLED), 90, "Process enabled")
            screenshot(path / "before-process.png")
            began = time.monotonic()
            click(process)
            wait(lambda: find(re.compile(r"Subtitles imported|Speech recognition finished, subtitles imported")), 120, "subtitles created")
            elapsed = time.monotonic() - began
            screenshot(path / "after-process.png")
            close = find(re.compile(r"Close"))
            if close is not None:
                click(close)
            click(accessible(r"Save", roles=(Atspi.Role.PUSH_BUTTON,)))
            time.sleep(0.6)
            dialog = find(re.compile(r"OK"))
            if dialog is not None:
                click(dialog)
            changed = wait(lambda: next((file for file in path.glob("*.ass") if read_subtitles(file)), None),
                           20, "saved subtitle file with dialogue")
            subtitles = read_subtitles(changed)
            text = words(" ".join(row[2] for row in subtitles))
            assert len({"fox", "dog", "boat", "river"} & set(text)) >= 3, subtitles
            report = {
                "engine": args.engine, "venv_setup_seconds": installed - setup,
                "model_install_seconds": configured - installed,
                "first_subtitle_seconds": elapsed,
                "venv_bytes": int(subprocess.check_output(("du", "-sb", venv), text=True).split()[0]),
                "installed_model_bytes": int(subprocess.check_output(("du", "-sb", model_dir), text=True).split()[0]),
                "downloaded_model_bytes": model.stat().st_size,
                "wheel_bytes": sum(item.stat().st_size for item in (app_data / "wheels" / args.engine).glob("*")),
                "subtitle_file": changed.name, "subtitles": subtitles,
            }
            (path / "result.json").write_text(json.dumps(report, indent=2) + "\n")
        finally:
            screenshot(path / "last.png")
            with (path / "accessible.txt").open("w") as dump:
                for node in tree(Atspi.get_desktop(0)):
                    if showing(node):
                        print(node.get_role_name(), node.get_name(), file=dump)
            app.terminate()
            try:
                app.wait(10)
            except subprocess.TimeoutExpired:
                app.kill()
                app.wait()


if __name__ == "__main__":
    main()
