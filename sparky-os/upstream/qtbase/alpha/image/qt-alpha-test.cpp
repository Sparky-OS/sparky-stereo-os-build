// Test aid: a translucent widgets top-level (Qt::WA_TranslucentBackground) with a QOpenGLWidget child, so the top-level is
// an OpenGL surface, under the default format a program asks for. QT_ALPHA_FMT: 16 (16/16/16/16), 10 (10/10/10/2),
// none (the default format is left alone). QT_ALPHA_GL=0: no QOpenGLWidget (a raster top-level). QT_ALPHA_OPAQUE=1: not translucent.
// Prints the requested format and the format the platform window ended up with.
#include <QApplication>
#include <QLabel>
#include <QOpenGLWidget>
#include <QOpenGLFunctions>
#include <QPainter>
#include <QTimer>
#include <QVBoxLayout>
#include <QWindow>
#include <cstdio>
static void pr(const char *what, const QSurfaceFormat &f)
{
    printf("%s: r=%d g=%d b=%d a=%d stereo=%d\n", what, f.redBufferSize(), f.greenBufferSize(), f.blueBufferSize(), f.alphaBufferSize(), f.stereo());
    fflush(stdout);
}
class Ramp : public QWidget
{
public:
    Ramp() { setMinimumSize(1024, 40); }
    void paintEvent(QPaintEvent *) override
    {
        QPainter p(this);
        QLinearGradient g(0, 0, width(), 0);
        g.setColorAt(0, Qt::black);
        g.setColorAt(1, Qt::white);
        p.fillRect(rect(), g);
    }
};
class Gl : public QOpenGLWidget, protected QOpenGLFunctions
{
public:
    void initializeGL() override { initializeOpenGLFunctions(); }
    void paintGL() override { glClearColor(0.1f, 0.4f, 0.2f, 1.f); glClear(GL_COLOR_BUFFER_BIT); }
};
int main(int argc, char **argv)
{
    const QByteArray mode = qgetenv("QT_ALPHA_FMT");
    QSurfaceFormat fmt;
    if (mode == "16" || mode == "10") {
        const int c = mode == "16" ? 16 : 10;
        fmt.setRedBufferSize(c);
        fmt.setGreenBufferSize(c);
        fmt.setBlueBufferSize(c);
        fmt.setAlphaBufferSize(mode == "16" ? 16 : 2);
        QSurfaceFormat::setDefaultFormat(fmt);
    }
    QApplication app(argc, argv);
    QWidget w;
    if (!qEnvironmentVariableIsSet("QT_ALPHA_OPAQUE"))
        w.setAttribute(Qt::WA_TranslucentBackground);
    auto *l = new QVBoxLayout(&w);
    auto *t = new QLabel("translucent depth test");
    t->setStyleSheet("color:#ffffff;background:#a02020");
    l->addWidget(t);
    l->addWidget(new Ramp);
    if (qgetenv("QT_ALPHA_GL") != "0")
        l->addWidget(new Gl);
    w.resize(1100, 300);
    w.show();
    QTimer::singleShot(2500, [&] {
        pr("requested", w.windowHandle()->requestedFormat());
        pr("window   ", w.windowHandle()->format());
    });
    QTimer::singleShot(qEnvironmentVariableIntValue("QT_STEREO_HOLD_MS") ?: 12000, &app, &QApplication::quit);
    return app.exec();
}
