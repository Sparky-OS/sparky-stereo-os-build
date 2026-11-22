// SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
// SPDX-License-Identifier: GPL-3.0-or-later
#include <QGuiApplication>
#include <QQmlEngine>
#include <QQmlComponent>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQuickItem>
#include <QVariantMap>
#include <iostream>
class Page : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantMap status MEMBER status NOTIFY statusChanged)
public:
    QVariantMap status;
    QStringList called;
    Q_INVOKABLE void act(const QStringList &args) { called = args; }
    Q_INVOKABLE void refresh() {}
signals:
    void statusChanged();
};
int main(int argc,char **argv) {
    QGuiApplication app(argc,argv);
    if(argc!=4)return 2;
    QFile file(argv[2]); if(!file.open(QIODevice::ReadOnly))return 3;
    QVariantMap words=QJsonDocument::fromJson(file.readAll()).object().toVariantMap();
    Page page;
    page.status={{"liveCaptions", QVariantMap{{"labels",words},{"on",false},{"login",false},{"microphone",false},{"models",QVariantList{}},{"message",words.value("stopped")}}}};
    QQmlEngine engine;
    QQmlComponent component(&engine,QUrl::fromLocalFile(argv[1]));
    if(component.isError()){for(auto error:component.errors())std::cerr<<error.toString().toStdString()<<"\n";return 4;}
    QObject *root=component.createWithInitialProperties({{"page",QVariant::fromValue(&page)}});
    if(!root){for(auto error:component.errors())std::cerr<<error.toString().toStdString()<<"\n";return 5;}
    app.processEvents();
    auto *button=root->findChild<QObject*>("liveSwitch");
    if(!button||button->property("checked").toBool()||button->property("text").toString()!=words.value("on").toString())return 6;
    button->setProperty("checked",true);
    if(!QMetaObject::invokeMethod(button,"clicked"))return 7;
    if(page.called!=QStringList{"live-captions","on"})return 8;
    std::cout<<argv[3]<<"\toff by default; localized switch; on dispatch\tpass\n";
    delete root;return 0;
}
#include "qml-probe.moc"
