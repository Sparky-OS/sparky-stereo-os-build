// SPDX-FileCopyrightText: 2026 Daniel Campos Ramos <Capitain_Jack@yahoo.com>
// SPDX-License-Identifier: GPL-2.0-or-later
#include "backend.h"
#include "umsprofile.h"
#include <KLocalizedString>
#include <QCryptographicHash>
#include <QDir>
#include <QDomDocument>
#include <QEventLoop>
#include <QFileInfo>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QTimer>
#include <QUdpSocket>
#include <QXmlStreamWriter>
#include <cmath>
#include <functional>
#include <stdexcept>

namespace {
[[noreturn]] void fail(const QString &message) { throw std::runtime_error(message.toUtf8().constData()); }
QString tag(const QDomElement &e) { return e.localName().isEmpty() ? e.tagName() : e.localName(); }
QList<QDomElement> xmlChildren(const QDomElement &e, const QString &name) {
    QList<QDomElement> result;
    for (auto c = e.firstChildElement(); !c.isNull(); c = c.nextSiblingElement()) if (tag(c) == name) result << c;
    return result;
}
QString value(const QDomElement &e, const QString &name) { auto list = xmlChildren(e, name); return list.isEmpty() ? QString() : list.first().text(); }
QDomDocument xml(const QByteArray &bytes) {
    QDomDocument doc;
    if (!doc.setContent(bytes, QDomDocument::ParseOption::UseNamespaceProcessing)) fail(i18n("The device returned invalid XML."));
    return doc;
}
qint64 micros(const QString &clock) {
    const auto parts = clock.split(QLatin1Char(':'));
    if (parts.size() != 3) return 0;
    return qRound64((parts[0].toDouble() * 3600 + parts[1].toDouble() * 60 + parts[2].toDouble()) * 1000000);
}
QString clockValue(qint64 us) {
    const qint64 seconds = us / 1000000;
    return QStringLiteral("%1:%2:%3").arg(seconds / 3600).arg(seconds / 60 % 60, 2, 10, QLatin1Char('0')).arg(seconds % 60, 2, 10, QLatin1Char('0'));
}
bool web(const QUrl &url) { return url.isValid() && !url.host().isEmpty() && url.userInfo().isEmpty() && (url.scheme() == QLatin1String("http") || url.scheme() == QLatin1String("https")); }
}

Backend::Backend(const QUrl &server, QObject *parent) : QObject(parent), m_server(server) {
    if (!web(server)) fail(i18n("The media server address is invalid."));
}

QByteArray Backend::request(const QUrl &url, const QByteArray &data, const QByteArray &action) {
    if (!web(url)) fail(i18n("The device address is invalid."));
    QNetworkRequest req(url);
    req.setTransferTimeout(8000);
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::ManualRedirectPolicy);
    req.setRawHeader("User-Agent", "Sparky-UMS-Control/0.2");
    if (action.isEmpty()) {
        req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
        if (url.host() == m_server.host() && url.port() == m_server.port() && !m_token.isEmpty()) req.setRawHeader("Authorization", "Bearer " + m_token);
    } else {
        req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("text/xml; charset=utf-8"));
        req.setRawHeader("SOAPACTION", action);
    }
    auto reply = data.isEmpty() ? m_network.get(req) : m_network.post(req, data);
    QEventLoop loop;
    QTimer deadline;
    deadline.setSingleShot(true);
    connect(&deadline, &QTimer::timeout, reply, &QNetworkReply::abort);
    connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
    connect(reply, &QNetworkReply::readyRead, reply, [reply] { if (reply->bytesAvailable() > 2 * 1024 * 1024) reply->abort(); });
    deadline.start(9000);
    loop.exec(QEventLoop::ExcludeUserInputEvents);
    const auto bytes = reply->readAll();
    const int code = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    const auto error = reply->error();
    reply->deleteLater();
    if (code == 401 || code == 403) fail(i18n("UMS requires permission. Sign in and try again."));
    if (error != QNetworkReply::NoError || code < 200 || code >= 300 || bytes.size() > 2 * 1024 * 1024)
        fail(i18n("The device request failed (HTTP %1). Check that the server and device are available.", code));
    return bytes;
}

