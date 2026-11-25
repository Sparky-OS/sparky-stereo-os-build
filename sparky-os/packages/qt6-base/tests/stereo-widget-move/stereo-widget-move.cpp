// stereo-widget-move: stereo QOpenGLWidgets under alien ancestors whose windows must move while the window repaints
// (queue row 863). The edition's qt6-base gives such a widget a native window of its own (a subsurface on Wayland), and
// its alien ancestors do not move that window when they move. The test moves the ancestors step by step while every GL
// widget animates, so the window always repaints, and says where each stereo window stands after each step.
// Two stereo widgets, as FreeCAD's two 3D views of one document: the first a plain stereo QOpenGLWidget drawn in
// paintGL(), the second a QGraphicsView whose viewport is a stereo QOpenGLWidget, showing the same scene. The view's
// paint asks the first widget for a new frame (a change to a shared scene redraws every view of it: FreeCAD's Quarter
// processes Coin's delay queue in its paint event, and "processing the sensors might trigger a redraw in another
// context"), so the window is dirty while it flushes; a repaint from inside the flush then rebuilds the top level's
// texture lists. A small mono QOpenGLWidget in the status bar animates too.
//
// Usage: stereo-widget-move MODE [STEPS] [WAIT_MS]
//   scroll    a QScrollArea's content widget (alien) holds the two stereo widgets and a 2D marker above them; each
//             step scrolls the area by 37 pixels, ten steps down, then ten up
//   viewport  two QGraphicsViews of the one scene whose viewports are stereo widgets (FreeCAD's 3D views), in the
//             central widget of a QMainWindow beside a dock that each step hides or shows
//   itemview  a QTableWidget with the stereo widgets as cell widgets, scrolled by 23 pixels each step (an item view
//             moves its cell widgets with QWidget::scroll(), not with move())
//   float     the stereo widgets inside a dock that each step floats or docks again (a new native parent)
// stderr: "R863 flush step=K expect=X,Y expect2=X,Y event=update|expose" for each update request or expose of the main
// window (the events whose processing paints and commits its picture), with each stereo widget's place in its native
// parent at that moment, so WAYLAND_DEBUG=client's commits that follow say whether the stereo window stood there;
// "R863 paint step=K expect=X,Y" for each paint of a 2D marker beside the first stereo widget; after each step's
// WAIT_MS of events "R863 step=K expect=X,Y window=X,Y placed=0|1" (the first stereo widget; placed2 for the second;
// a widget that is not visible counts as placed);
// at the end "R863 result mode=MODE steps=N stereo=0|1 native=0|1 stale=M" (stereo and native: both widgets have a
// stereo window of their own; stale: the steps after which a stereo window was not where its widget is).
// Exit status 0 when the run ends, whatever it measured.
#include <QApplication>
#include <QDockWidget>
#include <QGraphicsScene>
#include <QGraphicsView>
#include <QHBoxLayout>
#include <QHeaderView>
#include <QLabel>
#include <QMainWindow>
#include <QOpenGLFunctions>
#include <QOpenGLWidget>
#include <QPointer>
#include <QScrollArea>
#include <QScrollBar>
#include <QStatusBar>
#include <QSurfaceFormat>
#include <QTableWidget>
#include <QTimer>
#include <QVBoxLayout>
#include <QWindow>
#include <cstdio>
#include <functional>

static int g_step = 0;
static QWidget *g_gl = nullptr;
static QWidget *g_gl2 = nullptr;

static QPoint expectedPos(QWidget *gl)
{
    QWidget *np = gl ? gl->nativeParentWidget() : nullptr;
    return np ? gl->mapTo(np, QPoint()) : QPoint(-1, -1);
}

static QPoint windowPos(QWidget *gl)
{
    QWindow *w = gl ? gl->windowHandle() : nullptr;
    return w ? w->position() : QPoint(-1, -1);
}

class Gl : public QOpenGLWidget, protected QOpenGLFunctions
{
public:
    explicit Gl(bool stereo, QWidget *parent = nullptr) : QOpenGLWidget(parent), m_stereo(stereo)
    {
        QSurfaceFormat f = format();
        f.setStereo(stereo);
        setFormat(f);
        if (stereo)
            setMinimumSize(320, 200);
    }

protected:
    void initializeGL() override { initializeOpenGLFunctions(); }
    void paintGL() override
    {
        // left red, right green (a mono widget blue), a shade that changes every frame; update() keeps it animating
        const bool left = currentTargetBuffer() == QOpenGLWidget::LeftBuffer;
        const float shade = 0.5f + 0.5f * float(m_frame % 16) / 16.0f;
        if (m_stereo)
            glClearColor(left ? shade : 0, left ? 0 : shade, 0, 1);
        else
            glClearColor(0, 0, shade, 1);
        glClear(GL_COLOR_BUFFER_BIT);
        if (!m_stereo || !left)
            ++m_frame;
        update();
    }

private:
    bool m_stereo;
    int m_frame = 0;
};

