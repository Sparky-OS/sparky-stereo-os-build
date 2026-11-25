// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
// What a Throw sends: the codec, the mode, the container that follows the codec and the sound in it. The codec is the
// person's choice for that device, or the first one the device's row lists that this computer can encode (KPipeWire's
// own list of the encoders it finds); a choice that cannot be met is refused with its reason, never replaced.
#pragma once

#include "devicetable.h"

#include <QString>
#include <QStringList>

namespace Throw
{

struct CodecInfo {
    QString codec; // h264, hevc, vp9, vp8, av1, or "" for sound alone
    QString label; // H.264, HEVC, VP9, VP8, AV1
    int encoder = 0; // PipeWireBaseEncodedStream::Encoder, 0 none
    QString format; // libavformat muxer: matroska, mp4, webm, ogg
    QString mime; // what the device is asked to load
    QString audioCodec; // flac or opus
};

// a sentence for the person: its translation context, its message with %1.., its arguments
struct Said {
    QString context;
    QString message;
    QStringList args;
    bool isEmpty() const
    {
        return message.isEmpty();
    }
    QString english() const;
    QString translated() const;
};

struct Plan {
    bool video = true;
    CodecInfo info;
    Mode mode;
    int audioRate = 48000;
    int audioChannels = 2;
    Said error; // why this Throw cannot be made as chosen (empty when it can)
    Said limited; // why the device gets less than it can show (empty when it gets its best)
};

namespace Codecs
{
CodecInfo info(const QString &codec);
// the codecs KPipeWire can encode on this computer, found once
QStringList encodable();
// why this computer cannot encode it (English: the encoders' names)
QString missing(const QString &codec);
// the plan for a device: its row, and the person's codec and mode for it ("" for the table's pick)
Plan plan(const ModelRow &row, const QString &chosenCodec, const QString &chosenMode);
// the same, with the codecs this computer encodes given (tests)
Plan plan(const ModelRow &row, const QString &chosenCodec, const QString &chosenMode, const QStringList &here);
// the sound a plan carries (the device's page says it)
Said soundWords(const Plan &plan);
}

} // namespace Throw
