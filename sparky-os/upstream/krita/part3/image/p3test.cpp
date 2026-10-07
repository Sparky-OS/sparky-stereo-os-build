// Part 3 test: a widgets window with a 2D label column and a stereo OpenGL area; mode by P3_MODE
//  nativewidget: a QOpenGLWidget with stereo format and WA_NativeWindow, no stereo on the top level
//  container:    a stereo QWindow in createWindowContainer
#include <QApplication>
#include <QOpenGLWidget>
#include <QOpenGLFunctions>
#include <QOpenGLFunctions_2_1>
#include <QSurfaceFormat>
#include <QWindow>
#include <QTimer>
#include <QLabel>
#include <QHBoxLayout>
#include <QOpenGLContext>
#include <cstdio>

class W : public QOpenGLWidget, protected QOpenGLFunctions
{
public:
    void initializeGL() override { initializeOpenGLFunctions(); }
    void paintGL() override
    {
        const bool left = currentTargetBuffer() == QOpenGLWidget::LeftBuffer;
        glClearColor(left ? 1 : 0, left ? 0 : 1, 0, 1);
        glClear(GL_COLOR_BUFFER_BIT);
        static int n = 0;
        if (n++ < 6) { printf("paintGL target=%s\n", left ? "left" : "right"); fflush(stdout); }
    }
};

class SW : public QWindow
{
public:
    SW()
    {
        setSurfaceType(QSurface::OpenGLSurface);
        QSurfaceFormat fmt; fmt.setStereo(true); fmt.setRenderableType(QSurfaceFormat::OpenGL);
        setFormat(fmt); ctx.setFormat(fmt); ctx.create();
    }
    void exposeEvent(QExposeEvent *) override { render(); requestUpdate(); }
    bool event(QEvent *e) override { if (e->type() == QEvent::UpdateRequest) { render(); if (++frames < 30) requestUpdate(); return true; } return QWindow::event(e); }
    void render()
    {
        if (!isExposed()) return;
        ctx.makeCurrent(this);
        QOpenGLFunctions_2_1 f; f.initializeOpenGLFunctions();
        f.glViewport(0, 0, width() * devicePixelRatio(), height() * devicePixelRatio());
        f.glDrawBuffer(GL_BACK_LEFT); f.glClearColor(1, 0, 0, 1); f.glClear(GL_COLOR_BUFFER_BIT);
        f.glDrawBuffer(GL_BACK_RIGHT); f.glClearColor(0, 1, 0, 1); f.glClear(GL_COLOR_BUFFER_BIT);
        ctx.swapBuffers(this);
    }
    QOpenGLContext ctx; int frames = 0;
};

int main(int argc, char **argv)
{
    if (qgetenv("P3_DEFAULT") == "1") { QSurfaceFormat d; d.setStereo(true); d.setRenderableType(QSurfaceFormat::OpenGL); QSurfaceFormat::setDefaultFormat(d); }
    if (qgetenv("P3_DEPTH").size()) { QSurfaceFormat d = QSurfaceFormat::defaultFormat(); int b = qgetenv("P3_DEPTH").toInt(); d.setRedBufferSize(b); d.setGreenBufferSize(b); d.setBlueBufferSize(b); d.setAlphaBufferSize(qgetenv("P3_ALPHA").toInt()); d.setRenderableType(QSurfaceFormat::OpenGL); QSurfaceFormat::setDefaultFormat(d); }
    QApplication app(argc, argv);
    const QByteArray mode = qgetenv("P3_MODE");
    QWidget top; top.resize(400, 300);
    if (qgetenv("P3_TRANSLUCENT") == "1") top.setAttribute(Qt::WA_TranslucentBackground);
    if (qgetenv("P3_EARLY") == "1") {
        QSurfaceFormat keep = QSurfaceFormat::defaultFormat(), f = keep;
        f.setRedBufferSize(8); f.setGreenBufferSize(8); f.setBlueBufferSize(8); f.setAlphaBufferSize(8);
        QSurfaceFormat::setDefaultFormat(f);
        QWidget probe; probe.setAttribute(Qt::WA_TranslucentBackground);
        top.setAttribute(Qt::WA_TranslucentBackground);
        top.winId();
        if (qgetenv("P3_PLACEHOLDER") == "1") { auto *ph = new W; ph->setParent(&top); ph->resize(1, 1); ph->hide(); top.winId(); }
        QSurfaceFormat::setDefaultFormat(keep);
        printf("after early winId: requested %d/%d/%d/%d type=%d\n", top.windowHandle()->requestedFormat().redBufferSize(), top.windowHandle()->requestedFormat().greenBufferSize(), top.windowHandle()->requestedFormat().blueBufferSize(), top.windowHandle()->requestedFormat().alphaBufferSize(), int(top.windowHandle()->surfaceType()));
    }
    if (qgetenv("P3_GLTOP") == "1") { auto *g = new W; g->setParent(&top); g->resize(10, 10); }
    auto *lay = new QHBoxLayout(&top); lay->setContentsMargins(0, 0, 0, 0); lay->setSpacing(0);
    QLabel l1("2D", &top); l1.setStyleSheet("background:#0000ff;color:#ffffff"); l1.setFixedWidth(100);
    QLabel l2("2D", &top); l2.setStyleSheet("background:#0000ff;color:#ffffff"); l2.setFixedWidth(100);
    lay->addWidget(&l1);
    QWidget *area = nullptr;
    if (mode == "nativewidget") {
        QSurfaceFormat fmt; fmt.setStereo(true); fmt.setRenderableType(QSurfaceFormat::OpenGL);
        W *w = new W; w->setFormat(fmt); w->setAttribute(Qt::WA_NativeWindow); area = w;
    } else {
        area = QWidget::createWindowContainer(new SW, &top);
    }
    lay->addWidget(area, 1);
    lay->addWidget(&l2);
    top.show();
    QTimer::singleShot(1000, [&] { QWindow *w = top.windowHandle(); printf("top format stereo=%d size=%dx%d platform=%s rgba=%d/%d/%d/%d\n", int(w->format().stereo()), w->width(), w->height(), qPrintable(QGuiApplication::platformName()), w->format().redBufferSize(), w->format().greenBufferSize(), w->format().blueBufferSize(), w->format().alphaBufferSize()); printf("requested %d/%d/%d/%d type=%d\n", w->requestedFormat().redBufferSize(), w->requestedFormat().greenBufferSize(), w->requestedFormat().blueBufferSize(), w->requestedFormat().alphaBufferSize(), int(w->surfaceType())); if (area->windowHandle()) printf("area window format stereo=%d\n", int(area->windowHandle()->format().stereo())); fflush(stdout); });
    QTimer::singleShot(25000, &app, &QApplication::quit);
    return app.exec();
}
