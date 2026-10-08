#include <QGuiApplication>
#include <QElapsedTimer>
#include <QTimer>
#include <QScreen>
#include <QDateTime>
#include <KScreenDpms/Dpms>
#include <iostream>
int main(int argc, char **argv) {
 QGuiApplication app(argc, argv); app.setQuitOnLastWindowClosed(false);
 QElapsedTimer timer; timer.start(); KScreen::Dpms dpms;
 QObject::connect(&dpms, &KScreen::Dpms::modeChanged, &app, [&](KScreen::Dpms::Mode mode,QScreen *screen) {
  std::cout << "DPMS " << timer.elapsed() << ' ' << int(mode) << ' ' << screen->name().toStdString() << ' ' << QDateTime::currentMSecsSinceEpoch() << std::endl;
 });
 QTimer::singleShot(1000,&app,[&] { std::cout << "SUPPORTED " << dpms.isSupported() << std::endl; if(!dpms.isSupported()) app.exit(2); });
 QTimer::singleShot(270000,&app,&QCoreApplication::quit);
 return app.exec();
}
