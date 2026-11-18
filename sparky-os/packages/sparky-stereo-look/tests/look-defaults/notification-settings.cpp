// Created by Daniel Ramos (Capitain Jack) 2026/11/18
// Copyright 2026 under the GNU GPL3 License
#include <QApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QTextStream>

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    QQmlEngine engine;
    QQmlComponent component(&engine);
    component.setData("import QtQml\nimport org.kde.notificationmanager as N\nQtObject { property QtObject settings: N.Settings {} }", QUrl());
    const auto root = component.create();
    if (!root) {
        QTextStream(stderr) << component.errorString();
        return 1;
    }
    const auto settings = root->property("settings").value<QObject *>();
    if (!settings) {
        return 2;
    }
    const QJsonObject state{
        {QStringLiteral("permanentJobPopups"), settings->property("permanentJobPopups").toBool()},
        {QStringLiteral("jobsInNotifications"), settings->property("jobsInNotifications").toBool()},
        {QStringLiteral("popupTimeout"), settings->property("popupTimeout").toInt()},
    };
    QTextStream(stdout) << QJsonDocument(state).toJson();
    delete root;
    return 0;
}
