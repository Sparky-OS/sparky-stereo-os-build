// A widgets window with a stereo QOpenGLWidget in it (left red, right green), menu bar, tool bar, status bar,
// a label and a push button drawn over the GL widget.
//   QT_GLW_MODE=default   stereo on the default surface format (what Kubrick, KAlgebra and Kalzium do)
//   QT_GLW_MODE=widget    stereo on the widget's own format only (setFormat)
//   QT_GLW_MODE=none      mono everywhere
//   QT_GLW_MODE=toplevel  the GL widget is the window
//   QT_GLW_MODE=native    as widget, with WA_NativeWindow set on the GL widget
//   QT_GLW_NOOVERLAY=1 no overlay children; QT_GLW_STACKTOP=1 WA_AlwaysStackOnTop on the GL widget
//   QT_GLW_DIALOG=1 the GL widget lives in a dialog opened after the main window, never sized by the program
#include <QApplication>
#include <QMainWindow>
#include <QMenuBar>
#include <QToolBar>
#include <QStatusBar>
#include <QOpenGLWidget>
#include <QOpenGLFunctions>
#include <QSurfaceFormat>
#include <QLabel>
#include <QPushButton>
#include <QDialog>
#include <QVBoxLayout>
#include <QTimer>
#include <QScrollArea>
#include <QTabWidget>
#include <QScrollBar>
#include <QMouseEvent>
#include <cstdio>

class GL : public QOpenGLWidget, protected QOpenGLFunctions
{
public:
    GL(QWidget *p = nullptr, Qt::WindowFlags f = {}) : QOpenGLWidget(p, f) {}
    void mousePressEvent(QMouseEvent *e) override
    {
        printf("GL widget: mouse press at %d,%d\n", e->position().toPoint().x(), e->position().toPoint().y());
        fflush(stdout);
    }
    void initializeGL() override
    {
        initializeOpenGLFunctions();
        printf("GL widget: requested stereo=%d context stereo=%d size=%dx%d\n", int(format().stereo()), int(context()->format().stereo()), width(), height());
        fflush(stdout);
    }
    void paintGL() override
    {
        const bool left = currentTargetBuffer() == QOpenGLWidget::LeftBuffer;
        glClearColor(left ? 1 : 0, left ? 0 : 1, 0, 1);
        glClear(GL_COLOR_BUFFER_BIT);
    }
};

