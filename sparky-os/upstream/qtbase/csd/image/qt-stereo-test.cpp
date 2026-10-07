// Qt stereo test: a QOpenGLWidget with QSurfaceFormat::StereoBuffers draws red into the left
// target buffer and green into the right one (QT_STEREO_SWAP_EYES=1 inverts them).
#include <QApplication>
#include <QOpenGLWidget>
#include <QOpenGLFunctions>
#include <QSurfaceFormat>
#include <QWindow>
#include <QTimer>
#include <QLabel>
#include <QWindow>
#include <QOpenGLContext>
#include <QOpenGLFunctions_2_1>
#include <QOpenGLWindow>
#include <QExposeEvent>
#include <cstdio>

class W : public QOpenGLWidget, protected QOpenGLFunctions
{
public:
    bool swap = qEnvironmentVariableIsSet("QT_STEREO_SWAP_EYES");
    void initializeGL() override
    {
        initializeOpenGLFunctions();
        printf("context stereo=%d requested stereo=%d\n", int(context()->format().stereo()), int(format().stereo()));
    }
    void paintGL() override
    {
        const bool left = currentTargetBuffer() == QOpenGLWidget::LeftBuffer;
        const bool red = left != swap;
        glClearColor(red ? 1 : 0, red ? 0 : 1, 0, 1);
        glClear(GL_COLOR_BUFFER_BIT);
        static int n = 0;
        if (n++ < 4)
            printf("paintGL target=%s colour=%s\n", left ? "left" : "right", red ? "red" : "green");
    }
};

// The 3D area as its own window: a native child, so its own wl_surface (a subsurface on Wayland)
class StereoWindow : public QWindow
{
public:
    StereoWindow()
    {
        setSurfaceType(QSurface::OpenGLSurface);
        QSurfaceFormat fmt;
        fmt.setStereo(true);
        fmt.setRenderableType(QSurfaceFormat::OpenGL);
        if (qEnvironmentVariableIsSet("QT_STEREO_PLAIN")) {
            fmt.setDepthBufferSize(0);
            fmt.setStencilBufferSize(0);
            fmt.setAlphaBufferSize(0);
        }
        setFormat(fmt);
        ctx.setFormat(fmt);
        ctx.create();
    }
    bool event(QEvent *e) override
    {
        if (e->type() == QEvent::UpdateRequest) {
            render();
            if (++frames < qEnvironmentVariableIntValue("QT_STEREO_FRAMES"))
                requestUpdate();
            return true;
        }
        return QWindow::event(e);
    }
    void exposeEvent(QExposeEvent *) override
    {
        render();
        requestUpdate();
    }
    int frames = 0;
    void render()
    {
        if (!isExposed())
            return;
        ctx.makeCurrent(this);
        QOpenGLFunctions_2_1 f;
        f.initializeOpenGLFunctions();
        const bool swap = qEnvironmentVariableIsSet("QT_STEREO_SWAP_EYES");
        f.glViewport(0, 0, width() * devicePixelRatio(), height() * devicePixelRatio());
        f.glDrawBuffer(GL_BACK_LEFT);
        f.glClearColor(swap ? 0 : 1, swap ? 1 : 0, 0, 1);
        f.glClear(GL_COLOR_BUFFER_BIT);
        f.glDrawBuffer(GL_BACK_RIGHT);
        f.glClearColor(swap ? 1 : 0, swap ? 0 : 1, 0, 1);
        f.glClear(GL_COLOR_BUFFER_BIT);
        if (frames == 0) {
            unsigned char px[4] = {0};
            GLint stereo = 0, fbo = -1;
            f.glGetIntegerv(GL_STEREO, &stereo);
            f.glGetIntegerv(GL_FRAMEBUFFER_BINDING, &fbo);
            f.glReadBuffer(GL_BACK_LEFT);
            f.glReadPixels(16, 16, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);
            printf("GL_STEREO=%d fbo=%d err=0x%x left px=%u,%u,%u,%u ", stereo, fbo, f.glGetError(), px[0], px[1], px[2], px[3]);
            f.glReadBuffer(GL_BACK_RIGHT);
            f.glReadPixels(16, 16, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);
            printf("right px=%u,%u,%u,%u\n", px[0], px[1], px[2], px[3]);
            fflush(stdout);
        }
        if (qEnvironmentVariableIsSet("QT_STEREO_FINISH"))
            f.glFinish();
        ctx.swapBuffers(this);
        static bool once = false;
        if (!once) {
            once = true;
            printf("child window: context stereo=%d window format stereo=%d size=%dx%d\n", int(ctx.format().stereo()),
                   int(format().stereo()), width(), height());
            fflush(stdout);
        }
    }
    QOpenGLContext ctx;
};

