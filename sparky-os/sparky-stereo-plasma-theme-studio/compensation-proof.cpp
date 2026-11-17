// SPDX-License-Identifier: GPL-2.0-or-later
#include "drawing.h"
#include "depth-interface.h"
#include <QApplication>
#include <QDir>
#include <QTemporaryDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <iostream>
static void require(bool ok,const char *why){if(!ok)throw std::runtime_error(why);}
int main(int argc,char**argv){
 QApplication app(argc,argv);if(argc!=3)return 2;
 try {
 Drawing d;d.open(QString::fromLocal8Bit(argv[1]));QDir().mkpath(argv[2]);QJsonArray rows;
 require(Depth::authoredDisparity(-1,{10,4},1920)==-10 && Depth::authoredDisparity(1,{10,4},1920)==4,"Reference output budget changed");
 require(Depth::authoredDisparity(-1,{10,4},960)==-5 && Depth::authoredDisparity(1,{10,4},960)==2,"Limits do not follow the output width");
 require(Depth::authoredDisparity(-.001,{10,4},1920)==-1 && Depth::authoredDisparity(.001,{10,4},1920)==1,"Subpixel authored value lost its sign/minimum");
 require(Depth::authoredDisparity(-1,{0,0},1920)==0 && Depth::authoredDisparity(1,{0,0},1920)==0,"Zero desktop limits ignored");
 for(int n:{8,16,22,24,32,48,64,128,256})for(auto id:{QString("studio-part-rect3370"),QString("g3398")}){
  const int sign=id=="studio-part-rect3370"?-1:1;d.setPlace(id,sign*.1);
  const int measured=d.disparity(id,n);require(measured==sign,"Nonzero depth disappeared although this part has room");
  savePns(QString::fromLocal8Bit(argv[2])+QString("/%1-%2.pns").arg(id).arg(n),d.eye(n,false,id),d.eye(n,true,id));
  rows.append(QJsonObject{{"size",n},{"id",id},{"desktopBound",sign<0?10:4},{"expected",sign}});d.setPlace(id,0);
 }
 d.setPlace("studio-part-rect3370",-.1);d.setPlace("g3398",-.11);
 require(d.disparity("g3398",8)<=d.disparity("studio-part-rect3370",8),"Rounding inverted two depths");
 require(d.collapsedWith("g3398",8).contains(d.groupLabel("studio-part-rect3370")),"Collapsed depths are not reported");
 d.setPlace("studio-part-rect3370",-1);d.setPlace("g3398",-.3);
 bool rejected=false;try{d.eye(8,false);}catch(const std::exception&){rejected=true;}
 require(rejected,"Physical room inverted two parts without refusing the pair");
 for(auto id:d.groups())d.setPlace(id,0);
 d.setPlace("studio-part-rect3370",-.1);
 QTemporaryDir config;const auto savedConfig=qgetenv("XDG_CONFIG_HOME");qputenv("XDG_CONFIG_HOME",config.path().toUtf8());
 QFile file(config.path()+"/kwinrc");require(file.open(QIODevice::WriteOnly),"Cannot create private limits");file.write("[StereoDepth]\nSunkLimit=0\nPoppedLimit=0\n");file.close();
 d.readLimits(1920);require(d.disparity("studio-part-rect3370",16)==0 && d.depthNotice("studio-part-rect3370",16).contains("zero"),"Zero-limit exception not reported");
 require(d.forExport().disparity("studio-part-rect3370",16)==-1,"Export inherited private zero limits");qputenv("XDG_CONFIG_HOME",savedConfig);
 saveBytes(QString::fromLocal8Bit(argv[2])+"/predictions.json",QJsonDocument(rows).toJson());
 std::cout<<"GREEN: all nine sizes visibly sunk/popped within default output bounds; output scaling, zero limits, ties and order refusal verified\n";return 0;
 }catch(const std::exception&e){std::cerr<<e.what()<<'\n';return 1;}
}
