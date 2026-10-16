/* Sparky Stereo OS: the installer's slideshow, twenty-three stereo slides (full side by side, left eye first, PNG with the
 * sTER chunk). The branding sets slideshowWindow, so the QML runs in a window the picture can hand to the compositor.
 * The words are qsTr strings, translated through the branding's lang/calamares-sparky_<locale>.qm; English is the source.
 * Written by tools/make-slideshow.py from the approved texts (slides.json of the SparkyOS artwork): change the texts there.
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

    StereoSlide {
        pair: "slide01-welcome.pns"
        title: qsTr("Welcome to Sparky Stereo OS")
        lines: [
            qsTr("Your desktop in 3D, on the screen you already have."),
            qsTr("The installation carries on by itself and takes a few minutes.")
        ]
    }

    StereoSlide {
        pair: "slide02-desktop.pns"
        title: qsTr("A desktop made for both eyes")
        lines: [
            qsTr("Windows, panels and icons stand at their own distances, in front of the screen or behind it."),
            qsTr("Not only films and games: the whole desktop is in 3D, as we created it.")
        ]
    }

    StereoSlide {
        pair: "slide03-movies.pns"
        title: qsTr("3D films")
        lines: [
            qsTr("3D films play at full sharpness in each eye."),
            qsTr("Haruna, VLC Stereo, Dragon Player and Bino recognise a 3D film by themselves.")
        ]
    }

    StereoSlide {
        pair: "slide04-vr-films.pns"
        title: qsTr("VR films")
        lines: [
            qsTr("360° and 180° films, flat or in 3D, on any 3D screen."),
            qsTr("Turn the view with the mouse, no headset needed.")
        ]
    }

    StereoSlide {
        pair: "slide05-science.pns"
        title: qsTr("Science in 3D")
        lines: [
            qsTr("Globes, molecules and graphs that stand out of the screen."),
            qsTr("Marble, Kalzium, Avogadro, KAlgebra and GNU Octave are ready to use.")
        ]
    }

    StereoSlide {
        pair: "slide06-photos.pns"
        title: qsTr("Photos in 3D")
        lines: [
            qsTr("3D photos from cameras and phones open as they were taken."),
            qsTr("Screenshots of the 3D desktop are saved in 3D too.")
        ]
    }

    StereoSlide {
        pair: "slide07-paint-and-edit.pns"
        title: qsTr("Paint and edit in 3D")
        lines: [
            qsTr("Paint in Krita on a 3D canvas, with 16 bits per colour."),
            qsTr("Edit 3D photos in digiKam and KolourPaint, and 3D video in Kdenlive.")
        ]
    }

    StereoSlide {
        pair: "slide08-create-3d.pns"
        title: qsTr("Create 3D")
        lines: [
            qsTr("Right-click a photo or a video and choose Create Stereo."),
            qsTr("Make 3D pictures for any screen, and red-cyan versions to share with anyone.")
        ]
    }

    StereoSlide {
        pair: "slide09-web.pns"
        title: qsTr("The 3D web")
        lines: [
            qsTr("Waterfox shows 3D videos and WebXR scenes from web pages on your 3D screen."),
            qsTr("StorySplat tours of real places open in 3D, right in the browser.")
        ]
    }

    StereoSlide {
        pair: "slide10-deep-colour.pns"
        title: qsTr("Deep colour")
        lines: [
            qsTr("More colours than an ordinary screen shows, up to 16 bits per channel."),
            qsTr("Smooth skies and gradients, without steps.")
        ]
    }

    StereoSlide {
        pair: "slide11-any-screen.pns"
        title: qsTr("Any 3D screen")
        lines: [
            qsTr("3D TVs, glasses-free monitors, VR headsets, and red-cyan glasses on any monitor."),
            qsTr("Choose your screen's 3D mode in Display Configuration, and every program follows.")
        ]
    }

    StereoSlide {
        pair: "slide12-phone.pns"
        title: qsTr("Your phone as a 3D screen")
        lines: [
            qsTr("Put an Android phone in a cardboard viewer and see the desktop in 3D."),
            qsTr("Older phones work too, because the computer does the drawing.")
        ]
    }

    StereoSlide {
        pair: "slide13-throw-and-catch.pns"
        title: qsTr("Throw and Catch")
        lines: [
            qsTr("Throw a window, a film or the whole desktop to a TV, a phone or another computer, sound included."),
            qsTr("The other side catches it with one click.")
        ]
    }

    StereoSlide {
        pair: "slide14-sound.pns"
        title: qsTr("Sound, your way")
        lines: [
            qsTr("Send each program's sound to the speakers, headphones or TV you choose."),
            qsTr("Music and films keep their full quality, from the file to the speakers.")
        ]
    }

    StereoSlide {
        pair: "slide15-controllers.pns"
        title: qsTr("Every controller, every button")
        lines: [
            qsTr("Gamepads, wheels, pedals and flight sticks work as they come, with force feedback where the device has it."),
            qsTr("KDE's Game Controller page shows every button, axis and hat, even on big flight and racing rigs.")
        ]
    }

    StereoSlide {
        pair: "slide16-hardware.pns"
        title: qsTr("Ready for your hardware")
        lines: [
            qsTr("Printers, scanners, cameras, Arduino boards and virtual machines work for every new user."),
            qsTr("No permissions to fix by hand.")
        ]
    }

    StereoSlide {
        pair: "slide17-games.pns"
        title: qsTr("Games in 3D")
        lines: [
            qsTr("Half-Life 2 and DOOM (2016) in 3D through their VR modes."),
            qsTr("Lutris games in 3D with one switch.")
        ]
    }

    StereoSlide {
        pair: "slide18-screensavers.pns"
        title: qsTr("Screensavers in real 3D")
        lines: [
            qsTr("Over a hundred classic screensavers, each drawn for both eyes."),
            qsTr("Pure mathematics comes alive in 3D while you are away.")
        ]
    }

    StereoSlide {
        pair: "slide19-variety.pns"
        title: qsTr("3D wallpapers from the world")
        lines: [
            qsTr("Variety brings 3D photos from stereo photographers around the world to your desktop, with their names."),
            qsTr("On a 3D screen the wallpaper comes alive in 3D; on any other screen it looks as usual.")
        ]
    }

    StereoSlide {
        pair: "slide20-video-wallpaper.pns"
        title: qsTr("3D video wallpaper")
        lines: [
            qsTr("A film or a scene in 3D as your desktop background."),
            qsTr("It pauses by itself while a game or a full-screen program is running.")
        ]
    }

    StereoSlide {
        pair: "slide21-boot-and-lock.pns"
        title: qsTr("3D from the first second")
        lines: [
            qsTr("The boot screen and the lock screen are in 3D too."),
            qsTr("The system greets you in 3D before you even log in.")
        ]
    }

    StereoSlide {
        pair: "slide22-classic-look.pns"
        title: qsTr("A classic look, made new")
        lines: [
            qsTr("Kubabbar Glass brings back a classic silver look, with today's KDE underneath."),
            qsTr("Choose it, or keep the Sparky look, at any time.")
        ]
    }

    StereoSlide {
        pair: "slide23-certificates.pns"
        title: qsTr("Brazil's digital certificates")
        lines: [
            qsTr("ICP-Brasil certificates install in a few clicks, through KDE's Kleopatra."),
            qsTr("Made by Paweł and Daniel for every SparkyLinux edition.")
        ]
    }
}
