# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-3.0-or-later
"""Reading and writing Java KeyStore files of the JKS type that hold trusted certificates only.

The format is the one the JDK's sun.security.provider.JavaKeyStore writes: the magic 0xFEEDFEED, the version 2, the number of
entries, then each entry (tag 2 for a trusted certificate, an alias in modified UTF-8, the time in milliseconds, the
certificate type "X.509", the length and the bytes of the certificate), and the store's SHA-1 digest over the password
(UTF-16BE), the text "Mighty Aphrodite" and everything before the digest. An entry with a private key (tag 1) is refused:
the store PJeOffice Pro ships holds trusted certificates only, and a key must never pass through this code.
"""
import hashlib
import struct

MAGIC = 0xFEEDFEED
WHITENER = b'Mighty Aphrodite'


class KeyStoreError(ValueError):
    pass


def _digest(password, body):
    return hashlib.sha1(password.encode('utf-16-be') + WHITENER + body).digest()


def read(data, password):
    """The entries of a JKS store as [(alias, timestamp, certificate DER)], in file order; the digest is checked."""
    if len(data) < 32:
        raise KeyStoreError('the key store is too short')
    body, digest = data[:-20], data[-20:]
    if _digest(password, body) != digest:
        raise KeyStoreError('the key store digest does not match (a wrong password or a damaged file)')
    magic, version, count = struct.unpack('>III', body[:12])
    if magic != MAGIC or version != 2:
        raise KeyStoreError('not a JKS version 2 key store')
    entries, at = [], 12
    try:
        for _ in range(count):
            (tag,) = struct.unpack('>I', body[at:at + 4])
            at += 4
            if tag != 2:
                raise KeyStoreError('entry with tag %d: only trusted certificates are accepted' % tag)
            (length,) = struct.unpack('>H', body[at:at + 2])
            alias = body[at + 2:at + 2 + length].decode('utf-8')
            at += 2 + length
            (stamp,) = struct.unpack('>Q', body[at:at + 8])
            at += 8
            (length,) = struct.unpack('>H', body[at:at + 2])
            kind = body[at + 2:at + 2 + length]
            at += 2 + length
            if kind != b'X.509':
                raise KeyStoreError('certificate type %r is not X.509' % kind)
            (length,) = struct.unpack('>I', body[at:at + 4])
            der = body[at + 4:at + 4 + length]
            if len(der) != length:
                raise KeyStoreError('the key store ends inside a certificate')
            at += 4 + length
            entries.append((alias, stamp, der))
    except struct.error as error:
        raise KeyStoreError('the key store is damaged: %s' % error)
    if at != len(body):
        raise KeyStoreError('the key store has %d bytes after its last entry' % (len(body) - at))
    return entries


def write(entries, password):
    body = struct.pack('>III', MAGIC, 2, len(entries))
    for alias, stamp, der in entries:
        name = alias.encode('utf-8')
        body += struct.pack('>IH', 2, len(name)) + name + struct.pack('>QH', stamp, 5) + b'X.509'
        body += struct.pack('>I', len(der)) + der
    return body + _digest(password, body)
