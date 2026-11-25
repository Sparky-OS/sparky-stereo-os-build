// r863-probe: a library preloaded into an unmodified Qt 6 Widgets program (queue row 863): it overrides QtCore's
// qt_startup_hook(), installs an event filter on the application, and
//  - logs, at every update request or expose of the top level that holds the watched widgets (the events whose
//    processing paints and commits it; Qt 5 sends the update request to the top level QWidget, Qt 6 to its QWindow),
//    where each watched widget belongs in its native parent:
//      "R863 flush step=K expect=X,Y expect2=X,Y margins=L,T event=update|expose"   (the format lag.py reads; margins
//      are the top level's frame margins, QWindow::frameMargins(): with Qt's own frame a child surface stands at its
//      widget's place plus these, and in full screen they are 0,0)
//  - drives the steps of R863_STEPS (comma separated), R863_WAIT ms apart, from R863_START ms after the first show:
//      grow / shrink        the top level 160x100 larger / back
//      dock                 every dock widget that is shown is hidden; the next "dock" shows them again
//      tab:N                the first tab widget with more than N pages (or R863_TABS's object name) to page N
//      splitter             the first splitter's first handle 80 px further
//      action:TEXT          the first action whose object name is TEXT or whose text contains TEXT is triggered
//      full                 the top level to full screen and, the next time, back
//      actionx:TEXT         the first action whose text, without its '&', is exactly TEXT is triggered
//      key:C                a key press and release of the printable key C (or esc) sent to the top level
//      click                a left button press and release at the middle of the first watched widget
//      wait                 nothing (one more wait, for a program that animates after the step before)
//      displace             the known bad case for a program's own layer (R863_LAYER=1, Krita): the layer window is moved
//                           40,40 px away from the widget (QWindow::setPosition); the program has to place it again.
//                           Not a known bad case for a native child widget: moving its window moves the widget too.
//      list                 prints the actions, docks, tab widgets, splitters and native child widgets
//  - each step waits for the case script's step-K.captured (see waitCaptured) before the next one starts;
//  - after each step's wait: "R863 step=K name=STEP expect=X,Y window=X,Y placed=0|1 visible=0|1 size=WxH [the same keys
//    with 2, 3, 4 for the next watched widgets] margins=L,T" (margins: the native parent's frame margins) and the
//    file $R863_OUT/step-K.ready (the case script captures the screen then), and at the end
//    "R863 result steps=N stale=M watched=W" and $R863_OUT/done; with R863_QUIT=1 the program is asked to quit.
// Watched widgets: R863_WATCH (comma separated class names, QObject::inherits()), else every native child widget whose
// window asks for stereo. A widget that is not visible counts as placed (Qt places its window when it is shown).
// Built with: g++ -shared -fPIC -std=c++17 -O1 r863-probe.cpp $(pkg-config --cflags --libs Qt6Widgets) -o r863-probe.so
// The same source builds against Qt 5 (Qt5Widgets; QtCore 5 exports qt_startup_hook@@Qt_5 too) for a Qt 5 program.
#include <QAction>
#include <QApplication>
#include <QDockWidget>
#include <QElapsedTimer>
#include <QFile>
#include <QKeyEvent>
#include <QMouseEvent>
#include <QPointer>
#include <QSplitter>
#include <QTabWidget>
#include <QTimer>
#include <QWidget>
#include <QWindow>
#include <cstdio>
#include <cstdlib>

