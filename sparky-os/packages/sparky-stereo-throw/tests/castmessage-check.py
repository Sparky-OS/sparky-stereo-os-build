#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
# SPDX-License-Identifier: GPL-2.0-or-later
"""The daemon's hand-written CastMessage against pychromecast's generated protobuf module, both ways.

Usage: castmessage-check.py PATH_TO_castmessage-vectors
Exit status: the number of cases that differ.
"""
import json
import struct
import subprocess
import sys

from pychromecast.generated import cast_channel_pb2 as pb

CASES = [
    {"src": "sender-0", "dst": "receiver-0", "ns": "urn:x-cast:com.google.cast.tp.connection", "payload": '{"type":"CONNECT"}'},
    {"src": "sender-0", "dst": "receiver-0", "ns": "urn:x-cast:com.google.cast.tp.heartbeat", "payload": '{"type":"PING"}'},
    {"src": "sender-0", "dst": "receiver-0", "ns": "urn:x-cast:com.google.cast.receiver",
     "payload": '{"appId":"CC1AD845","requestId":3,"type":"LAUNCH"}'},
    {"src": "sender-0", "dst": "web-1", "ns": "urn:x-cast:com.google.cast.media",
     "payload": json.dumps({"type": "LOAD", "requestId": 4, "autoplay": True, "media": {
         "contentId": "http://10.81.0.1:41234/" + "k" * 26 + ".mkv", "contentType": "video/x-matroska", "streamType": "LIVE"}},
         separators=(",", ":"))},
    # a name with letters outside ASCII, and a payload over 127 bytes (two-byte length)
    {"src": "sender-0", "dst": "receiver-0", "ns": "urn:x-cast:com.google.cast.receiver",
     "payload": json.dumps({"type": "SET_VOLUME", "requestId": 9, "volume": {"level": 0.25}, "note": "Sala de estar, TV da Lívia " * 4},
                           ensure_ascii=False, separators=(",", ":"))},
    {"src": "sender-0", "dst": "receiver-0", "ns": "urn:x-cast:com.google.cast.tp.deviceauth", "binary_hex": "0a0412021234"},
]
# Cast V2 message chunking: fields 8 continued and 9 remaining_length (openscreen cast/common/channel/proto/cast_channel.proto,
# last changed 37a17677e5); the data of each chunk in payload_binary, the payload type the message's own (message_chunker.cc,
# 64d7c985d1). pychromecast's generated module predates the two fields, so they are appended by hand in field order.
CHUNKS = [('{"type":"RECEIVER_STATUS",', True, 27), ('"status":{},"requestId":1}', False, 0)]


def reference(case):
    m = pb.CastMessage()
    m.protocol_version = m.CASTV2_1_0
    m.source_id = case["src"]
    m.destination_id = case["dst"]
    m.namespace = case["ns"]
    if "binary_hex" in case:
        m.payload_type = m.BINARY
        m.payload_binary = bytes.fromhex(case["binary_hex"])
    else:
        m.payload_type = m.STRING
        m.payload_utf8 = case["payload"]
    body = m.SerializeToString()
    return (struct.pack(">I", len(body)) + body).hex()


def varint(value):
    out = b""
    while True:
        byte = value & 0x7F
        value >>= 7
        out += bytes([byte | (0x80 if value else 0)])
        if not value:
            return out


def field(number, value):
    if isinstance(value, int):
        return varint(number << 3) + varint(value)
    return varint(number << 3 | 2) + varint(len(value)) + value


def chunk(data, continued, remaining):
    # written field by field from cast_channel.proto, protocol version CASTV2_1_2 (2), payload type STRING (0)
    body = (field(1, 2) + field(2, b"receiver-0") + field(3, b"sender-0") + field(4, b"urn:x-cast:com.google.cast.receiver")
            + field(5, 0) + field(7, data.encode()) + field(8, int(continued)) + field(9, remaining))
    return (struct.pack(">I", len(body)) + body).hex()


def main():
    tool = sys.argv[1]
    lines = "\n".join(json.dumps(c, ensure_ascii=False) for c in CASES) + "\n"
    ours = subprocess.run([tool, "encode"], input=lines, capture_output=True, text=True, check=True).stdout.split()
    bad = 0
    for case, got in zip(CASES, ours):
        want = reference(case)
        ok = got == want
        bad += not ok
        print(("PASS" if ok else "FAIL"), "encode", case["ns"].rsplit(".", 1)[-1], len(want) // 2, "bytes")
        if not ok:
            print("  ours  ", got)
            print("  theirs", want)
    # decode what pychromecast encodes; the chunked pair joins into one message
    whole = CASES
    frames = "\n".join([reference(c) for c in whole] + [chunk(*c) for c in CHUNKS]) + "\n"
    decoded = subprocess.run([tool, "decode"], input=frames, capture_output=True, text=True).stdout.splitlines()
    for case, line in zip(whole, decoded):
        got = json.loads(line)
        ok = got["src"] == case["src"] and got["dst"] == case["dst"] and got["ns"] == case["ns"] and (
            got["binary_hex"] == case["binary_hex"] if "binary_hex" in case else got["payload"] == case["payload"])
        bad += not ok
        print(("PASS" if ok else "FAIL"), "decode", case["ns"].rsplit(".", 1)[-1])
    joined = json.loads(decoded[len(whole)]) if len(decoded) > len(whole) else {}
    ok = joined.get("payload") == "".join(c[0] for c in CHUNKS) and joined.get("type") == 0
    bad += not ok
    print(("PASS" if ok else "FAIL"), "decode chunked pair joined:", joined.get("payload"))
    print("RESULT:", "PASS" if not bad else f"FAIL ({bad})")
    return bad


if __name__ == "__main__":
    sys.exit(main())
