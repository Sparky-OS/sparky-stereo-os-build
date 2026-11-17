// SPDX-License-Identifier: GPL-2.0-or-later
#include "preview.h"
#include <QPainter>
#include <stereo-layer/widgetlayer.h>
#include <stereo-layer/picture.h>
class StereoPreview : public PreviewBackend {
    Stereo::WidgetLayer *layer;
public:
    explicit StereoPreview(Preview *owner) : layer(new Stereo::WidgetLayer(owner)) {
        layer->setPaintArea(false);
        QObject::connect(layer, &Stereo::WidgetLayer::failureChanged, owner, [owner] { if (owner->failed) owner->failed(); });
    }
    ~StereoPreview() override { QObject::disconnect(layer, nullptr, nullptr, nullptr); delete layer; }
    void setViews(const QImage &a, const QImage &b, bool stereo) override {
        if (stereo) {
            QImage pair(2*a.width(), a.height(), a.format()); pair.fill(Qt::transparent);
            { QPainter painter(&pair); painter.setCompositionMode(QPainter::CompositionMode_Source); painter.drawImage(0,0,a); painter.drawImage(a.width(),0,b); }
            layer->setPicture(Stereo::Picture::fromPackedImage(pair, Stereo::Picture::Layout::SideBySide, Stereo::Picture::EyeOrder::LeftFirst));
        } else { Stereo::Picture flat; flat.original = a; layer->setPicture(flat); }
    }
    void paint(QPainter *painter) override { layer->paint(painter); }
    QString failure() const override { return layer->failure(); }
};
std::unique_ptr<PreviewBackend> makePreviewBackend(Preview *owner) { return std::make_unique<StereoPreview>(owner); }
void preparePreviewWindow(QWidget *window) { Stereo::WidgetLayer::prepareWindow(window); }
