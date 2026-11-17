// SPDX-License-Identifier: GPL-2.0-or-later
#include "preview.h"
#include <QPainter>
class PlainPreview : public PreviewBackend {
    Preview *owner;
public:
    explicit PlainPreview(Preview *widget) : owner(widget) {}
    void setViews(const QImage &, const QImage &, bool) override {}
    void paint(QPainter *painter) override { painter->drawImage(owner->rect(), owner->left); }
    QString failure() const override { return {}; }
};
std::unique_ptr<PreviewBackend> makePreviewBackend(Preview *owner) { return std::make_unique<PlainPreview>(owner); }
void preparePreviewWindow(QWidget *) {}
