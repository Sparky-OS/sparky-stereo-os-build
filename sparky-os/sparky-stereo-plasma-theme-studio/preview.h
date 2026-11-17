// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
#include <QWidget>
#include <QImage>
#include <functional>
#include <memory>
class QPainter;
class Preview;
class PreviewBackend {
public:
    virtual ~PreviewBackend() = default;
    virtual void setViews(const QImage &, const QImage &, bool) = 0;
    virtual void paint(QPainter *) = 0;
    virtual QString failure() const = 0;
};
std::unique_ptr<PreviewBackend> makePreviewBackend(Preview *);
void preparePreviewWindow(QWidget *);
class Preview : public QWidget {
public:
    Preview();
    ~Preview() override;
    QImage left;
    std::function<void(QPointF)> picked;
    std::function<void()> failed;
    static void prepareWindow(QWidget *w) { preparePreviewWindow(w); }
    void setViews(const QImage &, const QImage &, bool);
    QString failure() const { return backend->failure(); }
protected:
    void paintEvent(QPaintEvent *) override;
    void mousePressEvent(QMouseEvent *) override;
private:
    std::unique_ptr<PreviewBackend> backend;
};
