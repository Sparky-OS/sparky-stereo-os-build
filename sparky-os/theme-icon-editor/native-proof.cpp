// SPDX-License-Identifier: GPL-2.0-or-later
#include "drawing.h"
#include <QApplication>
#include <QDir>
#include <QPainter>
#include <QSvgRenderer>
#include <iostream>

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    if (argc != 3) return 2;
    try {
        const QString out = QString::fromLocal8Bit(argv[2]);
        if (!QDir().mkpath(out)) return 1;
        Drawing drawing;
        drawing.open(QString::fromLocal8Bit(argv[1]));
        QImage original(256, 256, QImage::Format_ARGB32_Premultiplied);
        original.fill(Qt::transparent);
        { QSvgRenderer source(drawing.original); QPainter p(&original); source.render(&p); }
        if (drawing.eye(256, false) != original) throw std::runtime_error("Screen plane changes the original SVG rendering");
        original.save(out + "/original.png");
        const QMap<QString, int> choices{{"g3010", -1}, {"g3050", 0}, {"g3090", 1}};
        for (auto i = choices.cbegin(); i != choices.cend(); ++i) drawing.setPlace(i.key(), i.value());
        for (int n : {8, 16, 22, 24, 32, 48, 64, 128, 256}) {
            const auto left = drawing.eye(n, false);
            const auto right = drawing.eye(n, true);
            left.save(out + QString("/left-%1.png").arg(n));
            right.save(out + QString("/right-%1.png").arg(n));
            savePns(out + QString("/pair-%1.pns").arg(n), left, right);
            QImage pair(2*n, n, QImage::Format_ARGB32_Premultiplied);
            pair.fill(Qt::transparent);
            { QSvgRenderer vector(drawing.pairSvg(n)); QPainter p(&pair); vector.render(&p); }
            if (pair.copy(0, 0, n, n) != left || pair.copy(n, 0, n, n) != right)
                throw std::runtime_error("Vector pair differs from the independently rendered views at size " + std::to_string(n));
            for (const QString &id : choices.keys())
                savePns(out + QString("/%1-%2.pns").arg(id).arg(n), drawing.eye(n, false, id), drawing.eye(n, true, id));
        }
        drawing.eye(256, false).save(out + "/left.png");
        drawing.eye(256, true).save(out + "/right.png");
        for (const QString &id : choices.keys()) drawing.setPlace(id, 0);
        savePns(out + "/negative-flat.pns", drawing.eye(256, false, "g3090"), drawing.eye(256, true, "g3090"));
        std::cout << "PASS: original SVG at screen unchanged; nine vector pairs equal their separately rendered eyes; probes written\n";
        return 0;
    } catch (const std::exception &e) { std::cerr << e.what() << '\n'; return 1; }
}
