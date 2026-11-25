// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
// The codec plan against the package's own device table, with chosen lists of what this computer encodes: the table's
// pick, the person's choice, a choice refused with its reason (never replaced), and the sentence when a device gets less
// than it can show. Usage: codecplan DEVICES_JSON; exit status = rows not as expected.
#include "codecs.h"

#include <QCoreApplication>
#include <QTextStream>

using namespace Throw;

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    const DeviceTable table(QString::fromLocal8Bit(argv[1]));
    QTextStream out(stdout);
    int failed = 0;
    auto row = [&](const char *claim, const QString &expected, const QString &measured) {
        const bool ok = expected == measured;
        failed += ok ? 0 : 1;
        out << (ok ? "PASS " : "FAIL ") << claim << ": expected [" << expected << "], measured [" << measured << "]\n";
    };
    const QStringList all{QStringLiteral("h264"), QStringLiteral("hevc"), QStringLiteral("vp9"), QStringLiteral("vp8")};
    const QStringList h264only{QStringLiteral("h264")};
    const ModelRow ultra = table.row(QStringLiteral("Chromecast Ultra"));
    const ModelRow streamer = table.row(QStringLiteral("Google TV Streamer"));
    const ModelRow first = table.row(QStringLiteral("Chromecast"));
    const ModelRow speaker = table.row(QStringLiteral("Google Nest Mini"));

    Plan p = Codecs::plan(ultra, QString(), QString(), all);
    row("Ultra, every encoder here: HEVC at 3840x2160@30 in MP4 with FLAC", QStringLiteral("hevc 3840x2160@30 mp4 flac"),
        QStringLiteral("%1 %2 %3 %4").arg(p.info.codec, p.mode.text(), p.info.format, p.info.audioCodec));
    row("Ultra, every encoder here: no sentence about less", QString(), p.limited.english());
    p = Codecs::plan(ultra, QString(), QString(), h264only);
    row("Ultra, H.264 only here: 1920x1080@30 in Matroska", QStringLiteral("h264 1920x1080@30 matroska"),
        QStringLiteral("%1 %2 %3").arg(p.info.codec, p.mode.text(), p.info.format));
    row("Ultra, H.264 only here: told why it gets less", QStringLiteral("It shows up to 3840x2160 in HEVC, VP9, VP8; this computer has no encoder for it, so it gets 1920x1080 in H.264."),
        p.limited.english());
    p = Codecs::plan(streamer, QString(), QString(), all);
    row("Google TV Streamer: AV1 has no encoder here, HEVC at 4K is its pick", QStringLiteral("hevc 3840x2160@30"), QStringLiteral("%1 %2").arg(p.info.codec, p.mode.text()));
    p = Codecs::plan(streamer, QStringLiteral("av1"), QString(), all);
    row("AV1 chosen: refused with its reason, not replaced", QStringLiteral("this computer cannot encode AV1: KPipeWire 6.7.4 has no AV1 encoder"), p.error.english());
    p = Codecs::plan(streamer, QStringLiteral("vp9"), QStringLiteral("1920x1080@60"), all);
    row("VP9 at 1920x1080@60 chosen: WebM with Opus", QStringLiteral("vp9 1920x1080@60 webm opus"),
        QStringLiteral("%1 %2 %3 %4").arg(p.info.codec, p.mode.text(), p.info.format, p.info.audioCodec));
    p = Codecs::plan(first, QStringLiteral("h264"), QStringLiteral("3840x2160@30"), all);
    row("a mode the device does not take: refused", QStringLiteral("3840x2160@30 in H.264 is not a mode the device takes"), p.error.english());
    p = Codecs::plan(first, QStringLiteral("hevc"), QString(), all);
    row("a codec the device does not take: refused", QStringLiteral("the device does not take HEVC"), p.error.english());
    p = Codecs::plan(speaker, QString(), QString(), all);
    row("a speaker: the sound alone, FLAC in Ogg", QStringLiteral("false ogg flac audio/ogg"),
        QStringLiteral("%1 %2 %3 %4").arg(p.video ? QStringLiteral("true") : QStringLiteral("false"), p.info.format, p.info.audioCodec, p.info.mime));
    out << (failed ? "RESULT: FAIL" : "RESULT: PASS") << " (" << failed << " rows not as expected)\n";
    return failed;
}
