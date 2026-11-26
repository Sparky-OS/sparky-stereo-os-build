#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright 2026 Daniel Campos Ramos
"""make-pdf.py OUT.pdf WIDTH_PT HEIGHT_PT -- a two-page PDF whose pages carry colour-keyed marks, for the paper depth proof.

Page 1: a red square near the top left and a green bar; page 2: a blue square near the top left and a green bar. The marks
are solid DeviceRGB rectangles (no fonts, no images), so each one is one colour a script finds in each eye.
"""
import sys

out, width, height = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])


def page_content(r, g, b):
    s = min(width, height) / 5
    lines = [
        f"{r} {g} {b} rg {s:.2f} {height - 2 * s:.2f} {s:.2f} {s:.2f} re f",  # the square, near the top left
        f"0 1 0 rg {width / 2:.2f} {s / 2:.2f} {s / 4:.2f} {height - s:.2f} re f",  # a green bar down the middle
    ]
    return "\n".join(lines).encode()


contents = [page_content(1, 0, 0), page_content(0, 0, 1)]
objects = []
objects.append(b"<< /Type /Catalog /Pages 2 0 R >>")
kids = " ".join(f"{3 + 2 * i} 0 R" for i in range(len(contents)))
objects.append(f"<< /Type /Pages /Kids [{kids}] /Count {len(contents)} >>".encode())
for i, content in enumerate(contents):
    page_obj = 3 + 2 * i
    objects.append(f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {width:.2f} {height:.2f}] /Contents {page_obj + 1} 0 R "
                   f"/Resources << >> >>".encode())
    objects.append(b"<< /Length %d >>\nstream\n" % len(content) + content + b"\nendstream")

pdf = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
offsets = []
for number, body in enumerate(objects, start=1):
    offsets.append(len(pdf))
    pdf += f"{number} 0 obj\n".encode() + body + b"\nendobj\n"
xref = len(pdf)
pdf += f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode()
for offset in offsets:
    pdf += f"{offset:010d} 00000 n \n".encode()
pdf += f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
with open(out, "wb") as f:
    f.write(pdf)
