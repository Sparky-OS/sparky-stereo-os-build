// Test aid: a QMainWindow with a menu bar, a label and a stereo QOpenGLWidget; logs every size the window and the widget get.
#include <QApplication>
#include <QMainWindow>
#include <QMenuBar>
#include <QStatusBar>
#include <QLabel>
#include <QOpenGLWidget>
#include <QOpenGLFunctions>
#include <QSurfaceFormat>
#include <QResizeEvent>
#include <QElapsedTimer>
#include <QWindow>
#include <QOpenGLContext>
#include <QTimer>
#include <cstdio>
static QElapsedTimer t;
struct GL : QOpenGLWidget, QOpenGLFunctions {
    void initializeGL() override { initializeOpenGLFunctions(); }
    void paintGL() override {
        const bool right = currentTargetBuffer() == QOpenGLWidget::RightBuffer;
        glClearColor(right ? 0 : 1, 0, right ? 1 : 0, 1); glClear(GL_COLOR_BUFFER_BIT);
    }
    void resizeEvent(QResizeEvent *e) override { QOpenGLWidget::resizeEvent(e); fprintf(stderr, "%6lld ms GLwidget resize %dx%d stereo=%d\n", t.elapsed(), e->size().width(), e->size().height(), (int)format().stereo()); }
};
struct Win : QMainWindow {
    void resizeEvent(QResizeEvent *e) override { QMainWindow::resizeEvent(e); fprintf(stderr, "%6lld ms window resize %dx%d (old %dx%d) frame=%dx%d\n", t.elapsed(), e->size().width(), e->size().height(), e->oldSize().width(), e->oldSize().height(), frameGeometry().width(), frameGeometry().height()); }
};
struct GLW : QWindow, QOpenGLFunctions {
    QOpenGLContext *ctx = nullptr;
    GLW() { setSurfaceType(QSurface::OpenGLSurface); }
    void render() {
        if (!isExposed()) return;
        if (!ctx) { ctx = new QOpenGLContext(this); ctx->setFormat(format()); ctx->create(); }
        ctx->makeCurrent(this); initializeOpenGLFunctions();
        glDrawBuffer(GL_BACK_LEFT); glClearColor(1, 0, 0, 1); glClear(GL_COLOR_BUFFER_BIT);
        glDrawBuffer(GL_BACK_RIGHT); glClearColor(0, 0, 1, 1); glClear(GL_COLOR_BUFFER_BIT);
        ctx->swapBuffers(this);
    }
    void exposeEvent(QExposeEvent *) override { render(); }
    void resizeEvent(QResizeEvent *e) override { fprintf(stderr, "%6lld ms GLwindow resize %dx%d requested stereo=%d\n", t.elapsed(), e->size().width(), e->size().height(), (int)format().stereo()); }
};
int main(int argc, char **argv)
{
    t.start();
    QSurfaceFormat f = QSurfaceFormat::defaultFormat();
    f.setStereo(qEnvironmentVariableIsEmpty("NOSTEREO") && qEnvironmentVariableIsEmpty("NATIVE") && qEnvironmentVariableIsEmpty("CONTAINER"));
    QSurfaceFormat::setDefaultFormat(f);
    QApplication app(argc, argv);
    QWidget *early = nullptr;
    if (!qEnvironmentVariableIsEmpty("SPLASH_FIRST")) {
        early = new QWidget(nullptr, Qt::SplashScreen | Qt::WindowStaysOnTopHint); early->resize(960, 480); early->show(); app.processEvents();
        fprintf(stderr, "%6lld ms early splash shown\n", t.elapsed());
    }
    Win w;
    w.menuBar()->addMenu("File"); w.menuBar()->addMenu("Edit"); w.menuBar()->addMenu("View");
    if (!qEnvironmentVariableIsEmpty("CONTAINER")) {
        auto *glw = new GLW; QSurfaceFormat gf; gf.setStereo(true); glw->setFormat(gf);
        w.setCentralWidget(QWidget::createWindowContainer(glw, &w));
        w.statusBar()->showMessage("status bar text");
        w.resize(640, 400); w.show();
        return app.exec();
    }
    auto *gl = new GL;
    if (!qEnvironmentVariableIsEmpty("NATIVE")) {
        QSurfaceFormat gf = QSurfaceFormat::defaultFormat(); gf.setStereo(true);
        gl->setFormat(gf);
        gl->setAttribute(Qt::WA_NativeWindow, true);
        fprintf(stderr, "native stereo widget\n");
    }
    w.setCentralWidget(gl);
    w.statusBar()->showMessage("status bar text");
    w.resize(640, 400);
    w.show();
    if (early) QTimer::singleShot(3000, early, [early]{ fprintf(stderr, "%6lld ms early splash closed\n", t.elapsed()); early->resize(640, 532); early->close(); });
    if (!qEnvironmentVariableIsEmpty("SPLASH_AT")) QTimer::singleShot(qEnvironmentVariableIntValue("SPLASH_AT"), &w, [&w]{
        auto *sp = new QWidget(nullptr, Qt::SplashScreen | Qt::WindowStaysOnTopHint); sp->resize(640, 480); sp->show();
        fprintf(stderr, "%6lld ms splash shown\n", t.elapsed());
        QTimer::singleShot(2000, sp, [sp]{ fprintf(stderr, "%6lld ms splash closed\n", t.elapsed()); sp->close(); }); });
    if (!qEnvironmentVariableIsEmpty("RESIZE_AT")) QTimer::singleShot(qEnvironmentVariableIntValue("RESIZE_AT"), &w, [&w]{ fprintf(stderr, "%6lld ms requesting resize 641x400\n", t.elapsed()); w.resize(641, 400); });
    return app.exec();
}
