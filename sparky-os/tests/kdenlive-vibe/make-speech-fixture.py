#!/usr/bin/env python3
"""Build a fixed synthetic clip and a timeline with one picture and audio track."""

import argparse
import json
from pathlib import Path
import subprocess
import wave
from xml.etree import ElementTree as ET


SENTENCES = {
    "en": ("The quick brown fox jumps over the lazy dog.", "The blue boat is on the river."),
    "pt-br": ("O barco azul está no rio.", "A porta da casa está aberta."),
}
RATE = 16000
LENGTH = 250
FPS = 25


def command(*args):
    subprocess.run(args, check=True)


def audio(directory, language):
    reference = []
    samples = bytearray(2 * RATE * LENGTH // FPS)
    for start, sentence in zip((1, 6), SENTENCES[language], strict=True):
        rendered = directory / f"utterance-{start}.wav"
        pcm = directory / f"utterance-{start}.pcm"
        command("espeak-ng", "-v", "en-us" if language == "en" else language, "-s", "145", "-w", str(rendered), sentence)
        command("ffmpeg", "-nostdin", "-loglevel", "error", "-i", str(rendered), "-ar", str(RATE), "-ac", "1", "-f", "s16le", str(pcm))
        speech = pcm.read_bytes()
        frames = memoryview(speech).cast("h")
        active = [index for index, amplitude in enumerate(frames) if abs(amplitude) > 64]
        assert active and start + len(frames) / RATE < (6 if start == 1 else LENGTH / FPS)
        reference.append({"text": sentence, "start": start + active[0] / RATE, "end": start + active[-1] / RATE})
        offset = 2 * start * RATE
        samples[offset:offset + len(speech)] = speech
        rendered.unlink()
        pcm.unlink()
    narration = directory / "narration.wav"
    with wave.open(str(narration), "wb") as out:
        out.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        out.writeframes(samples)
    (directory / "reference.json").write_text(json.dumps(reference, indent=2, ensure_ascii=False) + "\n")
    return narration


def element(root, tag, **attrs):
    return ET.SubElement(root, tag, {name.rstrip("_"): str(value) for name, value in attrs.items()})


def properties(root, **values):
    for name, value in values.items():
        element(root, "property", name=name).text = str(value)


def project(path, clip):
    last = LENGTH - 1
    root = ET.Element("mlt", {"LC_NUMERIC": "C", "producer": "main_bin", "version": "7.7.0", "root": "/"})
    element(root, "profile", frame_rate_num=FPS, frame_rate_den=1, width=1280, height=720,
            progressive=1, sample_aspect_num=1, sample_aspect_den=1, display_aspect_num=16,
            display_aspect_den=9, colorspace=709, description="Speech fixture")
    track_types = {"audio": ("1", "video"), "video": ("0", "audio")}
    for name in ("bin", *track_types):
        source = element(root, "producer", id=name, in_=0, out=last)
        props = {"resource": clip, "length": LENGTH, "mlt_service": "avformat", "eof": "pause",
                 "kdenlive:id": 2, "kdenlive:clip_type": 3, "kdenlive:folderid": -1}
        if name in track_types:
            props |= {"set.test_audio": int(name == "video"), "set.test_image": int(name == "audio")}
        properties(source, **props)
    main_bin = element(root, "playlist", id="main_bin")
    document = {"activeTrack": 1, "audioChannels": 2, "audioTarget": 0, "documentid": "1700000000000",
                "kdenliveversion": "22.07.70", "position": 0, "profile": "atsc_720p_25",
                "version": "1.04", "videoTarget": 1, "zonein": 0, "zoneout": last, "zoom": 8}
    properties(main_bin, **{f"kdenlive:docproperties.{name}": value for name, value in document.items()})
    properties(main_bin, **{"kdenlive:docproperties.groups": "[]", "xml_retain": 1})
    element(main_bin, "entry", producer="bin", in_=0, out=last)
    properties(element(root, "producer", id="black_track", in_=0, out=last), length=2147483647,
               eof="continue", resource="black", aspect_ratio=1, mlt_service="color", mlt_image_format="rgba")
    for name, (audio_track, hidden) in track_types.items():
        playlist = element(root, "playlist", id=f"{name}_content")
        properties(element(playlist, "entry", producer=name, in_=0, out=last), **{"kdenlive:id": 2})
        element(root, "playlist", id=f"{name}_empty")
        track = element(root, "tractor", id=f"{name}_track", in_=0, out=last)
        properties(track, **{"kdenlive:audio_track": audio_track, "kdenlive:timeline_active": 1})
        element(track, "track", hide=hidden, producer=f"{name}_content")
        element(track, "track", hide=hidden, producer=f"{name}_empty")
    timeline = element(root, "tractor", id="maintractor", in_=0, out=last)
    for name in ("black_track", "audio_track", "video_track"):
        element(timeline, "track", producer=name, **({"hide": "video"} if name == "audio_track" else {}))
    properties(element(timeline, "transition", id="audio_mix"), a_track=0, b_track=1, mlt_service="mix",
               always_active=1, sum=1, internal_added=237)
    properties(element(timeline, "transition", id="video_composite"), a_track=0, b_track=2, mlt_service="qtblend",
               always_active=1, internal_added=237)
    ET.indent(root)
    ET.ElementTree(root).write(path, encoding="utf-8", xml_declaration=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("language", choices=SENTENCES)
    args = parser.parse_args()
    directory = args.directory.resolve()
    directory.mkdir()
    narration = audio(directory, args.language)
    clip = directory / "speech.mkv"
    command("ffmpeg", "-nostdin", "-loglevel", "error", "-f", "lavfi", "-i",
            f"color=c=0x2c4050:s=1280x720:r={FPS}:d={LENGTH / FPS}", "-i", str(narration),
            "-c:v", "ffv1", "-c:a", "pcm_s16le", "-threads", "2", str(clip))
    project(directory / "speech.kdenlive", clip)


if __name__ == "__main__":
    main()
