// SPDX-FileCopyrightText: 2026 Daniel Campos Ramos
// SPDX-License-Identifier: GPL-3.0-or-later
#include <QCoreApplication>
#include <QDir>
#include <QStorageInfo>
#include <iostream>
int main(int argc,char **argv) {
    QCoreApplication app(argc,argv);
    if(argc!=2) return 2;
    const QString path=QString::fromLocal8Bit(argv[1]);
    if(QDir(path).exists())return 3;
    const QStorageInfo missing(path),parent(QFileInfo(path).absolutePath());
    std::cout << "missing_valid=" << missing.isValid() << " missing_bytes=" << missing.bytesAvailable()
              << " parent_valid=" << parent.isValid() << " parent_bytes=" << parent.bytesAvailable() << '\n';
    if(!QDir().mkpath(path))return 4;
    const QStorageInfo created(path);
    std::cout << "created_valid=" << created.isValid() << " created_bytes=" << created.bytesAvailable() << '\n';
    return !missing.isValid() && parent.isValid() && parent.bytesAvailable()>0 && created.isValid() && created.bytesAvailable()>0 ? 0:1;
}
