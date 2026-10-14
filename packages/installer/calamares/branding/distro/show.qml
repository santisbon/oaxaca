/* Calamares slideshow (API 2): one slide while the installation runs. */
import QtQuick 2.0
import calamares.slideshow 1.0

Presentation {
    id: presentation
    function onActivate() { }
    function onLeave() { }

    Slide {
        Rectangle { anchors.fill: parent; color: "#1a1b26" }
        Text {
            anchors.centerIn: parent
            width: parent.width * 0.8
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            color: "#c0caf5"
            font.pixelSize: 22
            text: "Installing. The desktop, its tools and the first user's configuration are being set up; the computer restarts into the login screen when this finishes."
        }
    }
}
