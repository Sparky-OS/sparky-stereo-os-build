// Test aid: Marble's MarbleWidget in a window as the Marble applications make it (translucent window), with the globe in stereo 3D.
// Settings by environment; writes what the analysis needs (the widget's rectangle in the window, the globe's radius and centre,
// the float items' rectangles) to PROBE_DUMP as JSON once the view has settled.
#include <MarbleWidget.h>
#include <MarbleModel.h>
#include <MarbleClock.h>
#include <MarbleMap.h>
#include <ViewportParams.h>
#include <AbstractFloatItem.h>
#include <RenderPlugin.h>
#include <QApplication>
#include <QDateTime>
#include <QTimeZone>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMainWindow>
#include <QTimer>
#include <QStatusBar>
#include <QMenuBar>
using namespace Marble;
static double env(const char *n, double d) { return qEnvironmentVariableIsSet(n) ? qEnvironmentVariable(n).toDouble() : d; }
int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    QMainWindow w;
    if (!qEnvironmentVariableIsSet("PROBE_OPAQUE")) {
        MarbleWidget::prepareStereo3DWindow(&w);
    }
    w.menuBar()->addMenu("File");
    w.statusBar()->showMessage("status bar");
    auto *m = new MarbleWidget;
    w.setCentralWidget(m);
    m->setMapThemeId(qEnvironmentVariable("PROBE_THEME", "earth/bluemarble/bluemarble.dgml"));
    m->setProjection(Spherical);
    m->model()->clock()->setDateTime(QDateTime(QDate(2026, 10, 7), QTime(12, 0), QTimeZone::UTC));
    m->model()->clock()->setSpeed(0);
    m->setShowCompass(true);
    m->setShowScaleBar(true);
    m->setShowOverviewMap(qEnvironmentVariableIsSet("PROBE_OVERVIEW"));
    m->setShowGrid(true);
    m->setShowCities(true);
    m->setShowPlaces(true);
    m->setShowAtmosphere(false);
    if (qEnvironmentVariableIsSet("PROBE_NOBACKGROUND")) {
        m->setShowBackground(false);
    }
    m->setShowClouds(false);
    m->setShowSunShading(false);
    if (qEnvironmentVariableIsSet("PROBE_NOITEMS")) {
        for (AbstractFloatItem *f : m->floatItems()) {
            f->setVisible(false);
        }
        m->setShowCompass(false);
        m->setShowScaleBar(false);
    }
    m->centerOn(env("PROBE_LON", 10), env("PROBE_LAT", 20));
    m->setRadius(int(env("PROBE_RADIUS", 300)));
    if (qEnvironmentVariableIsSet("PROBE_SEP")) {
        m->setStereo3DSeparation(env("PROBE_SEP", 2));
    }
    if (qEnvironmentVariableIsSet("PROBE_STEREO")) {
        m->setStereo3D(true);
    }
    if (qEnvironmentVariableIsSet("PROBE_WINDOWED")) {
        w.resize(900, 600);
        w.show();
    } else {
        w.showFullScreen();
    }
    QTimer::singleShot(int(env("PROBE_DELAY_MS", 5000)), [&] {
        QJsonObject o;
        o["platform"] = QGuiApplication::platformName();
        o["stereo3D"] = m->stereo3D();
        o["supported"] = MarbleWidget::isStereo3DSupported();
        o["separation_deg"] = m->stereo3DSeparation();
        const QPoint p = m->mapTo(&w, QPoint(0, 0));
        o["widget"] = QJsonArray{p.x(), p.y(), m->width(), m->height()};
        o["window"] = QJsonArray{w.width(), w.height()};
        o["dpr"] = m->devicePixelRatioF();
        o["radius"] = m->radius();
        o["center_lon"] = m->centerLongitude();
        o["center_lat"] = m->centerLatitude();
        QJsonArray items;
        for (AbstractFloatItem *f : m->floatItems()) {
            if (!f->visible() || !f->enabled()) continue;
            const QPointF pos = f->positivePosition();
            items.append(QJsonObject{{"name", f->nameId()}, {"rect", QJsonArray{pos.x() + p.x(), pos.y() + p.y(), f->size().width(), f->size().height()}}});
        }
        o["float_items"] = items;
        QFile out(qEnvironmentVariable("PROBE_DUMP", "/tmp/probe.json"));
        if (out.open(QIODevice::WriteOnly)) out.write(QJsonDocument(o).toJson());
    });
    return app.exec();
}