QJsonObject Backend::api(const QString &path, const QJsonObject &data) {
    const auto bytes = request(m_server.resolved(QUrl(QStringLiteral("/v1/api/") + path)), data.isEmpty() ? QByteArray() : QJsonDocument(data).toJson(QJsonDocument::Compact));
    const auto doc = QJsonDocument::fromJson(bytes);
    if (!doc.isObject()) fail(i18n("UMS returned an invalid response."));
    return doc.object();
}
void Backend::login(const QString &username, const QString &password) {
    const auto result = api(QStringLiteral("auth/login"), {{QStringLiteral("username"), username}, {QStringLiteral("password"), password}});
    m_token = result.value(QStringLiteral("token")).toString().toUtf8();
    if (m_token.isEmpty()) fail(i18n("UMS did not accept the sign-in."));
}
QJsonArray Backend::renderers() {
    const auto result = api(QStringLiteral("renderers/"));
    if (!result.value(QStringLiteral("renderers")).isArray()) fail(i18n("UMS returned an invalid response."));
    return result.value(QStringLiteral("renderers")).toArray();
}

QMap<QString, UpnpService> Backend::discover(const QString &wanted) {
    QUdpSocket socket;
    if (!socket.bind(QHostAddress::AnyIPv4, 0)) fail(i18n("Device discovery could not start."));
    QSet<QUrl> locations;
    const QByteArray search = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 1\r\nST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n\r\n";
    socket.writeDatagram(search, QHostAddress(QStringLiteral("239.255.255.250")), 1900);
    QEventLoop loop;
    connect(&socket, &QUdpSocket::readyRead, &loop, [&] {
        while (socket.hasPendingDatagrams()) {
            QByteArray data;
            data.resize(qMin<qint64>(socket.pendingDatagramSize(), 65536));
            socket.readDatagram(data.data(), data.size());
            if (!data.toLower().contains(wanted.toUtf8().toLower())) continue;
            for (auto line : data.split('\n')) if (line.toLower().startsWith("location:")) {
                const QUrl url(QString::fromUtf8(line.mid(9).trimmed()));
                if (web(url)) locations.insert(url);
            }
        }
    });
    QTimer::singleShot(1800, &loop, &QEventLoop::quit);
    loop.exec(QEventLoop::ExcludeUserInputEvents);
    for (const auto &location : locations) {
        auto doc = xml(request(location));
        std::function<QDomElement(QDomElement)> find = [&](QDomElement e) -> QDomElement {
            if (tag(e) == QLatin1String("device") && value(e, QStringLiteral("UDN")).remove(QStringLiteral("uuid:")).compare(wanted, Qt::CaseInsensitive) == 0) return e;
            for (auto c = e.firstChildElement(); !c.isNull(); c = c.nextSiblingElement()) { auto result = find(c); if (!result.isNull()) return result; }
            return {};
        };
        const auto device = find(doc.documentElement());
        if (device.isNull()) continue;
        const auto baseText = value(doc.documentElement(), QStringLiteral("URLBase"));
        const QUrl base = baseText.isEmpty() ? location : QUrl(baseText);
        QMap<QString, UpnpService> services;
        for (const auto &list : xmlChildren(device, QStringLiteral("serviceList"))) for (const auto &s : xmlChildren(list, QStringLiteral("service"))) {
            const auto type = value(s, QStringLiteral("serviceType"));
            const auto parts = type.split(QLatin1Char(':'));
            if (parts.size() != 5) continue;
            const auto key = parts[3];
            if (key != QLatin1String("AVTransport") && key != QLatin1String("RenderingControl")) continue;
            UpnpService service{type, base.resolved(QUrl(value(s, QStringLiteral("controlURL")))), {}};
            auto scpd = xml(request(base.resolved(QUrl(value(s, QStringLiteral("SCPDURL"))))));
            const auto actionLists = xmlChildren(scpd.documentElement(), QStringLiteral("actionList"));
            for (const auto &actions : actionLists) for (const auto &a : xmlChildren(actions, QStringLiteral("action"))) service.actions.insert(value(a, QStringLiteral("name")));
            services.insert(key, service);
        }
        return services;
    }
    fail(i18n("The selected device did not answer discovery. Refresh the list and try again."));
}

