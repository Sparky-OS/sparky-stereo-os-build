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
    QString audioCodec; // the sound: one of Codecs::sounds()' ids
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

// a sound a Throw can carry: what plays it, and whether it keeps every bit of the source
struct Sound {
    QString id; // pcm24, flac, pcm16, opus, aac, vorbis, mp3, ac3-5.1, eac3-5.1
    QString label;
    QString encoder; // libavcodec's encoder
    int channels = 2;
    bool lossless = false;
    int bitRate = 0; // the compressed ones
};

struct Plan {
    bool video = true;
    CodecInfo info;
    Mode mode;
    int audioRate = 48000;
    int audioChannels = 2;
    QString soundChoice; // the person's sound for the device ("" for the table's pick)
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
// the whole plan: the person's codec, mode and sound for the device ("" for the table's picks), the sounds that did not
// start on this device, and the codecs this computer encodes
Plan plan(const ModelRow &row, const QString &chosenCodec, const QString &chosenMode, const QString &chosenSound,
          const QStringList &failedSounds, const QStringList &here);
// the sound a plan carries (the device's page says it)
Said soundWords(const Plan &plan);
// every sound a Throw can carry, best first: lossless before compressed, stereo before the 5.1 ones (a 5.1 sound is the
// person's choice; nothing is upmixed)
const QList<Sound> &sounds();
Sound sound(const QString &id);
// the sounds a container carries, best first
QStringList soundsFor(const QString &format);
// the sound of a plan: the person's choice when the container carries it (else an error), otherwise the best stereo
// sound the container carries that has not failed on this device
void pickSound(Plan &plan, const QString &chosen, const QStringList &failedOnDevice);
// a sound's name in the person's language: a bit depth is words, a format's own name (Opus, Dolby Digital) stays
QString soundLabel(const Sound &s);
// the message context of a sound's name when it is words (empty for a format's own name)
QString soundLabelContext(const Sound &s);
// an argument of a sentence in the person's language: a sound's English name becomes its translated name, other text stays
QString localArg(const QString &arg);
// the sound whose English name this is (an empty Sound when none is)
Sound soundNamed(const QString &label);
// what a sound means for a person, in plain words: lossless or compressed, how much of the network, 5.1 and its speakers
QString soundAbout(const Sound &s);
}

} // namespace Throw
