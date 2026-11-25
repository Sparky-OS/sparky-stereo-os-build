// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
// The CASTv2 channel's message: the nine fields of cast_channel.proto's CastMessage, written by hand
// (proto2 wire format) and checked byte for byte against pychromecast's generated module in the tests.
#pragma once

#include <QByteArray>
#include <QJsonObject>
#include <QString>
#include <optional>

namespace Throw
{

struct CastMessage {
    enum PayloadType { String = 0, Binary = 1 };
    int protocolVersion = 0; // CASTV2_1_0
    QString sourceId;
    QString destinationId;
    QString nameSpace;
    PayloadType payloadType = String;
    QByteArray payloadUtf8;
    QByteArray payloadBinary;
    // Cast V2 message chunking (openscreen 64d7c985d1): a message over 64 KiB comes in parts
    std::optional<bool> continued;
    std::optional<quint32> remainingLength;

    static CastMessage json(const QString &source, const QString &destination, const QString &nameSpace, const QJsonObject &payload);
    QJsonObject payloadJson() const;

    // the protobuf body, without the length
    QByteArray encode() const;
    static std::optional<CastMessage> decode(const QByteArray &body);
    // the frame on the wire: a 4-byte big-endian length, then the body
    QByteArray frame() const;
};

// Collects frames from a byte stream, and the parts of chunked messages into whole ones.
class FrameReader
{
public:
    void append(const QByteArray &bytes);
    // the next whole message, or nothing yet; a body that cannot be read sets error()
    std::optional<CastMessage> next();
    QString error() const
    {
        return m_error;
    }

private:
    QByteArray m_buffer;
    std::optional<CastMessage> m_partial;
    QString m_error;
};

inline const QString NsConnection = QStringLiteral("urn:x-cast:com.google.cast.tp.connection");
inline const QString NsHeartbeat = QStringLiteral("urn:x-cast:com.google.cast.tp.heartbeat");
inline const QString NsReceiver = QStringLiteral("urn:x-cast:com.google.cast.receiver");
inline const QString NsMedia = QStringLiteral("urn:x-cast:com.google.cast.media");
inline const QString DefaultMediaReceiver = QStringLiteral("CC1AD845");

} // namespace Throw
