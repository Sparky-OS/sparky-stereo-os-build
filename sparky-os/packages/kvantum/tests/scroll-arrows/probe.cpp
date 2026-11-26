// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright 2026 Daniel Campos Ramos
// probe: where the Kvantum style puts each part of a 200 px scroll bar, and what a press at each arrow's centre hits,
// for a vertical bar and a horizontal one in both directions. Prints one JSON object; builds with Qt 6 and Qt 5.
#include <QApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QScrollBar>
#include <QStyle>
#include <QStyleFactory>
#include <QStyleOptionSlider>
#include <cstdio>

static QJsonArray rect(const QRect &r)
{
    return QJsonArray{r.x(), r.y(), r.width(), r.height()};
}

static QJsonObject probe(QStyle *style, Qt::Orientation orientation, Qt::LayoutDirection direction)
{
    QScrollBar bar(orientation);
    bar.setLayoutDirection(direction);
    bar.setRange(0, 100);
    bar.setPageStep(20);
    bar.setValue(0);
    const int extent = style->pixelMetric(QStyle::PM_ScrollBarExtent, nullptr, &bar);
    bar.resize(orientation == Qt::Vertical ? QSize(extent, 200) : QSize(200, extent));
    QStyleOptionSlider opt;
    opt.initFrom(&bar);
    opt.subControls = QStyle::SC_All;
    opt.orientation = orientation;
    opt.minimum = bar.minimum();
    opt.maximum = bar.maximum();
    opt.sliderPosition = bar.sliderPosition();
    opt.sliderValue = bar.value();
    opt.singleStep = bar.singleStep();
    opt.pageStep = bar.pageStep();
    opt.upsideDown = false;
    if (orientation == Qt::Horizontal)
        opt.state |= QStyle::State_Horizontal;
    const struct { const char *name; QStyle::SubControl sc; } parts[] = {
        {"subline", QStyle::SC_ScrollBarSubLine}, {"addline", QStyle::SC_ScrollBarAddLine},
        {"groove", QStyle::SC_ScrollBarGroove}, {"slider", QStyle::SC_ScrollBarSlider},
        {"subpage", QStyle::SC_ScrollBarSubPage}, {"addpage", QStyle::SC_ScrollBarAddPage}};
    QJsonObject out{{"extent", extent}};
    for (const auto &part : parts)
        out.insert(part.name, rect(style->subControlRect(QStyle::CC_ScrollBar, &opt, part.sc, &bar)));
    for (const auto &part : parts) {
        if (part.sc != QStyle::SC_ScrollBarSubLine && part.sc != QStyle::SC_ScrollBarAddLine)
            continue;
        const QPoint centre = style->subControlRect(QStyle::CC_ScrollBar, &opt, part.sc, &bar).center();
        const QStyle::SubControl hit = style->hitTestComplexControl(QStyle::CC_ScrollBar, &opt, centre, &bar);
        out.insert(QStringLiteral("hit_%1").arg(QLatin1String(part.name)),
                   hit == QStyle::SC_ScrollBarSubLine ? "subline" : hit == QStyle::SC_ScrollBarAddLine ? "addline" : "other");
    }
    return out;
}

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    QStyle *style = QStyleFactory::create(QStringLiteral("kvantum"));
    if (!style) {
        std::fprintf(stderr, "the kvantum style plugin did not load\n");
        return 2;
    }
    QApplication::setStyle(style);
    const QJsonObject result{
        {"qt", QString::fromLatin1(qVersion())},
        {"vertical", probe(style, Qt::Vertical, Qt::LeftToRight)},
        {"horizontal", probe(style, Qt::Horizontal, Qt::LeftToRight)},
        {"horizontal_rtl", probe(style, Qt::Horizontal, Qt::RightToLeft)}};
    std::printf("%s\n", QJsonDocument(result).toJson(QJsonDocument::Compact).constData());
    return 0;
}