int main(int argc, char **argv)
{
    const QByteArray mode = qEnvironmentVariableIsSet("QT_GLW_MODE") ? qgetenv("QT_GLW_MODE") : QByteArray("default");
    QSurfaceFormat fmt;
    fmt.setRenderableType(QSurfaceFormat::OpenGL);
    fmt.setProfile(QSurfaceFormat::CompatibilityProfile);
    fmt.setVersion(2, 1);
    if (mode == "default" || mode == "toplevel" || mode == "nativedefault" || mode == "toplevelchild")
        fmt.setStereo(true);
    QSurfaceFormat::setDefaultFormat(fmt);
    if (qEnvironmentVariableIsSet("QT_GLW_NOSIBLINGS"))
        QCoreApplication::setAttribute(Qt::AA_DontCreateNativeWidgetSiblings);
    QApplication app(argc, argv);

    auto makeGl = [&](QWidget *parent) {
        GL *gl = new GL;
        if (mode == "widget" || mode == "native") {
            QSurfaceFormat f = fmt;
            f.setStereo(true);
            gl->setFormat(f);
        }
        if (mode == "native" || mode == "nativedefault")
            gl->setAttribute(Qt::WA_NativeWindow);
        if (qEnvironmentVariableIsSet("QT_GLW_STACKTOP"))
            gl->setAttribute(Qt::WA_AlwaysStackOnTop);
        gl->setMinimumSize(300, 200);
        if (parent)
            gl->setParent(parent);
        return gl;
    };
    auto overlay = [&](QWidget *gl) {
        if (qEnvironmentVariableIsSet("QT_GLW_NOOVERLAY"))
            return;
        QLabel *l = new QLabel("OVERLAY", gl);
        l->setStyleSheet("background: #204080; color: white; font-weight: bold; padding: 4px");
        l->move(20, 20);
        if (qEnvironmentVariableIsSet("QT_GLW_ALPHA")) {
            // a half transparent child over the 3D area
            QLabel *t = new QLabel("HALF", gl);
            t->setAttribute(Qt::WA_TranslucentBackground);
            t->setStyleSheet("background: rgba(0, 0, 128, 128); color: white; font-weight: bold; padding: 20px");
            t->move(150, 20);
        }
        QPushButton *b = new QPushButton("button", gl);
        b->move(20, 70);
        QObject::connect(b, &QPushButton::clicked, [] { printf("overlay button clicked\n"); fflush(stdout); });
    };

    if (mode == "toplevelchild") {
        // a stereo GL widget as a window of its own with a parent, never sized by the program (starts at 100x30)
        QMainWindow *w = new QMainWindow;
        w->menuBar()->addMenu("&File");
        w->setCentralWidget(new QLabel("main window, 2D"));
        w->resize(500, 300);
        w->show();
        GL *gl = new GL(w, Qt::Window);
        gl->setWindowTitle("GL window");
        QTimer::singleShot(1500, gl, [gl] { gl->show(); });
        return app.exec();
    }
    if (mode == "toplevel") {
        GL *gl = makeGl(nullptr);
        gl->resize(400, 300);
        gl->show();
        return app.exec();
    }
    if (qEnvironmentVariableIsSet("QT_GLW_DIALOG")) {
        QMainWindow w;
        w.menuBar()->addMenu("&File");
        w.setCentralWidget(new QLabel("main window, 2D"));
        w.resize(500, 300);
        w.show();
        QDialog *d = new QDialog(&w); // a dialog with a parent starts at Qt's default 100x30 and is never sized by us
        d->setWindowTitle("Dialog");
        QVBoxLayout *lay = new QVBoxLayout(d);
        lay->addWidget(new QLabel("dialog label (2D)"));
        GL *gl = makeGl(nullptr);
        lay->addWidget(gl);
        overlay(gl);
        QTimer::singleShot(1500, d, [d] { d->show(); });
        return app.exec();
    }
    QMainWindow w;
    w.menuBar()->addMenu("&File");
    w.menuBar()->addMenu("&View");
    QToolBar *tb = w.addToolBar("tools");
    tb->addWidget(new QLabel("toolbar label (2D)"));
    GL *gl = makeGl(nullptr);
    const QByteArray scen = qgetenv("QT_GLW_SCENARIO");
    if (scen == "scroll") {
        // the GL widget is 600x400 in a 300x200 viewport, scrolled by 120 rows
        QScrollArea *sa = new QScrollArea;
        QWidget *inner = new QWidget;
        inner->setFixedSize(600, 520);
        gl->setParent(inner);
        gl->setFixedSize(600, 400);
        gl->move(0, 0);
        QLabel *below = new QLabel("below the GL widget (2D)", inner);
        below->move(10, 440);
        sa->setWidget(inner);
        w.setCentralWidget(sa);
        sa->setMinimumSize(300, 200);
        QTimer::singleShot(1500, sa, [sa] { sa->verticalScrollBar()->setValue(120); sa->horizontalScrollBar()->setValue(60); });
    } else if (scen == "tabs") {
        QTabWidget *tw = new QTabWidget;
        tw->addTab(new QLabel("page one (2D)"), "one");
        QWidget *page = new QWidget;
        QVBoxLayout *l = new QVBoxLayout(page);
        l->addWidget(new QLabel("page two label (2D)"));
        gl->setParent(page);
        l->addWidget(gl);
        tw->addTab(page, "two");
        w.setCentralWidget(tw);
        QTimer::singleShot(1500, tw, [tw] { tw->setCurrentIndex(1); });
        if (qEnvironmentVariableIsSet("QT_GLW_TABBACK"))
            QTimer::singleShot(3500, tw, [tw] { tw->setCurrentIndex(0); });
    } else {
        w.setCentralWidget(gl);
    }
    overlay(gl);
    if (scen == "resize")
        QTimer::singleShot(1500, &w, [&w] { w.resize(900, 600); });
    if (scen == "toolbar")
        QTimer::singleShot(1500, tb, [tb] { tb->hide(); });
    w.statusBar()->showMessage("status bar (2D)");
    w.resize(640, 480);
    w.show();
    return app.exec();
}
