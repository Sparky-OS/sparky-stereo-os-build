/* Sparky Stereo OS: the installer's slideshow, six stereo slides (full side by side, left eye first, PNG with the
 * sTER chunk). The branding sets slideshowWindow, so the QML runs in a window the picture can hand to the compositor.
 */

import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation
{
    id: presentation

    Timer {
        interval: 20000
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    function onActivate() { }
    function onLeave() { }

    StereoSlide { pair: "slide1-welcome.pns" }
    StereoSlide { pair: "slide2-movies.pns" }
    StereoSlide { pair: "slide3-science.pns" }
    StereoSlide { pair: "slide4-photos.pns" }
    StereoSlide { pair: "slide5-deep-colour.pns" }
    StereoSlide { pair: "slide6-any-screen.pns" }
}
