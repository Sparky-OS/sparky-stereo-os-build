import QtQuick
import org.kde.kwin.decoration

Decoration {
    Component.onCompleted: {
        borders.left = 4; borders.right = 4; borders.top = 28; borders.bottom = 4;
        console.log("SHADE_PROBE_DECORATION_LOADED");
    }
    Rectangle { width: parent.width; height: 28; color: "#d8d9d5" }
    Timer {
        interval: 7000; running: true
        onTriggered: {
            if (decoration.client.caption === "Active opaque") {
                console.log("AURORAE_SHADEABLE=" + decoration.client.shadeable);
                console.log("AURORAE_SHADED=" + decoration.client.shaded);
                console.log("AURORAE_SHADE_METHOD=" + typeof decoration.requestToggleShade);
                decoration.requestToggleShade();
                console.log("AURORAE_SHADED_AFTER=" + decoration.client.shaded);
            }
        }
    }
}
