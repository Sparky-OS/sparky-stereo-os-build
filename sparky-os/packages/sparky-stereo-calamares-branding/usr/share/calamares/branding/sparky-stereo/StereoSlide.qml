/* A slide: one full side by side stereo picture, left eye first, 16:9, as large as the slideshow area allows, and its
 * words in the reader's language. The picture is its own surface, declared to the compositor; everything else in the
 * installer stays 2D. On a screen that shows one eye the item draws the left view, which is the slide's flat picture.
 *
 * The words are QML text, set at the screen plane over the picture's left column: the same pixels in both eyes, where
 * the picture has no subject (the subjects are in the right two thirds, the pictures carry no text). The block is laid
 * out in the artwork's own 1280 x 720 units and scaled with the picture, so any translation fits the same place.
 */

import QtQuick 2.15;
import calamares.slideshow 1.0;
import org.sparky.stereo 1.0

Slide {
    id: slide

    property url pair
    property string title
    property var lines: []

    x: 0
    y: 0
    width: parent.width
    height: parent.height

    StereoPicture {
        id: picture

        // An even width and a height of exactly 9/16 of it, so the surface holds each eye at whole pixels
        width: 2 * Math.floor(Math.min(slide.width, slide.height * 16 / 9) / 2)
        height: width * 9 / 16
        anchors.centerIn: parent
        source: slide.pair
    }

    Item {
        id: words

        // 1280 x 720 units of the artwork: the column starts at 96 and is 560 wide, centred on 330
        readonly property real unit: picture.width / 1280
        readonly property real fit: Math.min(1, 470 / column.implicitHeight)

        x: picture.x + 96 * unit
        y: picture.y + Math.max(80, 330 - column.implicitHeight * fit / 2) * unit
        width: 560
        height: column.implicitHeight
        scale: unit * fit
        transformOrigin: Item.TopLeft

        Column {
            id: column

            width: 560

            Text {
                width: parent.width
                text: slide.title
                color: "#ffffff"
                font.family: "Trebuchet MS"
                font.pixelSize: 56
                font.bold: true
                wrapMode: Text.WordWrap
                lineHeight: 66
                lineHeightMode: Text.FixedHeight
                bottomPadding: 26
            }

            Repeater {
                model: slide.lines

                Text {
                    width: column.width
                    text: modelData
                    color: "#d9d9d9"
                    font.family: "Verdana"
                    font.pixelSize: 25
                    wrapMode: Text.WordWrap
                    lineHeight: 36
                    lineHeightMode: Text.FixedHeight
                    bottomPadding: index < slide.lines.length - 1 ? 36 : 0
                }
            }
        }
    }
}
