// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright 2026 Daniel Campos Ramos
#include <QImage>
#include <QPalette>
#include <QPixmap>
#include <QProxyStyle>
#include <QStylePlugin>
#include <QWidget>

class WordsDeskStyle : public QProxyStyle
{
public:
    WordsDeskStyle() : QProxyStyle(QStringLiteral("Fusion")) {}

    void polish(QWidget *widget) override
    {
        QProxyStyle::polish(widget);
        if (!widget->inherits("KWCanvas"))
            return;

        // QPainter::eraseRect() reads this brush. The pattern gives the desk
        // a measurable horizontal position even where each page is blank.
        QImage tile(47, 23, QImage::Format_RGB32);
        for (int y = 0; y < tile.height(); ++y)
            for (int x = 0; x < tile.width(); ++x)
                tile.setPixel(x, y, qRgb(80 + (17 * x + 21 * y) % 103, 24, 140));

        QPalette palette = widget->palette();
        palette.setBrush(widget->backgroundRole(), QBrush(QPixmap::fromImage(tile)));
        widget->setPalette(palette);
    }
};

class WordsDeskStylePlugin : public QStylePlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QStyleFactoryInterface_iid FILE "words-desk-style.json")

public:
    QStyle *create(const QString &key) override
    {
        return key.compare(QLatin1String("PaperDepth"), Qt::CaseInsensitive) == 0
            ? new WordsDeskStyle : nullptr;
    }
};

#include "words-desk-style.moc"
