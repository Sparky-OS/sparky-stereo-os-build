// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "cameraservice.h"

#include <KQuickConfigModule>

#include <QSet>
#include <QTimer>
#include <QVariantList>

class CameraKcm : public KQuickConfigModule
{
    Q_OBJECT
    Q_PROPERTY(QVariantList cameras READ cameras NOTIFY camerasChanged)
    Q_PROPERTY(QString engineError READ engineError NOTIFY camerasChanged)
    Q_PROPERTY(QString current READ current WRITE setCurrent NOTIFY currentChanged)
    Q_PROPERTY(QString defaultCamera READ defaultCamera WRITE setDefaultCamera NOTIFY defaultCameraChanged)
    Q_PROPERTY(int currentNodeId READ currentNodeId NOTIFY currentChanged)
    Q_PROPERTY(QString currentNote READ currentNote NOTIFY currentChanged)
    Q_PROPERTY(QStringList machineNotes READ machineNotes CONSTANT)
    Q_PROPERTY(QVariantList formats READ formats NOTIFY detailsChanged)
    Q_PROPERTY(QVariantMap mode READ mode NOTIFY detailsChanged)
    Q_PROPERTY(QVariantList controls READ controls NOTIFY detailsChanged)
    Q_PROPERTY(QVariantList packings READ packings CONSTANT)
    Q_PROPERTY(QString packing READ packing WRITE setPacking NOTIFY detailsChanged)
    Q_PROPERTY(QVariantMap packingInfo READ packingInfo NOTIFY detailsChanged)
    Q_PROPERTY(QStringList savedNotes READ savedNotes NOTIFY detailsChanged)
    Q_PROPERTY(QString modeError READ modeError NOTIFY detailsChanged)

public:
    CameraKcm(QObject *parent, const KPluginMetaData &data);

    QVariantList cameras() const { return m_cameraList; }
    QString engineError() const { return m_engineError; }
    QString current() const { return m_current; }
    void setCurrent(const QString &name);
    QString defaultCamera() const { return m_defaultChoice; }
    void setDefaultCamera(const QString &name);
    int currentNodeId() const;
    QString currentNote() const;
    QStringList machineNotes() const { return m_machineNotes; }
    QVariantList formats() const { return m_formats; }
    QVariantMap mode() const { return m_mode; }
    QVariantList controls() const { return m_controls; }
    QVariantList packings() const { return m_packings; }
    QString packing() const { return m_packing; }
    void setPacking(const QString &id);
    QVariantMap packingInfo() const;
    QStringList savedNotes() const { return m_savedNotes; }
    QString modeError() const { return m_modeError; }

    Q_INVOKABLE QVariantList frameRates(const QString &fourcc, int width, int height);
    Q_INVOKABLE void setMode(const QString &fourcc, int width, int height, double fps);
    // Sets one control on the camera now; the returned text is empty on success, else what to tell the person
    Q_INVOKABLE QString setControl(int controlId, double value);
    Q_INVOKABLE void resetControls();
    Q_INVOKABLE void refresh();

    void load() override;
    void save() override;
    void defaults() override;

Q_SIGNALS:
    void camerasChanged();
    void currentChanged();
    void defaultCameraChanged();
    void detailsChanged();

private:
    void readDetails();
    void showError(const QString &error);
    Sparky::Camera::CameraInfo currentInfo() const;
    void remember(const QString &message);

    QList<Sparky::Camera::CameraInfo> m_infos;
    QVariantList m_cameraList;
    QString m_engineError;
    QString m_current;
    QString m_defaultChoice;
    QString m_defaultInStore; // what WirePlumber holds now
    QStringList m_machineNotes;
    QVariantList m_formats;
    QVariantMap m_mode;
    QVariantList m_controls;
    QVariantList m_packings;
    QString m_packing;
    QString m_modeError;
    QString m_pendingError; // Defaults' refused best mode, said with the reset that follows it
    QStringList m_savedNotes;
    QSet<QString> m_touched; // cameras whose device state the person changed here: saved with Apply
    QSet<QString> m_modeChosen; // cameras whose mode the person chose here: their mode is saved with Apply
    QSet<QString> m_modeDefault; // cameras put back to their best mode by Defaults: their saved mode is forgotten with Apply
    QMap<quint32, quint32> m_controlFlags; // the current camera's controls' flags as shown, to follow a change another control makes
    QTimer m_poll;
};
