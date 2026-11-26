// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#include "camerakcm.h"

#include "packings.h"
#include "previewsource.h"
#include "standardnames.h"

#include <KLocalizedString>
#include <KPluginFactory>

#include <QQmlEngine>
#include <QVariantMap>

#include <linux/videodev2.h>

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
                                {QStringLiteral("api"), c.node.api}, {QStringLiteral("note"), c.note}, {QStringLiteral("nodeId"), c.node.id},
                                {QStringLiteral("serial"), c.node.serial}});
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
                m_formats.append(QVariantMap{{QStringLiteral("fourcc"), f.fourcc}, {QStringLiteral("description"), formatLabel(f.fourcc, f.description)}, {QStringLiteral("compressed"), f.compressed}, {QStringLiteral("sizes"), sizes}});
            }
            const Mode mode = dev.currentMode();
            m_mode = {{QStringLiteral("fourcc"), mode.fourcc}, {QStringLiteral("width"), mode.size.width}, {QStringLiteral("height"), mode.size.height}, {QStringLiteral("fps"), mode.fps}};
            m_controlFlags.clear();
            for (const Control &c : dev.controls()) {
                static const char *kinds[] = {"integer", "boolean", "menu", "integer-menu", "button", "other"};
                QVariantList menu;
                for (const auto &m : c.menu) {
                    menu.append(QVariantMap{{QStringLiteral("index"), m.index}, {QStringLiteral("text"), menuLabel(c.id, m.index, m.text)}});
                }
                // Every control is shown; the note says why one cannot be changed now or is not kept (keepRule)
                const Keep keep = keepRule(c);
                QString note;
                if (c.kind == Control::Other) {
                    note = i18n("This page cannot change this kind of control (%1).", c.otherKind);
                } else if (c.readOnly) {
                    note = i18n("The camera only reports this value.");
                } else if (c.inactive) {
                    note = i18n("The camera is not using this control now. Another setting turns it on.");
                } else if (c.grabbed) {
                    note = i18n("Another program is using this control now, so it cannot be changed here.");
                } else if (keep == Keep::Motion || keep == Keep::WriteOnly || keep == Keep::Action) {
                    note = i18n("This control moves the camera or starts an action, so it is not kept for the next time the camera is plugged in.");
                } else if (keep == Keep::Volatile) {
                    note = i18n("The camera changes this value by itself, so it is not kept.");
                } else if (keep == Keep::NoRange) {
                    note = i18n("The camera gives this control no range, so there is nothing to set or keep.");
                }
                m_controlFlags.insert(c.id, c.flags);
                m_controls.append(QVariantMap{{QStringLiteral("id"), c.id}, {QStringLiteral("name"), c.name}, {QStringLiteral("label"), controlLabel(c.id, c.name)}, {QStringLiteral("kind"), QString::fromLatin1(kinds[c.kind])},
                                              {QStringLiteral("min"), c.minimum}, {QStringLiteral("max"), c.maximum}, {QStringLiteral("step"), c.step},
                                              {QStringLiteral("default"), effectiveDefault(c)}, {QStringLiteral("value"), c.value}, {QStringLiteral("inactive"), c.inactive},
                                              {QStringLiteral("readOnly"), c.readOnly}, {QStringLiteral("editable"), c.kind != Control::Other && !c.readOnly && !c.grabbed},
                                              {QStringLiteral("kept"), keep == Keep::Setting}, {QStringLiteral("menu"), menu}, {QStringLiteral("note"), note}});
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
    QString error;
    {
        V4l2Camera dev(info.node.v4l2Path);
        if (!dev.isOpen()) {
            error = V4l2Camera::explain({false, dev.openError(), QStringLiteral("open")}, info.node.description);
        } else {
            const Result r = dev.setMode({fourcc, {width, height}, fps});
            if (!r.ok) {
                error = V4l2Camera::explain(r, info.node.description);
            } else {
                m_touched.insert(m_current);
                m_modeChosen.insert(m_current);
                m_modeDefault.remove(m_current);
                setNeedsSave(true);
            }
        }
    }
    readDetails();
    showError(error);
}

void CameraKcm::showError(const QString &error)
{
    // readDetails() starts from a clean page; a refusal of the step that called it is said after it, so it stays on the page
    if (!error.isEmpty()) {
        m_modeError = error;
        Q_EMIT detailsChanged();
    }
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
    // A governing control changes whether others are in use (automatic white balance and its temperature; the driver may say
    // so with V4L2_CTRL_FLAG_UPDATE, uvcvideo only through the others' INACTIVE flag): the page follows when another control's
    // flags changed. A value that only moved (a slider being dragged) does not rebuild the list under the pointer.
    constexpr quint32 shown = V4L2_CTRL_FLAG_INACTIVE | V4L2_CTRL_FLAG_GRABBED | V4L2_CTRL_FLAG_READ_ONLY | V4L2_CTRL_FLAG_WRITE_ONLY | V4L2_CTRL_FLAG_VOLATILE;
    for (const Control &c : dev.controls()) {
        if (c.id != quint32(controlId) && (c.flags & shown) != (m_controlFlags.value(c.id) & shown)) {
            readDetails();
            break;
        }
    }
    return {};
}

void CameraKcm::resetControls()
{
    const CameraInfo info = currentInfo();
    QString error;
    {
        V4l2Camera dev(info.node.v4l2Path);
        if (dev.isOpen()) {
            QStringList failed;
            const Result r = dev.resetControls(&failed);
            if (!r.ok) {
                error = V4l2Camera::explain(r, info.node.description) + QLatin1Char(' ') + failed.join(QStringLiteral(", "));
            }
            m_touched.insert(m_current);
            setNeedsSave(true);
        }
    }
    readDetails();
    showError(QString(m_pendingError + QLatin1Char(' ') + error).trimmed());
    m_pendingError.clear();
}

void CameraKcm::load()
{
    m_touched.clear();
    m_modeChosen.clear();
    m_modeDefault.clear();
    m_defaultChoice = m_defaultInStore;
    refresh();
    // what the person changed and did not save goes back to what was saved; a camera nobody set goes to its best mode
    m_savedNotes.clear();
    for (const CameraInfo &c : m_infos) {
        const ApplyReport r = applyChoice(c);
        m_savedNotes << r.messages;
        for (const QString &line : r.log) {
            qInfo().noquote() << line;
        }
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
                // only what is a setting, and the mode only when the person chose one here (ORDER 678 and 682)
                choice = choiceFromDevice(dev, choice, m_modeChosen.contains(name));
                if (m_modeDefault.contains(name)) {
                    choice.hasMode = false;
                }
            }
            saveChoice(c.key, choice);
        }
    }
    m_touched.clear();
    m_modeChosen.clear();
    m_modeDefault.clear();
    setNeedsSave(false);
    refresh();
}

void CameraKcm::defaults()
{
    // the camera as it starts when nobody set it: its controls at their defaults and its best mode, the saved mode forgotten on Apply
    const CameraInfo info = currentInfo();
    {
        V4l2Camera dev(info.node.v4l2Path);
        if (dev.isOpen()) {
            const BestModeChoice best = bestModeFor(dev);
            if (best.mode) {
                const Result r = dev.setMode(*best.mode);
                if (!r.ok) {
                    m_pendingError = V4l2Camera::explain(r, info.node.description);
                }
            }
            m_modeDefault.insert(m_current);
            m_modeChosen.remove(m_current);
        }
    }
    resetControls();
}

#include "camerakcm.moc"
