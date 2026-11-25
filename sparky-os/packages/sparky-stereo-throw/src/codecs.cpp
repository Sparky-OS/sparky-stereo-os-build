// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
#include "codecs.h"
#include "logging.h"

#include <KLocalizedString>
#include <KPipeWire/PipeWireEncodedStream>

namespace Throw
{

QString Said::english() const
{
    QString text = message;
    for (const auto &arg : args) {
        text = text.arg(arg);
    }
    return text;
}

QString Said::translated() const
{
    if (message.isEmpty()) {
        return QString();
    }
    KLocalizedString s = ki18nc(context.toUtf8().constData(), message.toUtf8().constData());
    for (const auto &arg : args) {
        s = s.subs(arg);
    }
    return s.toString();
}

namespace Codecs
{

CodecInfo info(const QString &codec)
{
    // the container follows the codec, among those Google's media page names (MP4, WebM, Ogg), Matroska for H.264 as row
    // 81's review chose; the sound goes in the lossless FLAC where the container carries it, Opus in WebM, which
    // carries Opus or Vorbis only
    if (codec == QLatin1String("h264")) {
        return {codec, QStringLiteral("H.264"), PipeWireBaseEncodedStream::H264Main, QStringLiteral("matroska"), QStringLiteral("video/x-matroska"),
                QStringLiteral("flac")};
    }
    if (codec == QLatin1String("hevc")) {
        return {codec, QStringLiteral("HEVC"), PipeWireBaseEncodedStream::HEVCMain, QStringLiteral("mp4"), QStringLiteral("video/mp4"), QStringLiteral("flac")};
    }
    if (codec == QLatin1String("vp9")) {
        return {codec, QStringLiteral("VP9"), PipeWireBaseEncodedStream::VP9, QStringLiteral("webm"), QStringLiteral("video/webm"), QStringLiteral("opus")};
    }
    if (codec == QLatin1String("vp8")) {
        return {codec, QStringLiteral("VP8"), PipeWireBaseEncodedStream::VP8, QStringLiteral("webm"), QStringLiteral("video/webm"), QStringLiteral("opus")};
    }
    if (codec == QLatin1String("av1")) {
        return {codec, QStringLiteral("AV1"), PipeWireBaseEncodedStream::NoEncoder, QStringLiteral("webm"), QStringLiteral("video/webm"), QStringLiteral("opus")};
    }
    // sound alone, for a speaker or a group: FLAC in Ogg
    return {QString(), QString(), PipeWireBaseEncodedStream::NoEncoder, QStringLiteral("ogg"), QStringLiteral("audio/ogg"), QStringLiteral("flac")};
}

QStringList encodable()
{
    static const QStringList found = [] {
        QStringList codecs;
        PipeWireEncodedStream probe;
        const auto encoders = probe.suggestedEncoders();
        for (const auto &c : {QStringLiteral("h264"), QStringLiteral("hevc"), QStringLiteral("vp9"), QStringLiteral("vp8"), QStringLiteral("av1")}) {
            const int encoder = info(c).encoder;
            // KPipeWire 6.7.4 lists VP9 (libvpx-vp9 is there) but its VP9 encoder gives no picture for a live screen in our
            // proof (loopback row E1: none in 30 s, the screen moving or still; libvpx's default lag of 25 frames, which
            // upstream KPipeWire sets to 0): not offered as encodable until our KPipeWire carries upstream's settings
            if (c == QLatin1String("vp9")) {
                continue;
            }
            if (encoder != PipeWireBaseEncodedStream::NoEncoder && encoders.contains(PipeWireBaseEncodedStream::Encoder(encoder))) {
                codecs.append(c);
            }
        }
        qCInfo(THROW) << "KPipeWire encodes here:" << codecs;
        return codecs;
    }();
    return found;
}

QString missing(const QString &codec)
{
    if (codec == QLatin1String("av1")) {
        return QStringLiteral("KPipeWire 6.7.4 has no AV1 encoder");
    }
    if (codec == QLatin1String("hevc")) {
        return QStringLiteral("no HEVC encoder was found (hevc_vaapi, hevc_nvenc or libx265)");
    }
    if (codec == QLatin1String("vp9")) {
        return QStringLiteral("KPipeWire 6.7.4's VP9 encoder gives no picture for a live screen");
    }
    if (codec == QLatin1String("vp8")) {
        return QStringLiteral("no VP8 encoder was found (libvpx)");
    }
    return QStringLiteral("no H.264 encoder was found (h264_vaapi, h264_nvenc, libx264 or libopenh264)");
}

namespace
{
qint64 area(const Mode &m)
{
    return qint64(m.size.width()) * m.size.height();
}
Mode largest(const CodecRow &row)
{
    Mode best;
    for (const auto &m : row.modes) {
        if (!best.isValid() || area(m) > area(best)) {
            best = m;
        }
    }
    return best;
}
}

Plan plan(const ModelRow &row, const QString &chosenCodec, const QString &chosenMode)
{
    return plan(row, chosenCodec, chosenMode, row.video ? encodable() : QStringList());
}

Plan plan(const ModelRow &row, const QString &chosenCodec, const QString &chosenMode, const QStringList &here)
{
    Plan p;
    if (!row.video) {
        p.video = false;
        p.info = info(QString());
        return p;
    }
    const CodecRow *picked = nullptr;
    if (!chosenCodec.isEmpty()) {
        picked = row.codecRow(chosenCodec);
        if (!picked) {
            p.error = {QStringLiteral("@info why a Throw cannot be made as chosen; %1 a codec"), QStringLiteral("the device does not take %1"),
                       {info(chosenCodec).label}};
            return p;
        }
        if (!here.contains(chosenCodec)) {
            p.info = info(chosenCodec);
            p.error = {QStringLiteral("@info why a Throw cannot be made as chosen; %1 a codec, %2 the encoders looked for"),
                       QStringLiteral("this computer cannot encode %1: %2"),
                       {p.info.label, missing(chosenCodec)}};
            return p;
        }
    } else {
        for (const auto &c : row.codecs) {
            if (here.contains(c.codec)) {
                picked = &c;
                break;
            }
        }
        if (!picked) {
            p.error = {QStringLiteral("@info why a Throw cannot be made"), QStringLiteral("this computer cannot encode any codec the device takes"), {}};
            return p;
        }
    }
    p.info = info(picked->codec);
    p.mode = picked->defaultMode;
    if (!chosenMode.isEmpty()) {
        const Mode m = Mode::parse(chosenMode);
        if (!picked->allows(m)) {
            p.error = {QStringLiteral("@info why a Throw cannot be made as chosen; %1 a mode, %2 a codec"),
                       QStringLiteral("%1 in %2 is not a mode the device takes"),
                       {chosenMode, p.info.label}};
            return p;
        }
        p.mode = m;
    }
    // the device gets less than it can show: the largest mode of any codec it takes is beyond the largest this codec gives
    Mode best;
    QString bestCodec;
    for (const auto &c : row.codecs) {
        const Mode m = largest(c);
        if (!best.isValid() || area(m) > area(best)) {
            best = m;
            bestCodec = c.codec;
        }
    }
    const Mode mine = largest(*picked);
    if (best.isValid() && area(best) > area(mine)) {
        QStringList need;
        for (const auto &c : row.codecs) {
            if (area(largest(c)) >= area(best) && !here.contains(c.codec)) {
                need.append(info(c.codec).label);
            }
        }
        if (!need.isEmpty()) {
            p.limited = {QStringLiteral("@info a device gets less than it can show; %1 and %3 sizes, %2 codecs, %4 a codec"),
                         QStringLiteral("It shows up to %1 in %2; this computer has no encoder for it, so it gets %3 in %4."),
                         {QStringLiteral("%1x%2").arg(best.size.width()).arg(best.size.height()), need.join(QStringLiteral(", ")),
                          QStringLiteral("%1x%2").arg(mine.size.width()).arg(mine.size.height()), p.info.label}};
        }
    }
    return p;
}

Said soundWords(const Plan &plan)
{
    if (plan.info.audioCodec == QLatin1String("opus")) {
        return {QStringLiteral("@info the sound a Throw carries; %1 kilohertz, %2 channels"),
                QStringLiteral("Opus, %1 kHz, %2 channels (compressed: the WebM stream the device takes carries Opus or Vorbis only)"),
                {QString::number(plan.audioRate / 1000), QString::number(plan.audioChannels)}};
    }
    return {QStringLiteral("@info the sound a Throw carries; %1 kilohertz, %2 channels"), QStringLiteral("FLAC, 24 bit, %1 kHz, %2 channels (lossless)"),
            {QString::number(plan.audioRate / 1000), QString::number(plan.audioChannels)}};
}

} // namespace Codecs
} // namespace Throw
