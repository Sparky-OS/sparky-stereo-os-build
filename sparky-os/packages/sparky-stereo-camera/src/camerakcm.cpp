// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "camerakcm.h"

#include "packings.h"
#include "previewsource.h"

#include <KLocalizedString>
#include <KPluginFactory>

#include <QQmlEngine>
#include <QVariantMap>

using namespace Sparky::Camera;

K_PLUGIN_CLASS_WITH_JSON(CameraKcm, "kcm_sparkystereo_camera.json")

CameraKcm::CameraKcm(QObject *parent, const KPluginMetaData &data)
    : KQuickConfigModule(parent, data)
{
    qmlRegisterType<PreviewSource>("org.sparky.stereo.camera", 1, 0, "PreviewSource");
    setButtons(Apply | Default);
    for (const Packing &p : Sparky::Camera::packings()) {
        m_packings.append(QVariantMap{{QStringLiteral("id"), p.id}, {QStringLiteral("text"), p.text}, {QStringLiteral("group"), p.group}, {QStringLiteral("input"), p.videoOutput},
                                      {QStringLiteral("swap"), p.swapEyes}});
    }
    m_machineNotes = knownMachineNotes();
    // A camera plugged in or out while the page is open shows up without reopening it
    m_poll.setInterval(2500);
    connect(&m_poll, &QTimer::timeout, this, &CameraKcm::refresh);
    m_poll.start();
    refresh();
}

CameraInfo CameraKcm::currentInfo() const
{
    for (const CameraInfo &c : m_infos) {
        if (c.node.name == m_current) {
            return c;
        }
    }
    return {};
}

int CameraKcm::currentNodeId() const
{
    const CameraInfo c = currentInfo();
    return c.node.name.isEmpty() ? -1 : c.node.id;
}

QString CameraKcm::currentNote() const
{
    return currentInfo().note;
}

void CameraKcm::refresh()
{
    QString error;
    const QList<CameraInfo> infos = listCameras(&error);
    QVariantList list;
    QString now;
    for (const CameraInfo &c : infos) {
        list.append(QVariantMap{{QStringLiteral("name"), c.node.name}, {QStringLiteral("description"), c.node.description}, {QStringLiteral("isDefault"), c.node.isDefault},
                                {QStringLiteral("api"), c.node.api}, {QStringLiteral("note"), c.note}, {QStringLiteral("nodeId"), c.node.id}});
        if (c.node.isDefault) {
            now = c.node.name;
        }
    }
    const bool changed = list != m_cameraList || error != m_engineError;
    m_infos = infos;
    m_engineError = error;
    if (changed) {
        m_cameraList = list;
        Q_EMIT camerasChanged();
    }
    if (m_defaultInStore != now) {
        const bool unchangedByPerson = m_defaultChoice.isEmpty() || m_defaultChoice == m_defaultInStore;
        m_defaultInStore = now;
        if (unchangedByPerson) {
            m_defaultChoice = now;
            Q_EMIT defaultCameraChanged();
        }
    }
    bool stillThere = false;
    for (const CameraInfo &c : infos) {
        stillThere |= c.node.name == m_current;
    }
    if (!stillThere) {
        m_current = infos.isEmpty() ? QString() : (m_defaultChoice.isEmpty() ? infos.first().node.name : m_defaultChoice);
        readDetails();
        Q_EMIT currentChanged();
    } else if (changed) {
        readDetails();
    }
}

void CameraKcm::setCurrent(const QString &name)
{
    if (name == m_current) {
        return;
    }
    m_current = name;
    readDetails();
    Q_EMIT currentChanged();
}

void CameraKcm::setDefaultCamera(const QString &name)
{
    if (name == m_defaultChoice) {
        return;
    }
    m_defaultChoice = name;
    setNeedsSave(m_defaultChoice != m_defaultInStore || !m_touched.isEmpty());
    Q_EMIT defaultCameraChanged();
}

