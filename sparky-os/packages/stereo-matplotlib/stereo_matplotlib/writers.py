# SPDX-License-Identifier: MIT
"""Stereo pictures written with each format's own mark.

PNG: the registered chunk sTER (Extensions to the PNG 1.2 Specification, version 1.4.0, section 3.6), mode 1
(diverging: the left eye's picture on the left), before the first IDAT, with the padding columns the section asks for
so that the right picture starts on a column divisible by eight; the file is named .pns.
JPEG: the JPS block in an APP3 segment, made by the stereo layer's own encoder (libstereo-policy,
stereo_jps_encode), stored as the layer stores a side-by-side pair by default: the right eye's picture first, the
block saying so (VRex's General Purpose Stereoscopic Data Descriptor, 1997: type 1, layout 2, bit 18 clear).

A writer only ever creates a new file: an existing path is refused unless the caller passes replace=True, and the
file appears whole or not at all (a temporary file in the same folder, renamed when complete).
"""
import ctypes
import ctypes.util
import io
import os
import struct
import tempfile
import zlib

import numpy as np

__all__ = ['PNG_SIGNATURE', 'sTER_padding', 'pns_bytes', 'jps_bytes', 'write_pns', 'write_jps', 'read_png_chunks',
           'StereoFileExists']

PNG_SIGNATURE = b'\x89PNG\r\n\x1a\n'
JPS_SIDE_BY_SIDE_RIGHT_FIRST = 0x00000201
JPS_LEFT_FIRST = 1 << 18


class StereoFileExists(FileExistsError):
    """The target exists; the module writes only new files unless asked to replace one."""


def sTER_padding(width):
    """PNG Extensions 1.4.0, 3.6: padding := 7 - ((subimage_width - 1) mod 8)."""
    return 7 - ((width - 1) % 8)


def _pair(left, right):
    left, right = np.asarray(left), np.asarray(right)
    if left.shape != right.shape or left.ndim != 3:
        raise ValueError('both eyes must be pictures of the same size')
    return left, right


def _png(array):
    from PIL import Image
    buffer = io.BytesIO()
    mode = 'RGBA' if array.shape[2] == 4 else 'RGB'
    Image.fromarray(np.ascontiguousarray(array), mode).save(buffer, format='PNG', optimize=False)
    return buffer.getvalue()


def read_png_chunks(data):
    """(type, body) of every chunk, the CRC of each checked; raises ValueError on a bad datastream."""
    if data[:8] != PNG_SIGNATURE:
        raise ValueError('not a PNG datastream')
    pos, chunks = 8, []
    while pos < len(data):
        if pos + 12 > len(data):
            raise ValueError('truncated chunk')
        length, kind = struct.unpack('>I4s', data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        crc, = struct.unpack('>I', data[pos + 8 + length:pos + 12 + length])
        if zlib.crc32(kind + body) & 0xffffffff != crc:
            raise ValueError('bad CRC in ' + kind.decode('latin-1'))
        chunks.append((kind, body))
        pos += 12 + length
    return chunks


def pns_bytes(left, right):
    """A PNG of the pair, left eye first, with the padding columns and the sTER chunk (mode 1) after IHDR."""
    left, right = _pair(left, right)
    pad = sTER_padding(left.shape[1])
    filler = np.repeat(left[:, -1:], pad, axis=1)
    whole = np.concatenate([left, filler, right], axis=1)
    out = [PNG_SIGNATURE]
    for kind, body in read_png_chunks(_png(whole)):
        out.append(struct.pack('>I', len(body)) + kind + body + struct.pack('>I', zlib.crc32(kind + body) & 0xffffffff))
        if kind == b'IHDR':
            chunk = b'sTER' + b'\x01'
            out.append(struct.pack('>I', 1) + chunk + struct.pack('>I', zlib.crc32(chunk) & 0xffffffff))
    return b''.join(out)


class _JpsDescriptor(ctypes.Structure):
    _fields_ = [('value', ctypes.c_uint32), ('extension', ctypes.c_char_p), ('comment', ctypes.c_char_p),
                ('extension_size', ctypes.c_uint16), ('comment_size', ctypes.c_uint16)]


def _policy():
    lib = ctypes.CDLL('libstereo-policy.so.1')
    lib.stereo_jps_encode.argtypes = [ctypes.POINTER(_JpsDescriptor), ctypes.c_void_p, ctypes.c_size_t]
    lib.stereo_jps_encode.restype = ctypes.c_size_t
    return lib


def jps_segment(value=JPS_SIDE_BY_SIDE_RIGHT_FIRST):
    """The APP3 segment (marker, length, payload) whose payload the stereo layer's encoder writes."""
    lib = _policy()
    descriptor = _JpsDescriptor(value, None, None, 0, 0)
    payload = ctypes.create_string_buffer(256)
    size = lib.stereo_jps_encode(ctypes.byref(descriptor), payload, len(payload))
    if size == 0 or size > len(payload):
        raise RuntimeError('the stereo layer did not encode the JPS block')
    body = payload.raw[:size]
    return b'\xff\xe3' + struct.pack('>H', len(body) + 2) + body


def jps_bytes(left, right, quality=95):
    """A JPEG of the pair stored right eye first, with the stereo layer's JPS block after SOI and any APP0."""
    from PIL import Image
    left, right = _pair(left, right)
    whole = np.concatenate([right, left], axis=1)[..., :3]
    buffer = io.BytesIO()
    Image.fromarray(np.ascontiguousarray(whole), 'RGB').save(buffer, format='JPEG', quality=quality, subsampling=0)
    jpeg = buffer.getvalue()
    at = 2
    if jpeg[2:4] == b'\xff\xe0':
        at = 4 + struct.unpack('>H', jpeg[4:6])[0]
    return jpeg[:at] + jps_segment() + jpeg[at:]


def _write_new(path, data, replace):
    path = os.fspath(path)
    if os.path.lexists(path) and not replace:
        raise StereoFileExists(path)
    folder = os.path.dirname(os.path.abspath(path))
    fd, temporary = tempfile.mkstemp(prefix='.stereo-', dir=folder)
    try:
        with os.fdopen(fd, 'wb') as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(temporary, 0o666 & ~_umask())
        os.replace(temporary, path)
    except BaseException:
        if os.path.exists(temporary):
            os.unlink(temporary)
        raise
    return path


def _umask():
    mask = os.umask(0)
    os.umask(mask)
    return mask


def write_pns(path, left, right, replace=False):
    return _write_new(path, pns_bytes(left, right), replace)


def write_jps(path, left, right, replace=False, quality=95):
    return _write_new(path, jps_bytes(left, right, quality), replace)
