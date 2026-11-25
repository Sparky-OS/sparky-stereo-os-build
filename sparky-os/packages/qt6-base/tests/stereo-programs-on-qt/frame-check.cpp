// frame-check: a plain Qt Widgets window for row 863 part A4 (Qt's own frame, resized by its edge). It paints its whole
// content in one colour (#3060a0) with a 2 px magenta (#ff00ff) border exactly at the content's edges, so a picture of
// the screen shows the content's extent as the magenta pixels' bounding box, beside Qt's frame around it.
// FC_STALE=1 is the known bad case: the border is painted at the size of the paint before (content that lags its frame).
// Each resize and paint is logged on stderr: "FC resize WxH" and "FC paint WxH border=WxH".
// Built with: g++ -std=c++17 -O1 frame-check.cpp $(pkg-config --cflags --libs Qt6Widgets) -o frame-check
#include <QApplication>
#include <QPainter>
#include <QResizeEvent>
#include <QWidget>
#include <cstdio>
#include <cstdlib>

class FrameCheck : public QWidget
{
public:
    FrameCheck()
    {
        setWindowTitle(QStringLiteral("frame-check"));
        setAttribute(Qt::WA_OpaquePaintEvent);
        resize(600, 400);
    }

protected:
    void resizeEvent(QResizeEvent *e) override
    {
        fprintf(stderr, "FC resize %dx%d\n", e->size().width(), e->size().height());
        QWidget::resizeEvent(e);
    }
    void paintEvent(QPaintEvent *) override
    {
        const QSize border = (qEnvironmentVariableIntValue("FC_STALE") && m_last.isValid()) ? m_last : size();
        QPainter p(this);
        p.fillRect(rect(), QColor(0x30, 0x60, 0xa0));
        p.setPen(Qt::NoPen);
        p.setBrush(QColor(0xff, 0x00, 0xff));
        const int w = border.width(), h = border.height();
        p.drawRect(0, 0, w, 2);
        p.drawRect(0, h - 2, w, 2);
        p.drawRect(0, 0, 2, h);
        p.drawRect(w - 2, 0, 2, h);
        fprintf(stderr, "FC paint %dx%d border=%dx%d\n", width(), height(), w, h);
        m_last = size();
    }

private:
    QSize m_last;
};

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    FrameCheck w;
    w.show();
    return app.exec();
}