void CameraKcm::setPacking(const QString &id)
{
    if (id == m_packing) {
        return;
    }
    m_packing = id;
    m_touched.insert(m_current);
    setNeedsSave(true);
    Q_EMIT detailsChanged();
}

QVariantMap CameraKcm::packingInfo() const
{
    const Packing p = packingById(m_packing.isEmpty() ? QStringLiteral("mono") : m_packing);
    return {{QStringLiteral("id"), p.id}, {QStringLiteral("text"), p.text}, {QStringLiteral("input"), p.videoOutput}, {QStringLiteral("swap"), p.swapEyes}};
}

void CameraKcm::readDetails()
{
    m_formats.clear();
    m_controls.clear();
    m_mode.clear();
    m_modeError.clear();
    m_packing.clear();
    const CameraInfo info = currentInfo();
    if (!info.key.isEmpty()) {
        m_packing = loadChoice(info.key).packing;
        if (m_packing.isEmpty()) {
            m_packing = QStringLiteral("mono");
        }
        V4l2Camera dev(info.node.v4l2Path);
        if (dev.isOpen()) {
            for (const Format &f : dev.formats()) {
                QVariantList sizes;
                for (const SizeEntry &s : f.sizes) {
                    QVariantMap m{{QStringLiteral("width"), s.size.width}, {QStringLiteral("height"), s.size.height}, {QStringLiteral("stepwise"), s.stepwise}};
                    if (s.stepwise) {
                        m.insert(QStringLiteral("maxWidth"), s.max.width);
                        m.insert(QStringLiteral("maxHeight"), s.max.height);
                    }
                    sizes.append(m);
                }
                m_formats.append(QVariantMap{{QStringLiteral("fourcc"), f.fourcc}, {QStringLiteral("description"), f.description}, {QStringLiteral("compressed"), f.compressed}, {QStringLiteral("sizes"), sizes}});
            }
            const Mode mode = dev.currentMode();
            m_mode = {{QStringLiteral("fourcc"), mode.fourcc}, {QStringLiteral("width"), mode.size.width}, {QStringLiteral("height"), mode.size.height}, {QStringLiteral("fps"), mode.fps}};
            for (const Control &c : dev.controls()) {
                static const char *kinds[] = {"integer", "boolean", "menu", "integer-menu", "button", "other"};
                QVariantList menu;
                for (const auto &m : c.menu) {
                    menu.append(QVariantMap{{QStringLiteral("index"), m.index}, {QStringLiteral("text"), m.text}});
                }
                QString note;
                if (c.kind == Control::Other) {
                    note = i18n("This page cannot change this kind of control (%1).", c.otherKind);
                } else if (c.readOnly) {
                    note = i18n("The camera only reports this value.");
                } else if (c.inactive) {
                    note = i18n("The camera is not using this control now. Another setting turns it on.");
                }
                m_controls.append(QVariantMap{{QStringLiteral("id"), c.id}, {QStringLiteral("name"), c.name}, {QStringLiteral("kind"), QString::fromLatin1(kinds[c.kind])},
                                              {QStringLiteral("min"), c.minimum}, {QStringLiteral("max"), c.maximum}, {QStringLiteral("step"), c.step},
                                              {QStringLiteral("default"), c.defaultValue}, {QStringLiteral("value"), c.value}, {QStringLiteral("inactive"), c.inactive},
                                              {QStringLiteral("readOnly"), c.readOnly}, {QStringLiteral("editable"), c.kind != Control::Other && !c.readOnly}, {QStringLiteral("menu"), menu},
                                              {QStringLiteral("note"), note}});
            }
        } else {
            m_modeError = V4l2Camera::explain({false, dev.openError(), QStringLiteral("open")}, info.node.description);
        }
    }
    Q_EMIT detailsChanged();
}