// A 2D widget beside the first stereo widget in the same alien parent
class Marker : public QLabel
{
public:
    using QLabel::QLabel;

protected:
    void paintEvent(QPaintEvent *e) override
    {
        QLabel::paintEvent(e);
        const QPoint p = expectedPos(g_gl);
        fprintf(stderr, "R863 paint step=%d expect=%d,%d\n", g_step, p.x(), p.y());
    }
};

// The main window's update requests and exposes: their processing paints and commits its picture
class FlushLog : public QObject
{
protected:
    bool eventFilter(QObject *o, QEvent *e) override
    {
        if (g_gl && (e->type() == QEvent::UpdateRequest || e->type() == QEvent::Expose)) {
            const QPoint p = expectedPos(g_gl), p2 = expectedPos(g_gl2);
            fprintf(stderr, "R863 flush step=%d expect=%d,%d expect2=%d,%d event=%s\n", g_step, p.x(), p.y(), p2.x(),
                    p2.y(), e->type() == QEvent::Expose ? "expose" : "update");
        }
        return QObject::eventFilter(o, e);
    }
};

// A view of the shared scene: its paint asks the other view of the scene for a new frame
class SceneView : public QGraphicsView
{
public:
    using QGraphicsView::QGraphicsView;
    QPointer<QWidget> partner;

protected:
    void drawForeground(QPainter *painter, const QRectF &rect) override
    {
        QGraphicsView::drawForeground(painter, rect);
        if (partner)
            partner->update();
    }
};

static QGraphicsScene *sharedScene(QObject *owner)
{
    static QGraphicsScene *scene = nullptr;
    if (!scene) {
        scene = new QGraphicsScene(0, 0, 400, 300, owner);
        scene->addText(QStringLiteral("2D text in the graphics scene"));
    }
    return scene;
}

