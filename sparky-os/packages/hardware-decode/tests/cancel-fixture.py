# H.264 SEI payload 45, id ue(0), cancel=1, extension=0, payload alignment 1,
# then rbsp trailing bits. FFmpeg cbs_h264_syntax_template.c:807-835.
from pathlib import Path
p = Path('/w/fixtures')
sei_cancel = bytes.fromhex('00000001062d01d080')
(p / 'h264-cancel8.h264').write_bytes((p / 'marked.h264').read_bytes() + sei_cancel + (p / 'mono.h264').read_bytes())
