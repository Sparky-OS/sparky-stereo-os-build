#!/usr/bin/env python3
"""Render the menu bar and dock variant's splash headless (software Qt Quick, offscreen) at stages 0, 1, 3 and 6."""
import os
import sys
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")

from PySide6.QtCore import QTimer, QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuick import QQuickView

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "evidence/m3"
LNF = ROOT / "share/plasma/look-and-feel/kubabbar-glass-menubar/contents/splash/Splash.qml"
app = QGuiApplication(sys.argv)
for stage in (0, 1, 3, 6):
    view = QQuickView()
    view.resize(1280, 800)
    view.setResizeMode(QQuickView.SizeRootObjectToView)
    view.setSource(QUrl.fromLocalFile(str(LNF)))
    if view.status() != QQuickView.Ready:
        sys.exit("splash did not load: %s" % view.errors())
    view.rootObject().setProperty("stage", stage)
    view.show()
    path = OUT / ("splash-stage-%d.png" % stage)
    QTimer.singleShot(1800, lambda p=path, v=view: (v.grabWindow().save(str(p)), print("saved", p), app.quit()))
    app.exec()
    view.close()
