#!/usr/bin/env python3
"""Lay out unaltered reference and capture images in a labelled review sheet."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[1] / 'evidence'
font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 18)
small = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf', 14)
canvas = Image.new('RGB', (2040, 1130), '#f5f5f2')
draw = ImageDraw.Draw(canvas)
draw.text((16, 18), 'Apple appearance guidelines (1997)', font=font, fill='black')
draw.text((424, 18), 'Kubabbar Glass: live 2D OpenGL capture', font=font, fill='black')
canvas.paste(Image.open(root / 'reference/apple-1997-appearance.png').convert('RGB'), (16, 64))
canvas.paste(Image.open(root / '2d/desktop.png').convert('RGB'), (424, 64))
for i, text in enumerate(['Reference: Apple Computer, Inc.', 'Figure 1-4, Appearance control panel.', 'Historical comparison only.', 'No reference artwork in the theme.', '', 'Original geometry and DejaVu Sans.', 'Third box: minimize placeholder.', 'Qt widgets and GTK: milestone 2.']):
    draw.text((16, 380+i*24), text, font=small, fill='black')
draw.text((16, 1090), 'Source links, limits and design comparison: evidence/reference/README.md. Captures are not a final appearance approval.', font=small, fill='black')
canvas.save(root / 'reference/comparison.png')