void Backend::clear() {
    connected = false;
    m_renderer = {};
    m_services.clear();
    track.clear();
    title.clear();
    name.clear();
    uuid.clear();
    position = duration = 0;
    Q_EMIT changed();
}
void Backend::select(const QJsonObject &renderer) {
    clear();
    uuid = renderer.value(QStringLiteral("uuid")).toString();
    uuid.remove(QStringLiteral("uuid:"));
    if (uuid.isEmpty() || !renderer.value(QStringLiteral("isAllowed")).toBool() || !renderer.value(QStringLiteral("isActive")).toBool())
        fail(i18n("This device is unavailable or blocked in UMS."));
    name = renderer.value(QStringLiteral("name")).toString();
    m_services = discover(uuid);
    require(QStringLiteral("AVTransport"), QStringLiteral("GetTransportInfo"));
    m_renderer = renderer;
    poll();
}

bool Backend::supports(const QString &service, const QString &action) const { return m_services.value(service).actions.contains(action); }
void Backend::require(const QString &service, const QString &action) const {
    if (!supports(service, action)) fail(i18n("This device does not support %1.", action));
}
QMap<QString, QString> Backend::soap(const QString &serviceName, const QString &action, const QList<QPair<QString, QString>> &arguments) {
    require(serviceName, action);
    const auto service = m_services.value(serviceName);
    QByteArray bytes;
    QXmlStreamWriter writer(&bytes);
    writer.writeStartDocument();
    writer.writeStartElement(QStringLiteral("s:Envelope"));
    writer.writeNamespace(QStringLiteral("http://schemas.xmlsoap.org/soap/envelope/"), QStringLiteral("s"));
    writer.writeAttribute(QStringLiteral("s:encodingStyle"), QStringLiteral("http://schemas.xmlsoap.org/soap/encoding/"));
    writer.writeStartElement(QStringLiteral("s:Body"));
    writer.writeStartElement(QStringLiteral("u:") + action);
    writer.writeNamespace(service.type, QStringLiteral("u"));
    writer.writeTextElement(QStringLiteral("InstanceID"), QStringLiteral("0"));
    for (const auto &argument : arguments) writer.writeTextElement(argument.first, argument.second);
    writer.writeEndDocument();
    const auto response = xml(request(service.control, bytes, (QLatin1Char('"') + service.type + QLatin1Char('#') + action + QLatin1Char('"')).toUtf8()));
    QMap<QString, QString> result;
    std::function<void(QDomElement)> visit = [&](QDomElement e) {
        if (tag(e) == QLatin1String("Fault")) fail(i18n("The device refused %1: %2", action, e.text()));
        if (e.firstChildElement().isNull()) result.insert(tag(e), e.text());
        for (auto c = e.firstChildElement(); !c.isNull(); c = c.nextSiblingElement()) visit(c);
    };
    visit(response.documentElement());
    return result;
}

