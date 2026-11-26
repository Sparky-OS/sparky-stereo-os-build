#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
"""Generate the rig's synthetic display and two-page Words document."""
import sys
from pathlib import Path
from zipfile import ZIP_STORED, ZipFile

OFFICE = "urn:oasis:names:tc:opendocument:xmlns:office:1.0"
STYLE = "urn:oasis:names:tc:opendocument:xmlns:style:1.0"
TEXT = "urn:oasis:names:tc:opendocument:xmlns:text:1.0"
FO = "urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
MIME = "application/vnd.oasis.opendocument.text"


def make_edid(path):
    # EDID 1.4, preferred 1920×1080 at 60 Hz, 530×300 mm.
    edid = bytearray(128)
    edid[:25] = bytes.fromhex("00ffffffffffff004ded010001000000011e0104a2351e7806")
    edid[25:35] = bytes.fromhex("ee91a3544c99260f5054")
    edid[35:54] = bytes.fromhex("00000001010101010101010101010101010101")
    edid[54:72] = bytes.fromhex("023a801871382d40582c4500122c2100001e")
    edid[72:90] = b"\x00\x00\x00\xfc\x00Sparky Rig\n  "
    edid[90:108] = b"\x00\x00\x00\xff\x00PaperDepth\n  "
    edid[108:126] = bytes.fromhex("000000fd00324b1e5311000a202020202020")
    assert len(edid) == 128
    edid[127] = -sum(edid) % 256
    path.write_bytes(edid)


def make_odt(path):
    styles = f"""<office:document-styles xmlns:office="{OFFICE}" xmlns:style="{STYLE}" xmlns:fo="{FO}" office:version="1.2">
      <office:automatic-styles>
        <style:page-layout style:name="Paper">
          <style:page-layout-properties fo:page-width="13cm" fo:page-height="10cm" fo:margin="1cm"/>
        </style:page-layout>
      </office:automatic-styles>
      <office:master-styles><style:master-page style:name="Standard" style:page-layout-name="Paper"/></office:master-styles>
    </office:document-styles>"""
    content = f"""<office:document-content xmlns:office="{OFFICE}" xmlns:style="{STYLE}" xmlns:text="{TEXT}"
                         xmlns:fo="{FO}" xmlns:dc="http://purl.org/dc/elements/1.1/" office:version="1.2">
      <office:automatic-styles>
        <style:style style:name="NextPage" style:family="paragraph"><style:paragraph-properties fo:break-before="page"/></style:style>
      </office:automatic-styles>
      <office:body><office:text>
        <text:p>Paper depth, page one</text:p>
        <text:p>The text marks the plane of the page.<office:annotation><dc:creator>Rig</dc:creator><text:p>Page one comment</text:p></office:annotation></text:p>
        <text:p>One more line at a known horizontal position.</text:p>
        <text:p text:style-name="NextPage">Paper depth, page two</text:p>
        <text:p>The second page has a different mark.<office:annotation><dc:creator>Rig</dc:creator><text:p>Page two comment</text:p></office:annotation></text:p>
        <text:p>One more line at a known horizontal position.</text:p>
      </office:text></office:body>
    </office:document-content>"""
    manifest_ns = "urn:oasis:names:tc:opendocument:xmlns:manifest:1.0"
    manifest = f"""<manifest:manifest xmlns:manifest="{manifest_ns}" manifest:version="1.2">
      <manifest:file-entry manifest:full-path="/" manifest:media-type="{MIME}"/>
      <manifest:file-entry manifest:full-path="styles.xml" manifest:media-type="text/xml"/>
      <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
    </manifest:manifest>"""
    with ZipFile(path, "w", compression=ZIP_STORED) as archive:
        archive.writestr("mimetype", MIME)
        archive.writestr("styles.xml", styles)
        archive.writestr("content.xml", content)
        archive.writestr("META-INF/manifest.xml", manifest)


if __name__ == "__main__":
    make_edid(Path(sys.argv[1]))
    make_odt(Path(sys.argv[2]))