// A raw QOpenGLWindow: the application selects the eye itself with glDrawBuffer, no QRhi involved
class RawWindow : public QOpenGLWindow
{
public:
    void initializeGL() override
    {
        f.initializeOpenGLFunctions();
        printf("raw QOpenGLWindow: context stereo=%d window format stereo=%d\n", int(context()->format().stereo()),
               int(format().stereo()));
        fflush(stdout);
    }
    void paintGL() override
    {
        const bool swap = qEnvironmentVariableIsSet("QT_STEREO_SWAP_EYES");
        f.glViewport(0, 0, width() * devicePixelRatio(), height() * devicePixelRatio());
        f.glDrawBuffer(GL_BACK_LEFT);
        f.glClearColor(swap ? 0 : 1, swap ? 1 : 0, 0, 1);
        f.glClear(GL_COLOR_BUFFER_BIT);
        f.glDrawBuffer(GL_BACK_RIGHT);
        f.glClearColor(swap ? 1 : 0, swap ? 0 : 1, 0, 1);
        f.glClear(GL_COLOR_BUFFER_BIT);
        static int n = 0;
        if (n++ < 2) {
            printf("raw paintGL fbo=%u glerror=0x%x\n", defaultFramebufferObject(), f.glGetError());
            fflush(stdout);
        }
        update();
    }
    QOpenGLFunctions_2_1 f;
};

int main(int argc, char **argv)
{
    if (qEnvironmentVariableIsSet("QT_STEREO_OPENGLWINDOW")) {
        QGuiApplication app(argc, argv);
        QSurfaceFormat fmt;
        fmt.setStereo(true);
        fmt.setRenderableType(QSurfaceFormat::OpenGL);
        RawWindow w;
        w.setFormat(fmt);
        w.resize(qEnvironmentVariableIntValue("QT_STEREO_WIDTH") ?: 128, qEnvironmentVariableIntValue("QT_STEREO_HEIGHT") ?: 64);
        w.show();
        QTimer::singleShot(500, [&] { printf("platform=%s window=%dx%d\n", qPrintable(QGuiApplication::platformName()), w.width(), w.height()); fflush(stdout); });
        QTimer::singleShot(qEnvironmentVariableIntValue("QT_STEREO_HOLD_MS") ?: 12000, &app, &QGuiApplication::quit);
        return app.exec();
    }
    if (qEnvironmentVariableIsSet("QT_STEREO_TOPLEVEL")) {
        QGuiApplication app(argc, argv);
        StereoWindow sw;
        sw.resize(128, 64);
        sw.show();
        QTimer::singleShot(500, [&] { printf("platform=%s\n", qPrintable(QGuiApplication::platformName())); fflush(stdout); });
        QTimer::singleShot(qEnvironmentVariableIntValue("QT_STEREO_HOLD_MS") ?: 12000, &app, &QGuiApplication::quit);
        return app.exec();
    }
    if (qEnvironmentVariableIsSet("QT_STEREO_CHILD")) {
        QApplication app(argc, argv);
        QWidget top;
        top.move(0, 0);
        top.resize(128, 64);
        StereoWindow *sw = new StereoWindow;
        QWidget *container = QWidget::createWindowContainer(sw, &top);
        container->setGeometry(0, 0, 128, 64);
        QLabel label(&top);
        label.setAttribute(Qt::WA_NativeWindow);
        label.setStyleSheet("background: #0000ff; color: #0000ff;");
        label.setGeometry(0, 0, 24, 12);
        top.show();
        label.raise();
        QTimer::singleShot(500, [&] { printf("platform=%s\n", qPrintable(QGuiApplication::platformName())); fflush(stdout); });
        QTimer::singleShot(qEnvironmentVariableIntValue("QT_STEREO_HOLD_MS") ?: 12000, &app, &QApplication::quit);
        return app.exec();
    }
    QSurfaceFormat fmt;
    fmt.setStereo(!qEnvironmentVariableIsSet("QT_STEREO_OFF"));
    fmt.setRenderableType(QSurfaceFormat::OpenGL);
    QSurfaceFormat::setDefaultFormat(fmt);
    QApplication app(argc, argv);
    W w;
    w.setFormat(fmt);
    w.move(0, 0);
    w.resize(qEnvironmentVariableIntValue("QT_STEREO_WIDTH") ?: 128, qEnvironmentVariableIntValue("QT_STEREO_HEIGHT") ?: 64);
    // A 2D widget above the stereo one: Qt composes it into both views identically
    QLabel label(&w);
    label.setStyleSheet("background: #0000ff; color: #0000ff;");
    label.setGeometry(0, 0, 24, 12);
    label.setVisible(!qEnvironmentVariableIsSet("QT_STEREO_NOLABEL"));
    w.show();
    QTimer::singleShot(500, [&] {
        QWindow *win = w.windowHandle();
        printf("platform=%s window=%dx%d dpr=%g window format stereo=%d surfaceType=%d\n",
               qPrintable(QGuiApplication::platformName()), win->width(), win->height(), win->devicePixelRatio(),
               int(win->format().stereo()), int(win->surfaceType()));
        fflush(stdout);
    });
    QTimer::singleShot(qEnvironmentVariableIntValue("QT_STEREO_HOLD_MS") ?: 12000, &app, &QApplication::quit);
    return app.exec();
}