QJsonArray Backend::browse(const QString &id) {
    return api(QStringLiteral("renderers/browse"), {{QStringLiteral("id"), m_renderer.value(QStringLiteral("id"))}, {QStringLiteral("media"), id}}).value(QStringLiteral("childrens")).toArray();
}
void Backend::sendFile(const QUrl &url) {
    const QFileInfo file(url.toLocalFile());
    const auto path = file.canonicalFilePath();
    if (!url.isLocalFile() || path.isEmpty() || !file.isFile()) fail(i18n("Choose one local media file."));
    QString root;
    for (const auto &folder : UmsProfile(UmsProfile::defaultDirectory()).folders()) {
        const auto canonical = QFileInfo(folder).canonicalFilePath();
        if (!canonical.isEmpty() && path.startsWith(canonical + QLatin1Char('/')) && canonical.size() > root.size()) root = canonical;
    }
    if (root.isEmpty()) fail(i18n("This file is not in a shared folder. Add its folder in Media Server settings and try again."));
    QStringList parts{QFileInfo(root).fileName()};
    parts.append(QDir(root).relativeFilePath(path).split(QLatin1Char('/')));
    QString id = QStringLiteral("0");
    for (qsizetype index = 0; index < parts.size(); ++index) {
        const auto entries = browse(id);
        QList<QJsonObject> matches;
        for (const auto &entry : entries) {
            const auto item = entry.toObject();
            const auto label = item.value(QStringLiteral("label")).toString();
            const bool folder = index < parts.size() - 1;
            if (item.value(QStringLiteral("browsable")).toBool() != folder) continue;
            if (label == parts[index] || (!folder && label == QFileInfo(parts[index]).completeBaseName())) matches << item;
        }
        if (matches.size() != 1) fail(i18n("UMS cannot uniquely find this file for the selected device. Check its shared folders and media names."));
        id = matches.first().value(QStringLiteral("value")).toString();
        if (id.isEmpty()) fail(i18n("UMS returned an invalid response."));
    }
    api(QStringLiteral("renderers/control"), {{QStringLiteral("id"), m_renderer.value(QStringLiteral("id"))}, {QStringLiteral("action"), QStringLiteral("mediaid")}, {QStringLiteral("value"), id}});
    transport(QStringLiteral("Play"));
    title = file.fileName();
    track = QStringLiteral("/org/mpris/MediaPlayer2/track_") + QString::fromLatin1(QCryptographicHash::hash(path.toUtf8(), QCryptographicHash::Sha256).toHex());
    poll();
}
void Backend::transport(const QString &action) {
    soap(QStringLiteral("AVTransport"), action, action == QLatin1String("Play") ? QList<QPair<QString, QString>>{{QStringLiteral("Speed"), QStringLiteral("1")}} : QList<QPair<QString, QString>>{});
    poll();
}
void Backend::seek(qint64 target) {
    if (target < 0 || (duration > 0 && target > duration)) return;
    soap(QStringLiteral("AVTransport"), QStringLiteral("Seek"), {{QStringLiteral("Unit"), QStringLiteral("REL_TIME")}, {QStringLiteral("Target"), clockValue(target)}});
    poll();
    Q_EMIT seeked(position);
}
void Backend::setVolume(double value) {
    if (!std::isfinite(value) || value < 0 || value > 1) fail(i18n("Volume must be between 0 and 100 percent."));
    soap(QStringLiteral("RenderingControl"), QStringLiteral("SetVolume"), {{QStringLiteral("Channel"), QStringLiteral("Master")}, {QStringLiteral("DesiredVolume"), QString::number(qRound(value * 100))}});
    poll();
}
void Backend::setBrightness(int value) {
    soap(QStringLiteral("RenderingControl"), QStringLiteral("SetBrightness"), {{QStringLiteral("DesiredBrightness"), QString::number(qBound(0, value, 100))}});
}
void Backend::poll() {
    try {
        const auto state = soap(QStringLiteral("AVTransport"), QStringLiteral("GetTransportInfo"), {}).value(QStringLiteral("CurrentTransportState"));
        status = state == QLatin1String("PLAYING") ? QStringLiteral("Playing") : state == QLatin1String("PAUSED_PLAYBACK") ? QStringLiteral("Paused") : QStringLiteral("Stopped");
        if (supports(QStringLiteral("AVTransport"), QStringLiteral("GetPositionInfo"))) {
            const auto info = soap(QStringLiteral("AVTransport"), QStringLiteral("GetPositionInfo"), {});
            position = micros(info.value(QStringLiteral("RelTime")));
            duration = micros(info.value(QStringLiteral("TrackDuration")));
            const auto uri = info.value(QStringLiteral("TrackURI"));
            if (!uri.isEmpty()) {
                track = QStringLiteral("/org/mpris/MediaPlayer2/track_") + QString::fromLatin1(QCryptographicHash::hash(uri.toUtf8(), QCryptographicHash::Sha256).toHex());
                if (title.isEmpty()) title = QUrl(uri).fileName();
            }
        }
        if (supports(QStringLiteral("RenderingControl"), QStringLiteral("GetVolume")))
            volume = soap(QStringLiteral("RenderingControl"), QStringLiteral("GetVolume"), {{QStringLiteral("Channel"), QStringLiteral("Master")}}).value(QStringLiteral("CurrentVolume")).toDouble() / 100;
        connected = true;
        Q_EMIT changed();
    } catch (...) { connected = false; Q_EMIT changed(); throw; }
}
