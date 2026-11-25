// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
#include "castmessage.h"

#include <QJsonDocument>
#include <QtEndian>

namespace Throw
{

namespace
{
// a frame longer than this is not a Cast message: the channel limits a message to 64 KiB, chunking aside
constexpr quint32 MaxFrame = 1024 * 1024;

void putVarint(QByteArray &out, quint64 value)
{
    do {
        quint8 byte = value & 0x7f;
        value >>= 7;
        if (value) {
            byte |= 0x80;
        }
        out.append(char(byte));
    } while (value);
}

void putKey(QByteArray &out, int field, int wireType)
{
    putVarint(out, quint64(field) << 3 | quint64(wireType));
}

void putBytes(QByteArray &out, int field, const QByteArray &bytes)
{
    putKey(out, field, 2);
    putVarint(out, quint64(bytes.size()));
    out.append(bytes);
}

std::optional<quint64> getVarint(const QByteArray &in, qsizetype &pos)
{
    quint64 value = 0;
    for (int shift = 0; shift < 64; shift += 7) {
        if (pos >= in.size()) {
            return std::nullopt;
        }
        const quint8 byte = quint8(in.at(pos++));
        value |= quint64(byte & 0x7f) << shift;
        if (!(byte & 0x80)) {
            return value;
        }
    }
    return std::nullopt;
}
} // namespace

CastMessage CastMessage::json(const QString &source, const QString &destination, const QString &nameSpace, const QJsonObject &payload)
{
    CastMessage message;
    message.sourceId = source;
    message.destinationId = destination;
    message.nameSpace = nameSpace;
    message.payloadType = String;
    message.payloadUtf8 = QJsonDocument(payload).toJson(QJsonDocument::Compact);
    return message;
}

QJsonObject CastMessage::payloadJson() const
{
    return QJsonDocument::fromJson(payloadUtf8).object();
}

QByteArray CastMessage::encode() const
{
    // proto2 required fields are written even when they hold their default, in field order, as protobuf does
    QByteArray out;
    putKey(out, 1, 0);
    putVarint(out, quint64(protocolVersion));
    putBytes(out, 2, sourceId.toUtf8());
    putBytes(out, 3, destinationId.toUtf8());
    putBytes(out, 4, nameSpace.toUtf8());
    putKey(out, 5, 0);
    putVarint(out, quint64(payloadType));
    if (payloadType == String) {
        putBytes(out, 6, payloadUtf8);
    } else {
        putBytes(out, 7, payloadBinary);
    }
    if (continued) {
        putKey(out, 8, 0);
        putVarint(out, *continued ? 1 : 0);
    }
    if (remainingLength) {
        putKey(out, 9, 0);
        putVarint(out, *remainingLength);
    }
    return out;
}

std::optional<CastMessage> CastMessage::decode(const QByteArray &body)
{
    CastMessage message;
    qsizetype pos = 0;
    bool seen[6] = {};
    while (pos < body.size()) {
        const auto key = getVarint(body, pos);
        if (!key) {
            return std::nullopt;
        }
        const int field = int(*key >> 3);
        const int wireType = int(*key & 7);
        if (wireType == 0) {
            const auto value = getVarint(body, pos);
            if (!value) {
                return std::nullopt;
            }
            switch (field) {
            case 1:
                message.protocolVersion = int(*value);
                seen[1] = true;
                break;
            case 5:
                message.payloadType = *value ? Binary : String;
                seen[5] = true;
                break;
            case 8:
                message.continued = *value != 0;
                break;
            case 9:
                message.remainingLength = quint32(*value);
                break;
            default:
                break;
            }
        } else if (wireType == 2) {
            const auto length = getVarint(body, pos);
            if (!length || *length > quint64(body.size() - pos)) {
                return std::nullopt;
            }
            const QByteArray bytes = body.mid(pos, qsizetype(*length));
            pos += qsizetype(*length);
            switch (field) {
            case 2:
                message.sourceId = QString::fromUtf8(bytes);
                seen[2] = true;
                break;
            case 3:
                message.destinationId = QString::fromUtf8(bytes);
                seen[3] = true;
                break;
            case 4:
                message.nameSpace = QString::fromUtf8(bytes);
                seen[4] = true;
                break;
            case 6:
                message.payloadUtf8 = bytes;
                break;
            case 7:
                message.payloadBinary = bytes;
                break;
            default:
                break;
            }
        } else if (wireType == 5) {
            pos += 4;
        } else if (wireType == 1) {
            pos += 8;
        } else {
            return std::nullopt;
        }
    }
    if (pos != body.size() || !seen[1] || !seen[2] || !seen[3] || !seen[4] || !seen[5]) {
        return std::nullopt;
    }
    return message;
}

QByteArray CastMessage::frame() const
{
    const QByteArray body = encode();
    QByteArray out(4, Qt::Uninitialized);
    qToBigEndian(quint32(body.size()), out.data());
    out.append(body);
    return out;
}

void FrameReader::append(const QByteArray &bytes)
{
    m_buffer.append(bytes);
}

std::optional<CastMessage> FrameReader::next()
{
    while (m_buffer.size() >= 4) {
        const quint32 length = qFromBigEndian<quint32>(m_buffer.constData());
        if (length > MaxFrame) {
            m_error = QStringLiteral("a frame of %1 bytes, more than a Cast message can be").arg(length);
            m_buffer.clear();
            return std::nullopt;
        }
        if (m_buffer.size() < qsizetype(4 + length)) {
            return std::nullopt;
        }
        const auto message = CastMessage::decode(m_buffer.mid(4, length));
        m_buffer.remove(0, 4 + length);
        if (!message) {
            m_error = QStringLiteral("a message that is not a CastMessage");
            continue;
        }
        if (!message->continued.value_or(false) && !m_partial) {
            return message;
        }
        // a chunk: the parts share the addresses and namespace; their payloads join in order
        if (!m_partial) {
            m_partial = message;
        } else {
            m_partial->payloadUtf8.append(message->payloadUtf8);
            m_partial->payloadBinary.append(message->payloadBinary);
        }
        if (!message->continued.value_or(false)) {
            auto whole = *m_partial;
            m_partial.reset();
            whole.continued.reset();
            whole.remainingLength.reset();
            // the chunks carry their data in payload_binary whatever the message's type (openscreen message_chunker.cc,
            // "Per the Cast V2 Message Chunking specification, chunk data is always stored in the payload_binary field")
            if (whole.payloadType == CastMessage::String && whole.payloadUtf8.isEmpty()) {
                whole.payloadUtf8 = whole.payloadBinary;
                whole.payloadBinary.clear();
            }
            return whole;
        }
    }
    return std::nullopt;
}

} // namespace Throw