static SceneView *stereoView(QObject *owner, QWidget *partner)
{
    SceneView *view = new SceneView(sharedScene(owner));
    view->partner = partner;
    view->setViewport(new Gl(true));
    // a viewport's paint event goes to the view, so paintGL() never runs: the view is animated from here
    QTimer *frames = new QTimer(view);
    QObject::connect(frames, &QTimer::timeout, view->viewport(), qOverload<>(&QWidget::update));
    frames->start(16);
    return view;
}

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    const QByteArray mode = argc > 1 ? QByteArray(argv[1]) : QByteArray("scroll");
    const int steps = argc > 2 ? atoi(argv[2]) : 40;
    const int waitMs = argc > 3 ? atoi(argv[3]) : 120;

    QMainWindow window;
    window.setWindowTitle(QStringLiteral("stereo-widget-move"));
    window.resize(1000, 700);
    Gl *mono = new Gl(false);
    mono->setFixedSize(160, 22);
    window.statusBar()->addPermanentWidget(mono);
    window.statusBar()->showMessage(QStringLiteral("2D status bar with a mono GL widget"));
    QDockWidget *dock = new QDockWidget(QStringLiteral("Dock"), &window);
    std::function<void(int)> doStep;

    if (mode == "scroll") {
        QWidget *central = new QWidget;
        QVBoxLayout *lay = new QVBoxLayout(central);
        lay->addWidget(new QLabel(QStringLiteral("2D above the scroll area")));
        QScrollArea *scroll = new QScrollArea;
        QWidget *content = new QWidget;
        content->setFixedSize(760, 1400);
        Marker *marker = new Marker(QStringLiteral("2D marker above the 3D areas"), content);
        marker->setGeometry(40, 300, 320, 24);
        Gl *gl = new Gl(true, content);
        gl->setGeometry(40, 330, 320, 200);
        SceneView *v2 = stereoView(&window, gl);
        v2->setParent(content);
        v2->setGeometry(400, 330, 320, 200);
        g_gl = gl;
        g_gl2 = v2->viewport();
        scroll->setWidget(content);
        lay->addWidget(scroll);
        window.setCentralWidget(central);
        dock->setWidget(new QLabel(QStringLiteral("dock")));
        window.addDockWidget(Qt::LeftDockWidgetArea, dock);
        doStep = [scroll](int k) {
            QScrollBar *bar = scroll->verticalScrollBar();
            bar->setValue(bar->value() + (((k - 1) / 10) % 2 ? -37 : 37));
        };
    } else if (mode == "viewport") {
        QWidget *central = new QWidget;
        QVBoxLayout *lay = new QVBoxLayout(central);
        lay->addWidget(new Marker(QStringLiteral("2D marker above the 3D views")));
        QHBoxLayout *views = new QHBoxLayout;
        SceneView *v1 = stereoView(&window, nullptr), *v2 = stereoView(&window, nullptr);
        v1->partner = v2->viewport();
        v2->partner = v1->viewport();
        views->addWidget(v1);
        views->addWidget(v2);
        lay->addLayout(views);
        g_gl = v1->viewport();
        g_gl2 = v2->viewport();
        window.setCentralWidget(central);
        dock->setWidget(new QLabel(QStringLiteral("a dock whose width moves the 3D views")));
        dock->setMinimumWidth(260);
        window.addDockWidget(Qt::LeftDockWidgetArea, dock);
        doStep = [dock](int) { dock->setVisible(!dock->isVisible()); };
    } else if (mode == "itemview") {
        QTableWidget *table = new QTableWidget(40, 2);
        table->verticalHeader()->setDefaultSectionSize(60);
        table->setColumnWidth(0, 360);
        table->setColumnWidth(1, 360);
        table->setVerticalScrollMode(QAbstractItemView::ScrollPerPixel);
        for (int r = 0; r < 40; ++r)
            table->setItem(r, 1, new QTableWidgetItem(QStringLiteral("row %1").arg(r)));
        Gl *gl = new Gl(true);
        SceneView *v2 = stereoView(&window, gl);
        table->setRowHeight(6, 220);
        table->setRowHeight(9, 220);
        table->setCellWidget(6, 0, gl);
        table->setCellWidget(9, 0, v2);
        g_gl = gl;
        g_gl2 = v2->viewport();
        QWidget *central = new QWidget;
        QVBoxLayout *lay = new QVBoxLayout(central);
        lay->addWidget(new Marker(QStringLiteral("2D marker above the table")));
        lay->addWidget(table);
        window.setCentralWidget(central);
        dock->setWidget(new QLabel(QStringLiteral("dock")));
        window.addDockWidget(Qt::LeftDockWidgetArea, dock);
        doStep = [table](int k) {
            QScrollBar *bar = table->verticalScrollBar();
            bar->setValue(bar->value() + (((k - 1) / 10) % 2 ? -23 : 23));
        };
    } else if (mode == "float") {
        window.setCentralWidget(new QLabel(QStringLiteral("2D central widget")));
        QWidget *inside = new QWidget;
        QVBoxLayout *lay = new QVBoxLayout(inside);
        lay->addWidget(new Marker(QStringLiteral("2D marker above the 3D areas in the dock")));
        Gl *gl = new Gl(true);
        SceneView *v2 = stereoView(&window, gl);
        v2->setMinimumSize(320, 200);
        g_gl = gl;
        g_gl2 = v2->viewport();
        lay->addWidget(gl);
        lay->addWidget(v2);
        dock->setWidget(inside);
        window.addDockWidget(Qt::LeftDockWidgetArea, dock);
        doStep = [dock](int) { dock->setFloating(!dock->isFloating()); };
    } else {
        fprintf(stderr, "unknown mode %s\n", mode.constData());
        return 2;
    }

    window.show();
    FlushLog flushLog;
    window.windowHandle()->installEventFilter(&flushLog);
    int stale = 0;
    QTimer timer;
    timer.setInterval(waitMs);
    QObject::connect(&timer, &QTimer::timeout, &app, [&] {
        // the places after the previous step's WAIT_MS of events
        if (g_step > 0) {
            const QPoint want = expectedPos(g_gl), have = windowPos(g_gl);
            const QPoint want2 = expectedPos(g_gl2), have2 = windowPos(g_gl2);
            // a hidden widget (an item view's cell scrolled out) has no place to keep: Qt places its window when it
            // is shown again (QWidgetPrivate::show_sys())
            const bool placed = g_gl->windowHandle() && (!g_gl->isVisible() || want == have);
            const bool placed2 = g_gl2->windowHandle() && (!g_gl2->isVisible() || want2 == have2);
            if (!placed || !placed2)
                ++stale;
            fprintf(stderr, "R863 step=%d expect=%d,%d window=%d,%d placed=%d expect2=%d,%d window2=%d,%d placed2=%d\n",
                    g_step, want.x(), want.y(), have.x(), have.y(), int(placed), want2.x(), want2.y(), have2.x(),
                    have2.y(), int(placed2));
        }
        if (g_step == steps) {
            QWindow *w = g_gl->windowHandle(), *w2 = g_gl2->windowHandle();
            const bool stereo = w && w2 && w->requestedFormat().stereo() && w2->requestedFormat().stereo();
            fprintf(stderr, "R863 result mode=%s steps=%d stereo=%d native=%d stale=%d\n", mode.constData(), steps,
                    int(stereo), int(w && w2), stale);
            timer.stop();
            QTimer::singleShot(300, &app, &QApplication::quit);
            return;
        }
        ++g_step;
        doStep(g_step);
    });
    // the first step once the window has been shown and drawn for a while
    QTimer::singleShot(1500, &timer, [&timer] { timer.start(); });
    return app.exec();
}
