pragma Singleton

import QtQuick

QtObject {
    id: root

    property string activeSurface: ""
    signal closeRequested(string exceptSurface)

    function claim(surface) {
        closeRequested(surface);
        activeSurface = surface;
    }

    function release(surface) {
        if (activeSurface === surface)
            activeSurface = "";
    }
}
