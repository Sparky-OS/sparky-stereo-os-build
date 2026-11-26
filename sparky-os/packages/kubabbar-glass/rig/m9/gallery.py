#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""gallery.py OUT.png [--palette SCHEME.colors] [--qt5] [--window]: every control of Kubabbar Glass 9's list in one window
(push buttons, the default one ringed, bevel and tool buttons, check boxes, radio buttons, pop-up menus and combo boxes,
text fields, spin boxes, sliders, progress bars, tabs, group boxes, list and table headers, disclosure triangles, menus
and the menu bar, a tooltip, scroll bars), drawn by the application style in use and saved with QWidget.grab().
--palette sets the palette from a KDE colour scheme file (for a run without KDE's platform theme); --window keeps the
window open for a compositor capture instead of saving. Builds on PyQt6, or PyQt5 with --qt5."""
import configparser
import sys

QT5 = "--qt5" in sys.argv
if QT5:
    from PyQt5.QtCore import Qt, QTimer
    from PyQt5.QtGui import QColor, QPalette, QStandardItem, QStandardItemModel
    from PyQt5.QtWidgets import (QApplication, QCheckBox, QComboBox, QGridLayout, QGroupBox, QHBoxLayout, QLabel,
                                 QLineEdit, QMenu, QMenuBar, QProgressBar, QPushButton, QRadioButton, QScrollBar,
                                 QSlider, QSpinBox, QTabWidget, QTableWidget, QToolButton, QTreeView, QVBoxLayout, QWidget)
else:
    from PyQt6.QtCore import Qt, QTimer
    from PyQt6.QtGui import QColor, QPalette, QStandardItem, QStandardItemModel
    from PyQt6.QtWidgets import (QApplication, QCheckBox, QComboBox, QGridLayout, QGroupBox, QHBoxLayout, QLabel,
                                 QLineEdit, QMenu, QMenuBar, QProgressBar, QPushButton, QRadioButton, QScrollBar,
                                 QSlider, QSpinBox, QTabWidget, QTableWidget, QToolButton, QTreeView, QVBoxLayout, QWidget)

ROLE = QPalette.ColorRole
GROUP = QPalette.ColorGroup


def palette_from(path):
    cp = configparser.ConfigParser(interpolation=None)
    cp.optionxform = str
    cp.read(path)

    def c(group, key):
        return QColor(*[int(v) for v in cp[f"Colors:{group}"][key].split(",")[:3]])
    pal = QPalette()
    for g in (GROUP.Active, GROUP.Inactive):
        pal.setColor(g, ROLE.Window, c("Window", "BackgroundNormal"))
        pal.setColor(g, ROLE.WindowText, c("Window", "ForegroundNormal"))
        pal.setColor(g, ROLE.Base, c("View", "BackgroundNormal"))
        pal.setColor(g, ROLE.AlternateBase, c("View", "BackgroundAlternate"))
        pal.setColor(g, ROLE.Text, c("View", "ForegroundNormal"))
        pal.setColor(g, ROLE.Button, c("Button", "BackgroundNormal"))
        pal.setColor(g, ROLE.ButtonText, c("Button", "ForegroundNormal"))
        pal.setColor(g, ROLE.Highlight, c("Selection", "BackgroundNormal"))
        pal.setColor(g, ROLE.HighlightedText, c("Selection", "ForegroundNormal"))
        pal.setColor(g, ROLE.ToolTipBase, c("Tooltip", "BackgroundNormal"))
        pal.setColor(g, ROLE.ToolTipText, c("Tooltip", "ForegroundNormal"))
        pal.setColor(g, ROLE.Link, c("View", "ForegroundLink"))
    for role in (ROLE.WindowText, ROLE.Text, ROLE.ButtonText):
        pal.setColor(GROUP.Disabled, role, QColor(150, 150, 150))
    return pal


def build():
    root = QWidget()
    root.setWindowTitle("Kubabbar Glass 9 gallery")
    outer = QVBoxLayout(root)
    bar = QMenuBar()
    for title in ("File", "Edit", "View", "Special"):
        bar.addMenu(title).addAction("Item")
    outer.addWidget(bar)
    grid = QGridLayout()
    outer.addLayout(grid)

    buttons = QGroupBox("Buttons")
    bl = QVBoxLayout(buttons)
    ok = QPushButton("OK")
    ok.setDefault(True)
    bl.addWidget(ok)
    bl.addWidget(QPushButton("Cancel"))
    pressed = QPushButton("Pressed")
    pressed.setDown(True)
    bl.addWidget(pressed)
    dis = QPushButton("Disabled")
    dis.setEnabled(False)
    bl.addWidget(dis)
    row = QHBoxLayout()
    for i, text in enumerate(("Bevel", "Tool", "On")):
        tb = QToolButton()
        tb.setText(text)
        tb.setAutoRaise(False)
        tb.setCheckable(True)
        tb.setChecked(i == 2)
        row.addWidget(tb)
    bl.addLayout(row)
    grid.addWidget(buttons, 0, 0)

    checks = QGroupBox("Choices")
    cl = QVBoxLayout(checks)
    for text, state in (("Checked", Qt.CheckState.Checked), ("Unchecked", Qt.CheckState.Unchecked),
                        ("Mixed", Qt.CheckState.PartiallyChecked)):
        cb = QCheckBox(text)
        cb.setTristate(True)
        cb.setCheckState(state)
        cl.addWidget(cb)
    r1, r2 = QRadioButton("Radio on"), QRadioButton("Radio off")
    r1.setChecked(True)
    cl.addWidget(r1)
    cl.addWidget(r2)
    cd = QCheckBox("Disabled")
    cd.setEnabled(False)
    cl.addWidget(cd)
    grid.addWidget(checks, 0, 1)

    fields = QGroupBox("Fields")
    fl = QVBoxLayout(fields)
    combo = QComboBox()
    combo.addItems(["Pop-up menu", "Second"])
    fl.addWidget(combo)
    editable = QComboBox()
    editable.setEditable(True)
    editable.addItems(["Combo box"])
    fl.addWidget(editable)
    edit = QLineEdit("Text field")
    fl.addWidget(edit)
    spin = QSpinBox()
    spin.setValue(9)
    fl.addWidget(spin)
    grid.addWidget(fields, 0, 2)

    ranges = QGroupBox("Ranges")
    rl = QVBoxLayout(ranges)
    s = QSlider(Qt.Orientation.Horizontal)
    s.setValue(40)
    rl.addWidget(s)
    p = QProgressBar()
    p.setValue(62)
    rl.addWidget(p)
    busy = QProgressBar()
    busy.setRange(0, 0)
    rl.addWidget(busy)
    hs = QScrollBar(Qt.Orientation.Horizontal)
    hs.setRange(0, 100)
    hs.setPageStep(30)
    hs.setValue(20)
    rl.addWidget(hs)
    grid.addWidget(ranges, 1, 0)

    tabs = QTabWidget()
    for t in ("General", "Fonts", "Desktop"):
        page = QLabel(f"{t} page")
        page.setAlignment(Qt.AlignmentFlag.AlignCenter)
        tabs.addTab(page, t)
    grid.addWidget(tabs, 1, 1)

    vs = QScrollBar(Qt.Orientation.Vertical)
    vs.setRange(0, 100)
    vs.setPageStep(25)
    vs.setValue(30)
    vs.setMinimumHeight(150)
    grid.addWidget(vs, 1, 2, alignment=Qt.AlignmentFlag.AlignLeft)

    tree = QTreeView()
    model = QStandardItemModel()
    model.setHorizontalHeaderLabels(["Name", "Size", "Kind"])
    for folder in ("System Folder", "Documents"):
        it = QStandardItem(folder)
        for child in ("Item one", "Item two"):
            it.appendRow([QStandardItem(child), QStandardItem("12 KB"), QStandardItem("document")])
        model.appendRow([it, QStandardItem("--"), QStandardItem("folder")])
    tree.setModel(model)
    tree.expand(model.index(0, 0))
    tree.setCurrentIndex(model.index(0, 0, model.index(0, 0)))
    tree.setMinimumHeight(150)
    grid.addWidget(tree, 2, 0, 1, 2)

    table = QTableWidget(3, 2)
    table.setHorizontalHeaderLabels(["Column", "Value"])
    table.sortItems(0)
    grid.addWidget(table, 2, 2)
    return root, bar


def main():
    out = sys.argv[1]
    app = QApplication(sys.argv[:1])
    if "--palette" in sys.argv:
        app.setPalette(palette_from(sys.argv[sys.argv.index("--palette") + 1]))
    root, bar = build()
    root.resize(860, 560)
    if "--window" in sys.argv:
        root.show()
        sys.exit(app.exec())
    root.show()
    QTimer.singleShot(400, lambda: finish(app, root, out))
    app.exec()


def finish(app, root, out):
    shot = root.grab()
    menu = QMenu()
    menu.addAction("Open")
    menu.addAction("Close")
    menu.addSeparator()
    sub = menu.addMenu("Recent")
    sub.addAction("One")
    menu.setActiveAction(menu.actions()[0])
    menu.adjustSize()
    tip = QLabel("A tooltip, the help tag")
    tip.setWindowFlags(Qt.WindowType.ToolTip)
    tip.setObjectName("qtooltip_label")
    tip.adjustSize()
    from_pix = [shot, menu.grab(), tip.grab()]
    if QT5:
        from PyQt5.QtGui import QPainter, QPixmap
    else:
        from PyQt6.QtGui import QPainter, QPixmap
    w = shot.width() + max(from_pix[1].width(), from_pix[2].width()) + 24
    canvas = QPixmap(w, shot.height())
    canvas.fill(QColor(170, 170, 222))
    painter = QPainter(canvas)
    painter.drawPixmap(0, 0, shot)
    painter.drawPixmap(shot.width() + 12, 40, from_pix[1])
    painter.drawPixmap(shot.width() + 12, 60 + from_pix[1].height(), from_pix[2])
    painter.end()
    canvas.save(out)
    print(out, app.style().objectName(), "Qt", "5" if QT5 else "6")
    app.quit()


if __name__ == "__main__":
    main()