QVariantList CameraKcm::frameRates(const QString &fourcc, int width, int height)
{
    QVariantList rates;
    V4l2Camera dev(currentInfo().node.v4l2Path);
    if (dev.isOpen()) {
        for (double r : dev.frameRates(fourcc, {width, height})) {
            rates.append(r);
        }
    }
    return rates;
}

void CameraKcm::setMode(const QString &fourcc, int width, int height, double fps)
{
    const CameraInfo info = currentInfo();
    V4l2Camera dev(info.node.v4l2Path);
    m_modeError.clear();
    if (!dev.isOpen()) {
        m_modeError = V4l2Camera::explain({false, dev.openError(), QStringLiteral("open")}, info.node.description);
    } else {
        const Result r = dev.setMode({fourcc, {width, height}, fps});
        if (!r.ok) {
            m_modeError = V4l2Camera::explain(r, info.node.description);
        } else {
            m_touched.insert(m_current);
            setNeedsSave(true);
        }
    }
    readDetails();
}

QString CameraKcm::setControl(int controlId, double value)
{
    const CameraInfo info = currentInfo();
    V4l2Camera dev(info.node.v4l2Path);
    if (!dev.isOpen()) {
        return V4l2Camera::explain({false, dev.openError(), QStringLiteral("open")}, info.node.description);
    }
    const Result r = dev.setControl(quint32(controlId), qint64(value));
    if (!r.ok) {
        return V4l2Camera::explain(r, info.node.description);
    }
    m_touched.insert(m_current);
    setNeedsSave(true);
    return {};
}

void CameraKcm::resetControls()
{
    const CameraInfo info = currentInfo();
    V4l2Camera dev(info.node.v4l2Path);
    if (dev.isOpen()) {
        QStringList failed;
        const Result r = dev.resetControls(&failed);
        if (!r.ok) {
            m_modeError = V4l2Camera::explain(r, info.node.description) + QLatin1Char(' ') + failed.join(QStringLiteral(", "));
        }
        m_touched.insert(m_current);
        setNeedsSave(true);
    }
    readDetails();
}

void CameraKcm::load()
{
    m_touched.clear();
    m_defaultChoice = m_defaultInStore;
    refresh();
    // what the person changed and did not save goes back to what was saved
    for (const CameraInfo &c : m_infos) {
        applyChoice(c);
    }
    readDetails();
    Q_EMIT defaultCameraChanged();
    setNeedsSave(false);
}

void CameraKcm::save()
{
    if (!m_defaultChoice.isEmpty() && m_defaultChoice != m_defaultInStore) {
        const QString error = Sparky::Camera::setDefaultCamera(m_defaultChoice);
        if (!error.isEmpty()) {
            m_engineError = error;
            Q_EMIT camerasChanged();
        }
    }
    for (const QString &name : std::as_const(m_touched)) {
        for (const CameraInfo &c : m_infos) {
            if (c.node.name != name || c.key.isEmpty()) {
                continue;
            }
            V4l2Camera dev(c.node.v4l2Path);
            CameraChoice choice = loadChoice(c.key);
            if (name == m_current) {
                choice.packing = m_packing == QLatin1String("mono") ? QString() : m_packing;
            }
            if (dev.isOpen()) {
                choice.hasMode = true;
                choice.mode = dev.currentMode();
                choice.controls.clear();
                choice.controlNames.clear();
                for (const Control &ctl : dev.controls()) {
                    if (ctl.kind != Control::Button && ctl.kind != Control::Other && !ctl.readOnly && ctl.value != ctl.defaultValue) {
                        choice.controls.insert(ctl.id, ctl.value);
                        choice.controlNames.insert(ctl.id, ctl.name);
                    }
                }
            }
            saveChoice(c.key, choice);
        }
    }
    m_touched.clear();
    setNeedsSave(false);
    refresh();
}

void CameraKcm::defaults()
{
    resetControls();
}

#include "camerakcm.moc"
