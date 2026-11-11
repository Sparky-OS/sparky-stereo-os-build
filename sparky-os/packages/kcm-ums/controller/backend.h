// SPDX-FileCopyrightText: 2026 Daniel Campos Ramos <Capitain_Jack@yahoo.com>
// SPDX-License-Identifier: GPL-2.0-or-later
#pragma once
#include <QJsonArray>
#include <QJsonObject>
#include <QMap>
#include <QNetworkAccessManager>
#include <QObject>
#include <QSet>
#include <QUrl>

struct UpnpService {
    QString type;
    QUrl control;
    QSet<QString> actions;
};

class Backend : public QObject
{
    Q_OBJECT
public:
    explicit Backend(const QUrl &server, QObject *parent = nullptr);
    void clear();
    QJsonArray renderers();
    void login(const QString &username, const QString &password);
    void select(const QJsonObject &renderer);
    void sendFile(const QUrl &file);
    void transport(const QString &action);
    void seek(qint64 microseconds);
    void setVolume(double volume);
    void setBrightness(int brightness);
    void poll();
    bool supports(const QString &service, const QString &action) const;
    QString name;
    QString uuid;
    QString status = QStringLiteral("Stopped");
    QString title;
    QString track;
    qint64 position = 0;
    qint64 duration = 0;
    double volume = 0;
    bool connected = false;
Q_SIGNALS:
    void changed();
    void seeked(qint64 position);
private:
    QByteArray request(const QUrl &url, const QByteArray &data = {}, const QByteArray &action = {});
    QJsonObject api(const QString &path, const QJsonObject &data = {});
    QJsonArray browse(const QString &id);
    QMap<QString, QString> soap(const QString &service, const QString &action, const QList<QPair<QString, QString>> &arguments);
    QMap<QString, UpnpService> discover(const QString &uuid);
    void require(const QString &service, const QString &action) const;
    QNetworkAccessManager m_network;
    QUrl m_server;
    QByteArray m_token;
    QJsonObject m_renderer;
    QMap<QString, UpnpService> m_services;
};
