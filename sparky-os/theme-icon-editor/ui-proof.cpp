// SPDX-License-Identifier: GPL-2.0-or-later
#include "editor.h"
#include <QApplication>
#include <QDoubleSpinBox>
#include <QPushButton>
#include <QKeyEvent>
#include <QMouseEvent>
#include <iostream>

static void require(bool value, const char *message)
{
    if (!value) throw std::runtime_error(message);
}

int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    if (argc != 2) return 2;
    try {
        Editor editor;
        editor.loadProject(QString::fromLocal8Bit(argv[1]));
        require(editor.selectPart("g3010"), "Named part cannot be selected");
        const QImage baseline = editor.preview->left;
        require(baseline != editor.drawing.eye(256, false), "Selected group is not highlighted");
        auto *spin = editor.findChild<QDoubleSpinBox *>("g3010");
        require(spin, "Missing single depth control");
        spin->setValue(-25.0);
        require(editor.drawing.places.value("g3010") == -0.25, "Continuous value lost");
        require(editor.drawing.disparity("g3010", 256) == 0, "Fractional depth did not use KWin rounding");
        require(editor.disparities->item(8, 1)->text().contains("no depth"), "Zero disparity is hidden");
        editor.history->undo();
        require(editor.drawing.places.value("g3010") == -1, "Undo did not restore the value");
        require(editor.preview->left == baseline, "Undo did not restore the rendered selection");
        editor.history->redo();
        require(editor.drawing.places.value("g3010") == -0.25, "Redo did not restore the fractional value");
        QKeyEvent up(QEvent::KeyPress, Qt::Key_Up, Qt::NoModifier);
        QApplication::sendEvent(spin, &up);
        require(editor.drawing.places.value("g3010") == -0.20, "Keyboard does not operate the depth control");
        auto *undo = editor.findChild<QPushButton *>("undo");
        require(undo && undo->isEnabled(), "Undo action unavailable");
        undo->click();
        require(editor.drawing.places.value("g3010") == -0.25, "Undo button did not undo the keyboard step");
        require(!editor.setGroupDepth("g3010", -1.01).isEmpty(), "Author depth escaped desktop limits");
        require(!editor.setGroupDepth("missing", 0.25).isEmpty(), "Unknown group accepted");
        require(editor.drawing.places.value("g3010") == -0.25, "Rejected edit changed the document");
        require(editor.selectPart("g3090"), "Cannot select another part");
        require(editor.preview->left != baseline, "Selection did not change highlighted pixels");
        require(editor.setGroupDepth("g3090", 0.5).isEmpty(), "Fractional popped edit failed");
        require(editor.drawing.disparity("g3090", 256) == 0, "Half popped limit should round to zero at 256");
        std::cout << "PASS: group highlight, continuous bounded depth, per-size zero notice, keyboard edit, undo button, redo and rejected edits\n";
        return 0;
    } catch (const std::exception &e) { std::cerr << e.what() << '\n'; return 1; }
}
