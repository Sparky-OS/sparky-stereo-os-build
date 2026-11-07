#!/bin/sh
cd /rig && g++ -fPIC -O2 -o qt_stereo qt_stereo.cpp $(pkg-config --cflags --libs Qt6Widgets Qt6OpenGLWidgets Qt6OpenGL) && echo built-qt
