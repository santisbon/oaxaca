// Generated from packages/installer/calamares/branding/distro/show.qml.in by scripts/render.py. Edit the .in file, not this one.
/* Calamares slideshow (API 2), shown while the installation runs: three slides that advance every
   20 seconds while the installer shows them (Calamares 3.3.14's own sample uses the same Timer on
   presentation.activatedInCalamares). Colors: the boot and login screens' background, the mark's
   agave and the wordmark's light neutral (docs/6, choice 105). logo.png is the installer's mark,
   in this folder. */
pragma ComponentBehavior: Bound
import QtQuick 2.0
import calamares.slideshow 1.0

Presentation {
    id: presentation

    readonly property color night: "#1a1b26"
    readonly property color agave: "#6CC6B4"
    readonly property color light: "#ECEEF6"
    readonly property color muted: "#a9b1d6"

    Timer {
        interval: 20000
        running: presentation.activatedInCalamares
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    function onActivate() { presentation.currentSlide = 0 }
    function onLeave() { }

    component Page: Slide {
        id: page
        property string heading
        property string body
        default property alias extra: column.data
        Rectangle { anchors.fill: parent; color: presentation.night }
        Column {
            id: column
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: parent.width * 0.12
            width: parent.width * 0.76
            spacing: 18
            Image { source: "logo.png"; width: 72; height: 72; smooth: false }
            Text {
                width: parent.width
                text: page.heading
                color: presentation.light
                font.pixelSize: 30
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }
            Text {
                width: parent.width
                visible: page.body !== ""
                text: page.body
                color: presentation.muted
                font.pixelSize: 18
                lineHeight: 1.35
                wrapMode: Text.WordWrap
            }
        }
    }

    Page {
        heading: "Installing Oaxaca"
        body: "Omarchy's keyboard-driven Hyprland desktop, on Ubuntu 26.10. When the installation finishes, the computer restarts into the login screen."
    }

    Page {
        heading: "Four keys to start with"
        Grid {
            columns: 2
            columnSpacing: 28
            rowSpacing: 10
            Repeater {
                model: [
                    "Super + Space", "Oaxaca menu",
                    "Super + Alt + Space", "Apps",
                    "Super + Return", "Terminal",
                    "Super + K", "Every keybinding"
                ]
                Text {
                    required property string modelData
                    required property int index
                    text: modelData
                    color: index % 2 === 0 ? presentation.agave : presentation.light
                    font.pixelSize: 18
                    font.weight: index % 2 === 0 ? Font.DemiBold : Font.Normal
                }
            }
        }
    }

    Page {
        heading: "Updates you can undo"
        body: "On btrfs, the installer's default file system, Oaxaca takes a Timeshift snapshot of the system before every update."
    }
}
