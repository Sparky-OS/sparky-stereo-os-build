#!/usr/bin/env python3
"""Render the splash and the SDDM theme headless (software Qt Quick, offscreen) with stand-in SDDM objects."""
import os
import sys
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")

from PySide6.QtCore import Signal, Property, QAbstractListModel, QModelIndex, QObject, Qt, QTimer, QUrl, Slot
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuick import QQuickView

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "evidence/m2"
LNF = ROOT / "share/plasma/look-and-feel/kubabbar-glass/contents/splash/Splash.qml"
SDDM = ROOT / "share/sddm/themes/kubabbar-glass/Main.qml"


class Sddm(QObject):
    loginFailed = Signal()

    @Slot(str, str, int)
    def login(self, user, password, session):
        print("login", user, bool(password), session)

    @Slot()
    def powerOff(self):
        pass

    @Slot()
    def reboot(self):
        pass


class Users(QObject):
    @Property(str, constant=True)
    def lastUser(self):
        return "user"


class Sessions(QAbstractListModel):
    def rowCount(self, parent=QModelIndex()):
        return 2

    def data(self, index, role):
        return ["Plasma (Wayland)", "Plasma (X11)"][index.row()] if role == Qt.UserRole + 1 else None

    def roleNames(self):
        return {Qt.UserRole + 1: b"name"}

    @Property(int, constant=True)
    def lastIndex(self):
        return 0


class Text(QObject):
    @Property(str, constant=True)
    def userName(self):
        return "User name"

    @Property(str, constant=True)
    def password(self):
        return "Password"

    @Property(str, constant=True)
    def login(self):
        return "Login"

    @Property(str, constant=True)
    def shutdown(self):
        return "Shut down"

    @Property(str, constant=True)
    def reboot(self):
        return "Restart"

    @Property(str, constant=True)
    def loginFailed(self):
        return "Login failed"


def grab(view, path, delay=1500):
    def save():
        image = view.grabWindow()
        image.save(str(path))
        print("saved", path, image.width(), image.height())
        app.quit()
    QTimer.singleShot(delay, save)
    app.exec()


app = QGuiApplication(sys.argv)
keep = []
for stage in (0, 1, 3, 6):
    view = QQuickView()
    view.resize(1280, 800)
    view.setResizeMode(QQuickView.SizeRootObjectToView)
    view.setSource(QUrl.fromLocalFile(str(LNF)))
    if view.status() != QQuickView.Ready:
        sys.exit("splash did not load: %s" % view.errors())
    view.rootObject().setProperty("stage", stage)
    view.show()
    grab(view, OUT / ("splash-stage-%d.png" % stage), 1800)
    view.close()
sddm, users, sessions, text = Sddm(), Users(), Sessions(), Text()
view = QQuickView()
view.resize(1280, 800)
view.setResizeMode(QQuickView.SizeRootObjectToView)
for name, value in (("sddm", sddm), ("userModel", users), ("sessionModel", sessions), ("textConstants", text)):
    view.rootContext().setContextProperty(name, value)
view.setSource(QUrl.fromLocalFile(str(SDDM)))
if view.status() != QQuickView.Ready:
    sys.exit("sddm theme did not load: %s" % view.errors())
view.show()
grab(view, OUT / "sddm-login.png", 1500)