namespace {

int g_step = 0;
bool g_docksHidden = false;
QList<QPointer<QDockWidget>> g_hiddenDocks;
bool g_full = false;

QByteArray env(const char *name, const char *fallback = "")
{
    const QByteArray v = qgetenv(name);
    return v.isEmpty() ? QByteArray(fallback) : v;
}

QList<QWidget *> watched()
{
    QList<QWidget *> out;
    const QList<QByteArray> classes = env("R863_WATCH").isEmpty() ? QList<QByteArray>() : env("R863_WATCH").split(',');
    for (QWidget *w : QApplication::allWidgets()) {
        if (w->isWindow())
            continue;
        bool want = false;
        if (!classes.isEmpty()) {
            for (const QByteArray &c : classes)
                want = want || w->inherits(c.constData());
        } else {
            want = w->windowHandle() && w->windowHandle()->requestedFormat().stereo();
        }
        if (want)
            out.append(w);
    }
    std::sort(out.begin(), out.end(), [](QWidget *a, QWidget *b) {
        const QPoint pa = a->mapTo(a->window(), QPoint()), pb = b->mapTo(b->window(), QPoint());
        return pa.y() != pb.y() ? pa.y() < pb.y() : pa.x() < pb.x();
    });
    return out;
}

QWidget *nativeParent(QWidget *w)
{
    QWidget *p = w->nativeParentWidget();
    return p ? p : w->window();
}

QPoint expected(QWidget *w)
{
    return w ? w->mapTo(nativeParent(w), QPoint()) : QPoint(-1, -1);
}

// R863_LAYER=1: the watched widget is shown through a child QWindow the program places itself at the widget's rectangle
// (Krita's KisStereoCanvasLayer): that window is the child of the native parent's window whose size is the widget's,
// a stereo one first
QWindow *layerWindow(QWidget *w)
{
    QWidget *np = nativeParent(w);
    if (!np || !np->windowHandle())
        return nullptr;
    QWindow *best = nullptr;
    for (QWindow *c : np->windowHandle()->findChildren<QWindow *>(QString(), Qt::FindDirectChildrenOnly)) {
        if (!c->isVisible() || c->size() != w->size())
            continue;
        if (!best || (c->requestedFormat().stereo() && !best->requestedFormat().stereo()))
            best = c;
    }
    return best;
}

QWindow *placedWindow(QWidget *w)
{
    if (!w)
        return nullptr;
    return qEnvironmentVariableIntValue("R863_LAYER") ? layerWindow(w) : w->windowHandle();
}

QPoint windowPos(QWidget *w)
{
    // a native child's own window (or, with R863_LAYER, the layer the program places); none to read gives -1,-1
    QWindow *h = placedWindow(w);
    return h ? h->position() : QPoint(-1, -1);
}

void touch(const QString &name)
{
    const QByteArray dir = env("R863_OUT");
    if (dir.isEmpty())
        return;
    QFile f(QString::fromLocal8Bit(dir) + QLatin1Char('/') + name);
    if (f.open(QIODevice::WriteOnly))
        f.write(QByteArray::number(g_step) + '\n');
}

QWidget *mainWindow()
{
    const QList<QWidget *> w = watched();
    if (!w.isEmpty())
        return w.first()->window();
    QWidget *best = nullptr;
    for (QWidget *t : QApplication::topLevelWidgets())
        if (t->isVisible() && (!best || t->width() * t->height() > best->width() * best->height()))
            best = t;
    return best;
}

// every action of the program: the main window's children and every widget's own list (menus, tool bars), once each
QList<QAction *> allActions()
{
    QList<QAction *> out;
    if (QWidget *top = mainWindow())
        out += top->findChildren<QAction *>();
    for (QWidget *w : QApplication::allWidgets())
        out += w->actions();
    QList<QAction *> unique;
    for (QAction *a : out)
        if (!unique.contains(a))
            unique.append(a);
    return unique;
}

template<typename T> T *first(const char *objectName = nullptr)
{
    QWidget *top = mainWindow();
    if (!top)
        return nullptr;
    for (T *t : top->findChildren<T *>()) {
        if (objectName && *objectName && t->objectName() != QLatin1String(objectName))
            continue;
        return t;
    }
    return nullptr;
}

void list()
{
    QWidget *top = mainWindow();
    fprintf(stderr, "R863 list top=%s %s\n", top ? top->metaObject()->className() : "-", top ? qPrintable(top->windowTitle()) : "");
    if (!top)
        return;
    for (QAction *a : allActions())
        if (!a->text().isEmpty())
            fprintf(stderr, "R863 list action name=%s text=%s checked=%d\n", qPrintable(a->objectName()), qPrintable(a->text()), int(a->isChecked()));
    for (QDockWidget *d : top->findChildren<QDockWidget *>())
        fprintf(stderr, "R863 list dock name=%s title=%s visible=%d\n", qPrintable(d->objectName()), qPrintable(d->windowTitle()), int(d->isVisible()));
    for (QTabWidget *t : top->findChildren<QTabWidget *>())
        fprintf(stderr, "R863 list tabs name=%s count=%d current=%d\n", qPrintable(t->objectName()), t->count(), t->currentIndex());
    for (QSplitter *s : top->findChildren<QSplitter *>())
        fprintf(stderr, "R863 list splitter name=%s count=%d\n", qPrintable(s->objectName()), s->count());
    for (QWidget *w : QApplication::allWidgets())
        if (!w->isWindow() && w->windowHandle())
            fprintf(stderr, "R863 list native class=%s name=%s stereo=%d visible=%d at=%d,%d size=%dx%d\n", w->metaObject()->className(),
                    qPrintable(w->objectName()), int(w->windowHandle()->requestedFormat().stereo()), int(w->isVisible()),
                    expected(w).x(), expected(w).y(), w->width(), w->height());
}

void doStep(const QByteArray &step)
{
    QWidget *top = mainWindow();
    if (step == "grow" && top) {
        top->resize(top->width() + 160, top->height() + 100);
    } else if (step == "shrink" && top) {
        top->resize(top->width() - 160, top->height() - 100);
    } else if (step == "dock" && top) {
        if (!g_docksHidden) {
            g_hiddenDocks.clear();
            for (QDockWidget *d : top->findChildren<QDockWidget *>())
                if (d->isVisible()) {
                    g_hiddenDocks.append(d);
                    d->hide();
                }
        } else {
            for (const QPointer<QDockWidget> &d : std::as_const(g_hiddenDocks))
                if (d)
                    d->show();
        }
        g_docksHidden = !g_docksHidden;
    } else if (step.startsWith("tab:")) {
        const int page = step.mid(4).toInt();
        QWidget *t0 = mainWindow();
        if (t0)
            for (QTabWidget *t : t0->findChildren<QTabWidget *>())
                if ((env("R863_TABS").isEmpty() && t->count() > page) || t->objectName() == QLatin1String(env("R863_TABS"))) {
                    t->setCurrentIndex(page);
                    break;
                }
    } else if (step == "splitter") {
        if (QSplitter *s = first<QSplitter>(env("R863_SPLITTER").constData())) {
            QList<int> sizes = s->sizes();
            if (sizes.size() >= 2) {
                sizes[0] += 80;
                sizes[1] -= 80;
                s->setSizes(sizes);
            }
        }
    } else if (step.startsWith("action:")) {
        const QString want = QString::fromUtf8(step.mid(7));
        for (QAction *a : allActions())
            if (a->objectName() == want || a->text().remove(QLatin1Char('&')).contains(want, Qt::CaseInsensitive)) {
                a->trigger();
                break;
            }
    } else if (step == "full" && top) {
        if (!g_full)
            top->showFullScreen();
        else
            top->showNormal();
        g_full = !g_full;
    } else if (step.startsWith("actionx:")) {
        const QString want = QString::fromUtf8(step.mid(8));
        for (QAction *a : allActions())
            if (a->text().remove(QLatin1Char('&')) == want) {
                a->trigger();
                break;
            }
    } else if (step.startsWith("key:") && top) {
        const QByteArray k = step.mid(4);
        const bool esc = k == "esc";
        const int code = esc ? int(Qt::Key_Escape) : int(Qt::Key_A) + (QChar::fromLatin1(k.at(0)).toLower().toLatin1() - 'a');
        const QString text = esc ? QString(QChar(27)) : QString::fromLatin1(k.left(1));
        QWidget *target = QApplication::focusWidget() ? QApplication::focusWidget() : top;
        QKeyEvent press(QEvent::KeyPress, code, Qt::NoModifier, text);
        QCoreApplication::sendEvent(target, &press);
        QKeyEvent release(QEvent::KeyRelease, code, Qt::NoModifier, text);
        QCoreApplication::sendEvent(target, &release);
    } else if (step == "click") {
        const QList<QWidget *> w = watched();
        if (!w.isEmpty()) {
            const QPointF local(w.first()->width() / 2.0, w.first()->height() / 2.0);
            const QPointF global = w.first()->mapToGlobal(local.toPoint()); // the QPoint form: Qt 5 has no other
            QMouseEvent press(QEvent::MouseButtonPress, local, global, Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
            QCoreApplication::sendEvent(w.first(), &press);
            QMouseEvent release(QEvent::MouseButtonRelease, local, global, Qt::LeftButton, Qt::NoButton, Qt::NoModifier);
            QCoreApplication::sendEvent(w.first(), &release);
        }
    } else if (step == "displace") {
        const QList<QWidget *> w = watched();
        if (QWindow *h = w.isEmpty() ? nullptr : placedWindow(w.first()))
            h->setPosition(h->position() + QPoint(40, 40));
    } else if (step == "list") {
        list();
    }
}

void report(const QByteArray &name)
{
    const QList<QWidget *> w = watched();
    QByteArray line = "R863 step=" + QByteArray::number(g_step) + " name=" + name;
    int stale = 0;
    for (int i = 0; i < w.size() && i < 4; ++i) {
        const QPoint e = expected(w[i]), h = windowPos(w[i]);
        const bool readable = placedWindow(w[i]) != nullptr;
        const bool placed = !w[i]->isVisible() || !readable || e == h;
        const QByteArray k = i ? QByteArray::number(i + 1) : QByteArray();
        line += " expect" + k + "=" + QByteArray::number(e.x()) + "," + QByteArray::number(e.y()) + " window" + k + "="
            + QByteArray::number(h.x()) + "," + QByteArray::number(h.y()) + " placed" + k + "=" + QByteArray::number(int(placed))
            + " visible" + k + "=" + QByteArray::number(int(w[i]->isVisible())) + " readable" + k + "="
            + QByteArray::number(int(readable)) + " size" + k + "="
            + QByteArray::number(w[i]->width()) + "x" + QByteArray::number(w[i]->height());
        stale += placed ? 0 : 1;
    }
    if (!w.isEmpty()) {
        QWidget *np = nativeParent(w.first());
        const QMargins m = np && np->windowHandle() ? np->windowHandle()->frameMargins() : QMargins();
        line += " margins=" + QByteArray::number(m.left()) + "," + QByteArray::number(m.top());
    }
    fprintf(stderr, "%s\n", line.constData());
    static int staleSteps = 0;
    staleSteps += stale ? 1 : 0;
    qApp->setProperty("r863StaleSteps", staleSteps);
}

class Probe : public QObject
{
public:
    bool eventFilter(QObject *o, QEvent *e) override
    {
        if (e->type() == QEvent::UpdateRequest || e->type() == QEvent::Expose) {
            // Qt 6 posts a widget window's update request to its QWindow; Qt 5 posts it to the top level QWidget
            QWindow *win = qobject_cast<QWindow *>(o);
            if (!win && e->type() == QEvent::UpdateRequest)
                if (QWidget *top = qobject_cast<QWidget *>(o); top && top->isWindow())
                    win = top->windowHandle();
            if (win) {
                const QList<QWidget *> w = watched();
                if (!w.isEmpty() && !win->parent() && nativeParent(w.first())->windowHandle() == win) {
                    const QPoint p = expected(w.first()), p2 = expected(w.size() > 1 ? w[1] : w.first());
                    const QMargins m = win->frameMargins();
                    fprintf(stderr, "R863 flush step=%d expect=%d,%d expect2=%d,%d margins=%d,%d event=%s\n", g_step, p.x(), p.y(), p2.x(),
                            p2.y(), m.left(), m.top(), e->type() == QEvent::Expose ? "expose" : "update");
                }
            }
        }
        if (e->type() == QEvent::Show && !m_started) {
            if (QWidget *w = qobject_cast<QWidget *>(o); w && w->isWindow()) {
                m_started = true;
                QTimer::singleShot(env("R863_START", "6000").toInt(), this, [this] { next(); });
            }
        }
        return QObject::eventFilter(o, e);
    }

private:
    void next()
    {
        const QList<QByteArray> steps = env("R863_STEPS").isEmpty() ? QList<QByteArray>() : env("R863_STEPS").split(',');
        const int wait = env("R863_WAIT", "1500").toInt();
        if (g_step == 0 && !m_startReported) {
            m_startReported = true;
            report("start");
            touch(QStringLiteral("step-0.ready"));
            waitCaptured(0);
            return;
        }
        if (g_step >= steps.size()) {
            fprintf(stderr, "R863 result steps=%d stale=%d watched=%d\n", int(steps.size()),
                    qApp->property("r863StaleSteps").toInt(), int(watched().size()));
            touch(QStringLiteral("done"));
            if (env("R863_QUIT") == "1")
                QTimer::singleShot(env("R863_QUIT_AFTER", "4000").toInt(), qApp, &QCoreApplication::quit);
            return;
        }
        const QByteArray step = steps[g_step];
        ++g_step;
        fprintf(stderr, "R863 do step=%d name=%s\n", g_step, step.constData());
        doStep(step);
        QTimer::singleShot(wait, this, [this, step] {
            report(step);
            touch(QStringLiteral("step-%1.ready").arg(g_step));
            waitCaptured(g_step);
        });
    }
    // the case script captures the screen when step-K.ready appears and writes step-K.captured when it is done; the
    // next step waits for that (R863_CAPTURE_TIMEOUT ms at most, then it says so and goes on); without R863_OUT it waits
    // R863_CAPTURE_MS
    void waitCaptured(int k)
    {
        const QByteArray dir = env("R863_OUT");
        if (dir.isEmpty()) {
            QTimer::singleShot(env("R863_CAPTURE_MS", "2500").toInt(), this, [this] { next(); });
            return;
        }
        const QString file = QString::fromLocal8Bit(dir) + QStringLiteral("/step-%1.captured").arg(k);
        const int limit = env("R863_CAPTURE_TIMEOUT", "60000").toInt();
        auto *timer = new QTimer(this);
        auto *clock = new QElapsedTimer;
        clock->start();
        timer->setInterval(100);
        connect(timer, &QTimer::timeout, this, [this, timer, clock, file, limit, k] {
            const bool there = QFile::exists(file);
            if (!there && clock->elapsed() < limit)
                return;
            if (!there)
                fprintf(stderr, "R863 capture timeout step=%d after %d ms\n", k, limit);
            timer->stop();
            timer->deleteLater();
            delete clock;
            QTimer::singleShot(200, this, [this] { next(); });
        });
        timer->start();
    }
    bool m_startReported = false;
    bool m_started = false;
};

} // namespace

extern "C" void qt_startup_hook()
{
    if (!qobject_cast<QApplication *>(QCoreApplication::instance()))
        return;
    static Probe *probe = new Probe;
    QCoreApplication::instance()->installEventFilter(probe);
}
