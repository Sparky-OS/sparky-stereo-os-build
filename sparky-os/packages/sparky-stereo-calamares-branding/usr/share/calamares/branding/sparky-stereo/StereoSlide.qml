/* A slide that is one full side by side stereo picture, left eye first, 16:9, as large as the slideshow area allows.
 * The picture is its own surface, declared to the compositor; everything else in the installer stays 2D. On a screen
 * that shows one eye the item draws the left view, which is the slide's flat picture.
 */

import QtQuick 2.0;
import calamares.slideshow 1.0;
import org.sparky.stereo 1.0

Slide {
    id: slide

    property url pair

    x: 0
    y: 0
    width: parent.width
    height: parent.height

    StereoPicture {
        // An even width and a height of exactly 9/16 of it, so the surface holds each eye at whole pixels
        width: 2 * Math.floor(Math.min(slide.width, slide.height * 16 / 9) / 2)
        height: width * 9 / 16
        anchors.centerIn: parent
        source: slide.pair
    }
}
