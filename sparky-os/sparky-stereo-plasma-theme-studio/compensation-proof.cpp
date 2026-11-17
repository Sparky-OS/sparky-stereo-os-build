// SPDX-License-Identifier: GPL-2.0-or-later
#include "drawing.h"
#include "depth-interface.h"
#include <QApplication>
#include <QDir>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <iostream>
int main(int argc,char**argv){
 QApplication app(argc,argv);if(argc!=3)return 2;
 Drawing d;d.open(QString::fromLocal8Bit(argv[1]));QDir().mkpath(argv[2]);QJsonArray rows;
 for(int n:{8,16,22,24,32,48,64,128,256})for(auto id:{QString("g3010"),QString("g3090")}){
  int sign=id=="g3010"?-1:1;d.setPlace(id,sign);int cap=std::abs(Depth::parallax(sign<0?d.sunk():d.popped(),n));
  d.setPlace(id,sign*.1);int measured=d.disparity(id,n);int want=cap?sign:0;
  if(measured!=want){std::cerr<<"RED: "<<id.toStdString()<<" at "<<n<<" expected "<<want<<" got "<<measured<<'\n';return 1;}
  savePns(QString::fromLocal8Bit(argv[2])+QString("/%1-%2.pns").arg(id).arg(n),d.eye(n,false,id),d.eye(n,true,id));
  rows.append(QJsonObject{{"size",n},{"id",id},{"cap",cap},{"expected",want}});
  d.setPlace(id,0);
 }
 saveBytes(QString::fromLocal8Bit(argv[2])+"/predictions.json",QJsonDocument(rows).toJson());
 std::cout<<"GREEN: bounded minimum pixel at all nine sizes; pairs exported\n";
}
