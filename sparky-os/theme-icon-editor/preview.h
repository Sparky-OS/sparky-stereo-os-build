// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
#include <QWidget>
#include <QPainter>
#include <stereo-layer/widgetlayer.h>
#include <stereo-layer/picture.h>
class Preview : public QWidget
{
public:
    Stereo::WidgetLayer *layer;
    QImage left;
    Preview() { setFixedSize(256, 256); layer = new Stereo::WidgetLayer(this); layer->setPaintArea(false); }
    void setViews(const QImage &a, const QImage &b, bool stereo)
    {
#ifdef PREVIEW_REFERENCE
        stereo = false;
#endif
        left = a;
        setFixedSize(QSize(256, qMax(1, qRound(256.0 * a.height() / a.width()))));
        if (stereo) {
            QImage pair(a.width() * 2, a.height(), a.format());
            pair.fill(Qt::transparent);
            { QPainter p(&pair); p.setCompositionMode(QPainter::CompositionMode_Source); p.drawImage(0, 0, a); p.drawImage(a.width(), 0, b); }
            layer->setPicture(Stereo::Picture::fromPackedImage(pair, Stereo::Picture::Layout::SideBySide, Stereo::Picture::EyeOrder::LeftFirst));
        } else { Stereo::Picture flat; flat.original = a; layer->setPicture(flat); }
        update();
    }
    void paintEvent(QPaintEvent *) override
    {
        QPainter p(this);
        p.fillRect(rect(), Qt::black);
        layer->paint(&p);
    }
};

