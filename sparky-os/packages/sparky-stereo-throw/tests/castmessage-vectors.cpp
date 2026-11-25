// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-2.0-or-later
// For castmessage-check.py: "encode" reads JSON lines {src, dst, ns, payload|binary_hex, continued?, remaining?} and
// prints each frame as hex; "decode" reads hex frames and prints each message as a JSON line.
#include "castmessage.h"

#include <QCoreApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTextStream>

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QTextStream in(stdin);
    QTextStream out(stdout);
    const bool encode = app.arguments().value(1) == QLatin1String("encode");
    Throw::FrameReader reader;
    while (!in.atEnd()) {
        const QString line = in.readLine();
        if (line.isEmpty()) {
            continue;
        }
        if (encode) {
            const QJsonObject o = QJsonDocument::fromJson(line.toUtf8()).object();
            Throw::CastMessage m;
            m.sourceId = o.value(QStringLiteral("src")).toString();
            m.destinationId = o.value(QStringLiteral("dst")).toString();
            m.nameSpace = o.value(QStringLiteral("ns")).toString();
            if (o.contains(QStringLiteral("binary_hex"))) {
                m.payloadType = Throw::CastMessage::Binary;
                m.payloadBinary = QByteArray::fromHex(o.value(QStringLiteral("binary_hex")).toString().toLatin1());
            } else {
                m.payloadUtf8 = o.value(QStringLiteral("payload")).toString().toUtf8();
            }
            if (o.contains(QStringLiteral("continued"))) {
                m.continued = o.value(QStringLiteral("continued")).toBool();
            }
            if (o.contains(QStringLiteral("remaining"))) {
                m.remainingLength = quint32(o.value(QStringLiteral("remaining")).toInt());
            }
            out << m.frame().toHex() << '\n';
        } else {
            reader.append(QByteArray::fromHex(line.toLatin1()));
            while (const auto m = reader.next()) {
                QJsonObject o{{QStringLiteral("src"), m->sourceId}, {QStringLiteral("dst"), m->destinationId}, {QStringLiteral("ns"), m->nameSpace},
                              {QStringLiteral("type"), int(m->payloadType)}, {QStringLiteral("payload"), QString::fromUtf8(m->payloadUtf8)},
                              {QStringLiteral("binary_hex"), QString::fromLatin1(m->payloadBinary.toHex())}};
                out << QJsonDocument(o).toJson(QJsonDocument::Compact) << '\n';
            }
            if (!reader.error().isEmpty()) {
                out << "ERROR " << reader.error() << '\n';
                return 1;
            }
        }
    }
    return 0;
}
