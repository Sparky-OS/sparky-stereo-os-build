// SPDX-License-Identifier: GPL-2.0-or-later
// SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
#include <QCoreApplication>
#include <QGuiApplication>
#include <QWindow>
#include <QQmlEngine>
#include <QTimer>
#include <QSaveFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QVideoSink>
#include <QVideoFrame>
#include <QImage>
#include <QQuickItem>
#include <QJsonArray>
static void begin(){
 auto *timer=new QTimer(QCoreApplication::instance());
 QObject::connect(timer,&QTimer::timeout,[]{
  auto folder=qEnvironmentVariable("KAM61_MATRIX_OUT");if(folder.isEmpty())return;
  QQmlEngine *engine=nullptr;for(auto *window:QGuiApplication::allWindows())if((engine=qmlEngine(window)))break;
  if(!engine)return;
  // An integral 640x480 video hole avoids the parent covering a fractional
  // edge of the rounded subsurface viewport in the initial 700x525 window.
  for(auto *window:QGuiApplication::allWindows())if(qmlEngine(window)==engine && (window->width()!=700 || window->height()!=526)) {
    window->resize(700,526);return;
  }
  auto *webcam=engine->singletonInstance<QObject *>(qmlTypeId("org.kde.kamoso",3,0,"WebcamControl"));if(!webcam)return;
  auto *sink=qvariant_cast<QVideoSink *>(webcam->property("stereoSink"));if(!sink||!sink->videoFrame().isValid())return;
  const auto frame=sink->videoFrame();const auto image=frame.toImage().convertToFormat(QImage::Format_RGBA8888);if(image.isNull())return;
  QSaveFile raw(folder+"/delivered.raw");if(!raw.open(QIODevice::WriteOnly))return;raw.write(reinterpret_cast<const char *>(image.constBits()),image.sizeInBytes());raw.commit();
  bool notice=false;QJsonArray noticeRect;
  for(auto *window:QGuiApplication::allWindows())for(auto *item:window->findChildren<QObject *>())
    if(item->property("visible").toBool() && item->property("text").toString().contains(QStringLiteral("This display is in 2D. Showing the left eye."))){notice=true;if(auto *label=qobject_cast<QQuickItem *>(item)){const auto pos=label->mapToScene(QPointF());noticeRect={pos.x(),pos.y(),label->width(),label->height()};}}
  QJsonArray view;
  for(auto *window:QGuiApplication::allWindows())for(auto *item:window->findChildren<QQuickItem *>())
    if(qvariant_cast<QVideoSink *>(item->property("videoSink"))==sink) {
      const auto rect=item->property("contentRect").toRectF();
      const auto point=item->mapToScene(rect.topLeft());
      view={point.x(),point.y(),rect.width(),rect.height()};
    }
  QJsonObject state{{"view",view},{"leftEyeNoticeVisible",notice},{"noticeRect",noticeRect},{"width",image.width()},{"height",image.height()},{"stereoFrame",webcam->property("stereoFrame").toBool()},{"enabled",webcam->property("stereoEnabled").toBool()},{"flatOutput",webcam->property("flatOutput").toBool()},{"message",webcam->property("stereoMessage").toString()}};
  QSaveFile file(folder+"/frame.json");if(file.open(QIODevice::WriteOnly)){file.write(QJsonDocument(state).toJson());file.commit();}
 });timer->start(500);
}
Q_COREAPP_STARTUP_FUNCTION(begin)
