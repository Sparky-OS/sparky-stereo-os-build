// SPDX-License-Identifier: GPL-2.0-or-later
// SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QImage>
#include <QPainter>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <stereo-policy.h>
#include <stereo-layer/picture.h>
static void raw(const QString &path,const QImage &image){QFile f(path);Q_ASSERT(f.open(QIODevice::WriteOnly));f.write(reinterpret_cast<const char *>(image.constBits()),image.sizeInBytes());}
int main(int argc,char **argv){
 QCoreApplication app(argc,argv);QDir().mkpath(argv[1]);QJsonArray manifest;
 for(size_t index=0;index<stereo_policy_input_format_count();++index){
  const auto &entry=*stereo_policy_input_format_at(index);
  const int w=160,h=120;
  QImage left(w,h,QImage::Format_RGBA8888),right(w,h,QImage::Format_RGBA8888);
  left.fill(QColor(220,25,25));right.fill(QColor(25,25,220));
  for(auto *eye:{&left,&right}){QPainter p(eye);p.setPen(Qt::black);p.setBrush(Qt::white);p.drawEllipse(QRect(44,24,72,72));p.fillRect(12,12,9,20,Qt::black);}
        QImage first = entry.order ? right : left, second = entry.order ? left : right;
        QImage input;
        const int layout = entry.layout;
        const bool rows = layout == STEREO_POLICY_LAYOUT_ROWS;
        const bool columns = layout == STEREO_POLICY_LAYOUT_COLUMNS;
        const bool checker = layout == STEREO_POLICY_LAYOUT_CHECKERBOARD;
        const bool vertical = layout == STEREO_POLICY_LAYOUT_TOP_AND_BOTTOM || rows;
        if (layout >= STEREO_POLICY_LAYOUT_SIDE_BY_SIDE && layout <= STEREO_POLICY_LAYOUT_SIDE_BY_SIDE_QUINCUNX) {
            input = QImage(vertical ? QSize(w, 2*h) : QSize(2*w, h), left.format());
            for (int y = 0; y < input.height(); ++y) {
                for (int x = 0; x < input.width(); ++x) {
                    const bool odd = rows ? y % 2 : columns ? x % 2 : checker ? (x+y) % 2 : vertical ? y >= h : x >= w;
                    const int sx = columns || checker ? x/2 : x%w;
                    const int sy = rows ? y/2 : y%h;
                    input.setPixelColor(x, y, (odd ? second : first).pixelColor(sx, sy));
                }
            }
        } else if (stereo_policy_is_depth_layout(layout)) {
            // A constant depth map avoids assumptions about the DIBR default; the
            // independent shared depth call below is the conversion authority.
            QImage depth(w, h, left.format()); depth.fill(QColor(128, 128, 128));
            first = entry.order ? depth : left;
            second = entry.order ? left : depth;
            const bool side = layout == STEREO_POLICY_LAYOUT_DEPTH_SIDE_BY_SIDE;
            const bool background = layout == STEREO_POLICY_LAYOUT_DEPTH_BACKGROUND;
            const bool graphics = layout == STEREO_POLICY_LAYOUT_DEPTH_GRAPHICS;
            input = QImage(side || background ? 2*w : w, side ? h : graphics ? 4*h : 2*h, left.format());
            input.fill(Qt::black);
            for (int y = 0; y < h; ++y) for (int x = 0; x < w; ++x) {
                input.setPixelColor(x, y, first.pixelColor(x, y));
                input.setPixelColor(x + (side || background ? w : 0), y + (side || background ? 0 : h), second.pixelColor(x, y));
            }
            const auto expected = Stereo::Picture::fromPackedImage(input, Stereo::Picture::Layout(layout), Stereo::Picture::EyeOrder(entry.order));
            Q_ASSERT(expected.isStereo()); left = expected.left; right = expected.right;
        } else {
            input = first;
            if (entry.anaglyph) {
                const auto expected = Stereo::Picture::fromAnaglyph(input, Stereo::Picture::AnaglyphColorPair(entry.anaglyph));
                Q_ASSERT(expected.isStereo()); left = expected.left; right = expected.right;
            }
        }

  const QString folder=QString::fromLocal8Bit(argv[1])+"/"+QString::fromLatin1(entry.id);QDir().mkpath(folder);
  const bool temporal=layout==STEREO_POLICY_LAYOUT_FRAME_SEQUENTIAL;
  const bool separated=layout==STEREO_POLICY_LAYOUT_BLOCK_LACED;
  if(separated)input=first;
  raw(folder+"/input.raw",input);if(temporal||separated)raw(folder+"/second.raw",second);
  const auto pair=Stereo::Picture::fromViewsInTurn(left,right,Stereo::Picture::EyeOrder::LeftFirst).sideBySide().convertToFormat(QImage::Format_RGBA8888);
  const bool stereo=layout!=STEREO_POLICY_LAYOUT_NONE||entry.anaglyph;
  raw(folder+"/expected.raw",stereo?pair:input);
  QJsonObject row{{"id",QString::fromLatin1(entry.id)},{"width",input.width()},{"height",input.height()},{"eyeWidth",left.width()},{"eyeHeight",left.height()},{"stereo",stereo},{"temporal",temporal},{"separated",separated},{"rightFirst",bool(entry.order)}};
  QFile json(folder+"/spec.json");json.open(QIODevice::WriteOnly);json.write(QJsonDocument(row).toJson());manifest.append(row);
 }
 QFile json(QString::fromLocal8Bit(argv[1])+"/manifest.json");json.open(QIODevice::WriteOnly);json.write(QJsonDocument(manifest).toJson());
}
