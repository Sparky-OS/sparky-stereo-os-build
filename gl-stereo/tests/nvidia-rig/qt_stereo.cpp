#include <QApplication>
#include <QOpenGLWidget>
#include <QOpenGLFunctions>
#include <QSurfaceFormat>
#include <QTimer>
#include <cstdio>
class W : public QOpenGLWidget, protected QOpenGLFunctions {
protected:
    void initializeGL() override {
        initializeOpenGLFunctions();
        printf("RESULT qt platform=%s renderer=%s gles=%d stereo-fmt=%d\n", qPrintable(QGuiApplication::platformName()),
               (const char *)glGetString(GL_RENDERER), (int)context()->isOpenGLES(), (int)context()->format().stereo());
        fflush(stdout);
    }
    void paintGL() override {
        bool swap = qEnvironmentVariableIsSet("SWAP_EYES");
        if ((currentTargetBuffer() == QOpenGLWidget::RightBuffer) != swap) glClearColor(0, 0, 1, 1);
        else glClearColor(1, 0, 0, 1);
        glClear(GL_COLOR_BUFFER_BIT);
    }
};
int main(int argc, char **argv) {
    QApplication a(argc, argv);
    QSurfaceFormat f; f.setStereo(!qEnvironmentVariableIsSet("QT_MONO")); if (qEnvironmentVariableIsSet("QT_STEREO_DESKTOP")) f.setRenderableType(QSurfaceFormat::OpenGL); QSurfaceFormat::setDefaultFormat(f);
    W w; w.resize(400, 300); w.show();
    QTimer t; QObject::connect(&t, &QTimer::timeout, [&] { w.update(); }); t.start(16);
    return a.exec();
}
