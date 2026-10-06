#!/bin/bash
# usage: build-aid3.sh <include-root> <out.so>
cd /o/tests && g++ -shared -fPIC -O1 -std=c++17 -o $2 avogadro-aid3.cpp -I$1 -I$1/avogadro -I/usr/include/eigen3 -I/usr/include/x86_64-linux-gnu/qt6 -I/usr/include/x86_64-linux-gnu/qt6/QtCore -I/usr/include/x86_64-linux-gnu/qt6/QtGui -I/usr/include/x86_64-linux-gnu/qt6/QtWidgets -I/usr/include/x86_64-linux-gnu/qt6/QtOpenGLWidgets -I/usr/include/x86_64-linux-gnu/qt6/QtOpenGL -ldl -lQt6Core -lQt6Gui -lQt6Widgets -lQt6OpenGLWidgets -lAvogadroQtOpenGL -lAvogadroQtGui -lAvogadroRendering 2>&1 | head
