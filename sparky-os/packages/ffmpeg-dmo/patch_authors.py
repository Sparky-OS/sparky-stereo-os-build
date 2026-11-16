"""Keep carried patch credits without publishing third-party addresses."""
from pathlib import Path
import re


def sanitize(text):
    # Only metadata changes. The diff remains byte-for-byte identical.
    split = re.search(r"^(?:diff --git |--- (?:a/|/dev/null))", text, re.M)
    end = split.start() if split else len(text)
    header, diff = text[:end], text[end:]
    header = re.sub(
        r"<(?!Capitain_Jack@yahoo\.com>)[^<>\s]+@[^<>\s]+>", "", header
    )
    header = re.sub(r"[ \t]+$", "", header, flags=re.M)
    if not re.search(r"^Origin:", header, re.M):
        commit = re.search(r"^From ([0-9a-f]{40}) ", header, re.M)
        if commit:
            origin = "https://git.ffmpeg.org/gitweb/ffmpeg.git/commit/" + commit[1]
            author = re.search(r"^From: (.+)$", header, re.M)
            metadata = ("Author: " + author[1] + "\n") if author else ""
            header = metadata + "Origin: upstream, " + origin + "\n" + header
    header = re.sub(
        r"Origin: other, FFmpeg port commit ([0-9a-f]{40})",
        r"Origin: other, https://code.ffmpeg.org/danielcamposramos/FFmpeg/commit/\1",
        header,
    )
    return header + diff


def sanitize_patches(directory):
    for patch in sorted(Path(directory).glob("*.patch")):
        text = patch.read_text()
        clean = sanitize(text)
        if clean != text:
            patch.write_text(clean)
