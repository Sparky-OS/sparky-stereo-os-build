// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
#include "viewer.h"
#include "f3dworker.h"

#include <KConfigGroup>
#include <KLocalizedString>
#include <KSharedConfig>

#include <QFileInfo>
#include <QPointer>
#include <QProcess>
#include <QStandardPaths>

Viewer::Viewer(QObject *parent)
    : QObject(parent)
    , m_worker(std::make_unique<F3DWorker>())
{
    const KConfigGroup group(KSharedConfig::openConfig(), QStringLiteral("Viewer"));
    m_recent = group.readPathEntry("Recent", QStringList());
    m_stereo = group.readEntry("Enable3D", true);
    m_resolution = group.readEntry("Resolution", 100);
    for (const QString &path : std::as_const(m_recent)) {
        Q_UNUSED(path)
    }
    connect(m_worker.get(), &F3DWorker::loaded, this, [this](const QString &path, bool animation) {
        m_path = path;
        m_fileName = QFileInfo(path).fileName();
        m_hasAnimation = animation;
        m_playing = false;
        m_problem.clear();
        remember(path);
        Q_EMIT problemChanged();
        Q_EMIT playingChanged();
        Q_EMIT fileChanged();
    });
    connect(m_worker.get(), &F3DWorker::loadFailed, this, [this](const QString &path, const QString &reason) {
        const QString name = QFileInfo(path).fileName();
        m_problem = reason == QLatin1String("no reader")
            ? i18nc("@info the file is not a model the viewer knows", "“%1” is not a 3D model format the viewer can read.", name)
            : i18nc("@info a model file that cannot be read, then the reason", "“%1” cannot be read: %2", name, reason);
        Q_EMIT problemChanged();
    });
    connect(m_worker.get(), &F3DWorker::depthState, this, [this](int state, double, double) {
        depthState(state);
    });
    connect(m_worker.get(), &F3DWorker::stereoFailed, this, [this]() {
        m_notice = i18nc("@info", "3D could not be enabled: this display offers no stereo window");
        Q_EMIT noticeChanged();
    });
    connect(m_worker.get(), &F3DWorker::playingChanged, this, [this](bool playing) {
        m_playing = playing;
        Q_EMIT playingChanged();
    });
    m_worker->start();
}

Viewer::~Viewer()
{
    F3DWorker::Command quit;
    quit.kind = F3DWorker::Command::Quit;
    m_worker->post(quit);
    m_worker->wait(5000);
}

QStringList Viewer::nameFilters() const
{
    return {i18nc("@item:inlistbox file dialog filter", "3D models (*.glb *.gltf *.obj *.stl *.ply *.3mf *.fbx *.dae *.off *.step *.stp *.brep *.iges *.igs *.drc *.splat *.spz *.pts *.vtk *.vtp *.vtu *.3ds *.wrl *.xyz *.dxf)"),
            i18nc("@item:inlistbox file dialog filter", "All files (*)")};
}

void Viewer::depthState(int state)
{
    QString sentence;
    switch (state) {
    case 2:
        sentence = i18nc("@info", "3D depth: this desktop offers no depth limits, so both eyes show the same picture");
        break;
    case 3:
        sentence = i18nc("@info", "3D depth: the desktop has not delivered the depth limits yet, both eyes show the same picture for now");
        break;
    case 4:
        sentence = i18nc("@info", "3D depth: this window cannot read the desktop's depth limits, so both eyes show the same picture");
        break;
    default:
        break;
    }
    if (sentence != m_notice) {
        m_notice = sentence;
        Q_EMIT noticeChanged();
    }
}

void Viewer::setStereo(bool on)
{
    if (m_stereo == on) {
        return;
    }
    m_stereo = on;
    KConfigGroup(KSharedConfig::openConfig(), QStringLiteral("Viewer")).writeEntry("Enable3D", on);
    KSharedConfig::openConfig()->sync();
    F3DWorker::Command c;
    c.kind = F3DWorker::Command::Stereo;
    c.flag = on;
    m_worker->post(c);
    Q_EMIT stereoChanged();
}

void Viewer::setResolution(int percent)
{
    if (m_resolution == percent) {
        return;
    }
    m_resolution = percent;
    KConfigGroup(KSharedConfig::openConfig(), QStringLiteral("Viewer")).writeEntry("Resolution", percent);
    KSharedConfig::openConfig()->sync();
    sendPlace();
    Q_EMIT resolutionChanged();
}

void Viewer::open(const QUrl &url)
{
    if (url.isLocalFile()) {
        openPath(url.toLocalFile());
    }
}

void Viewer::openPath(const QString &path)
{
    F3DWorker::Command c;
    c.kind = F3DWorker::Command::Load;
    c.path = path;
    m_worker->post(c);
}

void Viewer::reset()
{
    F3DWorker::Command c;
    c.kind = F3DWorker::Command::Reset;
    m_worker->post(c);
}

void Viewer::togglePlay()
{
    F3DWorker::Command c;
    c.kind = F3DWorker::Command::TogglePlay;
    m_worker->post(c);
}

void Viewer::showDisplaySettings()
{
    if (!QProcess::startDetached(QStringLiteral("kcmshell6"), {QStringLiteral("kcm_kscreen")})) {
        m_problem = i18nc("@info", "Display Settings could not be opened: kcmshell6 was not found");
        Q_EMIT problemChanged();
    }
}

void Viewer::clearRecent()
{
    m_recent.clear();
    KConfigGroup(KSharedConfig::openConfig(), QStringLiteral("Viewer")).writePathEntry("Recent", m_recent);
    KSharedConfig::openConfig()->sync();
    Q_EMIT recentChanged();
}

void Viewer::remember(const QString &path)
{
    m_recent.removeAll(path);
    m_recent.prepend(path);
    while (m_recent.size() > 8) {
        m_recent.removeLast();
    }
    KConfigGroup(KSharedConfig::openConfig(), QStringLiteral("Viewer")).writePathEntry("Recent", m_recent);
    KSharedConfig::openConfig()->sync();
    Q_EMIT recentChanged();
}

void Viewer::place(QQuickWindow *window, qreal x, qreal y, qreal width, qreal height)
{
    m_window = window;
    m_area = QRectF(x, y, width, height);
    sendPlace();
}

void Viewer::sendPlace()
{
    if (!m_window || m_area.width() < 1 || m_area.height() < 1) {
        return;
    }
    const qreal ratio = m_window->devicePixelRatio();
    F3DWorker::Command c;
    c.kind = F3DWorker::Command::Place;
    c.parent = static_cast<quint64>(m_window->winId());
    c.rect = QRect(qRound(m_area.x() * ratio), qRound(m_area.y() * ratio), qRound(m_area.width() * ratio), qRound(m_area.height() * ratio));
    c.percent = m_resolution;
    m_worker->post(c);
}
