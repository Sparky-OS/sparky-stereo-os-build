/*
    SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com>
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// The loading screen between the login and the desktop shows the boot splash's picture (sparky-stereo-plymouth, theme
// sparky-stereo-lines), placed and timed as that theme places it, so the screen from power-on to the desktop is one picture.
// On a screen in a 3D mode each part stands at the boot splash's level, inside the person's own limits for that screen, which
// Stereo KWin sends (StereoDepth, org.sparky.stereo): the background on the screen, the swirl with its orbits at half the popped
// limit, the SparkyOS logo at the popped limit, the electrons riding the orbits, popping where a curve rises and sinking where it
// falls (sunk by 0.6 of the sunk limit at most). On a 2D screen it is the same picture, plain. KSplash closes it when the desktop
// is ready (stage 6); it shows no progress of its own, as the boot splash shows none.
import QtQuick
import org.sparky.stereo

Image {
    id: root

    property int stage
    // the electrons' clock, in steps of the boot splash's refresh (50 a second), started again every 2.5 seconds as there
    property real step: 0

    source: "images/background.png"
    fillMode: Image.PreserveAspectCrop

    NumberAnimation on step {
        from: 0
        to: 125
        duration: 2500
        loops: Animation.Infinite
    }

    Image {
        id: swirl
        source: "images/logo.png"
        height: Math.min(root.width, root.height) * 0.7
        width: implicitWidth * height / implicitHeight
        x: root.width / 2 - width / 2 + width * 0.092
        y: 0
        StereoDepth.depth: StereoDepth.Popped / 2
    }

    Image {
        id: wordmark
        source: "images/wordmark.png"
        readonly property real fit: Math.min(1, swirl.width / implicitWidth * 0.7)
        width: implicitWidth * fit
        height: implicitHeight * fit
        x: (root.width - width) / 2
        y: root.height - root.height * 0.092 - height
        StereoDepth.depth: StereoDepth.Popped
    }

    // the orbits of the swirl (centre, radii as fractions of the swirl's picture) and the steps each electron rides one
    readonly property var orbits: [
        { cx: 0.4245, cy: 0.611, rx: 0.295, ry: 0.3303, first: 0, last: 150, start: Math.PI, turn: -1 },
        { cx: 0.3825, cy: 0.411, rx: 0.2248, ry: 0.1645, first: 50, last: 130, start: 0, turn: 1 },
        { cx: 0.7065, cy: 0.460, rx: 0.2945, ry: 0.2343, first: 20, last: 100, start: 0, turn: 1 }
    ]

    Repeater {
        model: 15
        Image {
            id: electron
            readonly property var orbit: root.orbits[Math.floor(index / 5)]
            readonly property int trail: index % 5
            readonly property bool riding: root.step >= orbit.first && root.step < orbit.last
            // the angle along the orbit: faster in the middle of the turn, the trail a little behind the head
            readonly property real angle: orbit.start + (root.step - orbit.first) * 2 * Math.PI / (orbit.last - orbit.first) * orbit.turn
            readonly property real eased: 2 * Math.PI * Math.sin((angle - orbit.start) / 4) + orbit.start
            readonly property real phi: eased - orbit.turn * trail * 0.01
            readonly property real rx: swirl.width * orbit.rx
            readonly property real ry: swirl.height * orbit.ry
            // the depth of this point of the curve, in pixels of a view 1920 wide: popped where the curve rises, sunk where it falls
            readonly property real rise: -orbit.turn * ry * Math.cos(phi) / Math.sqrt(Math.pow(rx * Math.sin(phi), 2) + Math.pow(ry * Math.cos(phi), 2))
            readonly property real popped: swirl.StereoDepth.poppedLimit
            readonly property real sunk: swirl.StereoDepth.sunkLimit
            readonly property real pixels: rise >= 0 ? popped / 2 + popped / 2 * rise : popped / 2 + 0.6 * sunk * rise

            source: "images/electron.png"
            width: implicitWidth * 0.06 * swirl.height / swirl.implicitHeight
            height: width
            visible: riding
            opacity: Math.pow(Math.sin(Math.abs((angle - orbit.start) / 2)), 2) * (1 - 0.2 * trail)
            x: swirl.x + swirl.width * orbit.cx - width / 2 + rx * Math.cos(phi)
            y: swirl.y + swirl.height * orbit.cy - height / 2 + ry * Math.sin(phi)
            StereoDepth.depth: pixels >= 0 ? (popped > 0 ? pixels / popped : 0) : (sunk > 0 ? pixels / sunk : 0)
        }
    }
}
