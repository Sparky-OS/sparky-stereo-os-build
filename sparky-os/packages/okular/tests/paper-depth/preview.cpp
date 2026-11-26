// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright 2026 Daniel Campos Ramos
// preview MODE [ZOOM] [SCROLL] -- Qt's print preview (QPrintPreviewWidget) under a toolbar, for the paper depth proof:
// two pages, the first with a red square near its top left and a green bar, the second with a blue square and a green bar.
//   MODE   all: every page in view (AllPagesView); single: one page at a time, ZOOM times its size, scrolled down by SCROLL
//          (a fraction of the scroll range), so the page runs under the toolbar
// The program prints its view's geometry once shown: "PREVIEW viewport X Y W H" in window coordinates.
#include <QApplication>
#include <QGraphicsView>
#include <QMainWindow>
#include <QPageLayout>
#include <QPainter>
#include <QPrintPreviewWidget>
#include <QPrinter>
#include <QScrollBar>
#include <QTimer>
#include <QToolBar>
#include <cstdio>

class ElementProbe : public QWidget
{
public:
    using QWidget::QWidget;

protected:
    void resizeEvent(QResizeEvent *event) override
    {
        QWidget::resizeEvent(event);
        setProperty("_q_stereo_depth_rects", QVariantList{
            QVariantMap{{QStringLiteral("rect"), rect()}, {QStringLiteral("depth"), -1.0}},
            QVariantMap{{QStringLiteral("rect"), QRect(200, 70, 320, 220)}, {QStringLiteral("depth"), 1.0}},
        });
    }

    void paintEvent(QPaintEvent *) override
    {
        QPainter painter(this);
        painter.fillRect(rect(), Qt::gray);
        painter.fillRect(QRect(80, 70, 6, 220), Qt::red);
        painter.fillRect(QRect(200, 70, 320, 220), Qt::white);
        painter.fillRect(QRect(332, 92, 6, 176), Qt::green);
    }
};

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    const QString mode = argc > 1 ? QString::fromLatin1(argv[1]) : QStringLiteral("all");
    const double zoom = argc > 2 ? QString::fromLatin1(argv[2]).toDouble() : 2.0;
    const double scroll = argc > 3 ? QString::fromLatin1(argv[3]).toDouble() : 0.3;

    if (mode == QLatin1String("probe")) {
        QMainWindow window;
        window.setWindowTitle(QStringLiteral("paper-depth-element-probe"));
        window.setCentralWidget(new ElementProbe(&window));
        window.resize(900, 520);
        window.show();
        return app.exec();
    }

    QPrinter printer(QPrinter::ScreenResolution);
    printer.setOutputFormat(QPrinter::PdfFormat);
    printer.setPageLayout(QPageLayout(QPageSize(QPageSize::A6), QPageLayout::Portrait, QMarginsF(0, 0, 0, 0)));

    QMainWindow window;
    window.setWindowTitle(QStringLiteral("paper-depth-preview"));
    auto *toolbar = window.addToolBar(QStringLiteral("Preview"));
    toolbar->addAction(QStringLiteral("Zoom in"));
    toolbar->addAction(QStringLiteral("Zoom out"));
    auto *preview = new QPrintPreviewWidget(&printer, &window);
    window.setCentralWidget(preview);
    QObject::connect(preview, &QPrintPreviewWidget::paintRequested, preview, [](QPrinter *p) {
        QPainter painter(p);
        const QRectF page = p->pageLayout().paintRectPixels(p->resolution());
        const qreal s = qMin(page.width(), page.height()) / 5;
        const QColor squares[] = {Qt::red, Qt::blue};
        for (int i = 0; i < 2; ++i) {
            if (i)
                p->newPage();
            painter.fillRect(QRectF(page.left() + s, page.top() + s, s, s), squares[i]);
            painter.fillRect(QRectF(page.center().x(), page.top() + s / 2, s / 4, page.height() - s), Qt::green);
        }
    });
    if (mode == QLatin1String("single")) {
        preview->setSinglePageViewMode();
        preview->setZoomFactor(zoom);
    } else {
        preview->setAllPagesViewMode();
    }
    window.resize(1500, 900);
    window.show();
    QTimer::singleShot(1500, &window, [preview, mode, scroll] {
        auto *view = preview->findChild<QGraphicsView *>();
        if (!view)
            return;
        if (mode == QLatin1String("single")) {
            QScrollBar *bar = view->verticalScrollBar();
            bar->setValue(bar->minimum() + qRound((bar->maximum() - bar->minimum()) * scroll));
        }
        const QPoint at = view->viewport()->mapTo(view->window(), QPoint(0, 0));
        std::printf("PREVIEW viewport %d %d %d %d\n", at.x(), at.y(), view->viewport()->width(), view->viewport()->height());
        std::fflush(stdout);
    });
    return app.exec();
}
