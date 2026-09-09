import QtQuick
import Quickshell.Wayland

WlSessionLockSurface {
    id: root

    required property var auth
    required property var theme
    required property bool unlocking
    required property string animationPreference
    required property int randomFormationMode
    required property bool audioReactive
    required property real audioLow
    required property real audioMid
    required property real audioHigh
    required property real audioOverall
    required property bool mouseInteractive
    required property bool showLogo
    required property bool showTime
    required property bool showDate
    required property bool showUsername
    required property bool showWeather
    required property string weatherText
    required property string backgroundMode
    required property string wallpaperSource
    required property color autoAccent
    required property var layout

    color: "#000000"

    readonly property real uiScale: scene.uiScale
    readonly property real passwordScale: scene.elementScale("password")
    readonly property int maskedCount: Math.min(password.text.length, 10)
    readonly property real maskSpread: maskedCount === 0 ? 0
        : Math.round((24 + maskedCount * 14) * uiScale * passwordScale)

    property bool entered: false

    function submitPassword() {
        if ((auth.busy && !auth.responseRequired) || password.text.length === 0)
            return;

        const response = password.text;
        if (auth.submit(response))
            password.text = "";
    }

    PinchHandler {
        target: null
    }

    WheelHandler {
        target: null
    }

    LockScene {
        id: scene
        anchors.fill: parent
        theme: root.theme
        unlocking: root.unlocking
        animationPreference: root.animationPreference
        randomFormationMode: root.randomFormationMode
        audioReactive: root.audioReactive
        audioLow: root.audioLow
        audioMid: root.audioMid
        audioHigh: root.audioHigh
        audioOverall: root.audioOverall
        mouseInteractive: root.mouseInteractive
        showLogo: root.showLogo
        showTime: root.showTime
        showDate: root.showDate
        showUsername: root.showUsername
        showWeather: root.showWeather
        weatherText: root.weatherText
        backgroundMode: root.backgroundMode
        wallpaperSource: root.wallpaperSource
        autoAccent: root.autoAccent
        layout: root.layout
        previewMode: false
    }

    MouseArea {
        id: pointerArea
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        cursorShape: Qt.BlankCursor
        onPositionChanged: mouse => scene.handlePointerMotion(mouse.x, mouse.y)
        onClicked: mouse => {
            scene.handlePointerClick(mouse.x, mouse.y);
            password.forceActiveFocus();
        }
        onWheel: wheel => { wheel.accepted = true; }
    }

    Item {
        id: passwordBlock
        x: scene.passwordCenterX - width / 2
        y: scene.passwordCenterY - height / 2
        width: scene.passwordWidth
        height: scene.passwordHeight
        z: 20
        opacity: root.unlocking ? 0 : root.entered ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: root.unlocking ? 160 : 220
                easing.type: Easing.OutCubic
            }
        }

        Rectangle {
            anchors.centerIn: parent
            width: root.maskSpread
            height: Math.round(14 * root.uiScale * root.passwordScale)
            color: scene.elementColor("password")
            opacity: password.text.length > 0 ? 0.09 : 0
        }

        Row {
            anchors.centerIn: parent
            spacing: Math.round(7 * root.uiScale * root.passwordScale)

            Repeater {
                model: root.maskedCount

                Rectangle {
                    width: Math.round(7 * root.uiScale * root.passwordScale)
                    height: Math.round(10 * root.uiScale * root.passwordScale)
                    color: scene.elementColor("password")
                    opacity: 0.82
                }
            }
        }

        TextInput {
            id: password
            anchors.fill: parent

            color: "transparent"
            selectionColor: "transparent"
            selectedTextColor: "transparent"
            cursorVisible: false
            font.family: root.theme.fontFamily
            font.pixelSize: Math.round(18 * root.uiScale * root.passwordScale)
            horizontalAlignment: TextInput.AlignHCenter
            verticalAlignment: TextInput.AlignVCenter
            echoMode: TextInput.Password
            inputMethodHints: Qt.ImhSensitiveData
            enabled: !auth.busy || auth.responseRequired
            activeFocusOnTab: true

            onTextChanged: {
                if (text.length > 0 && root.auth.statusIsError)
                    root.auth.clearStatus();
            }

            Keys.onReturnPressed: event => {
                root.submitPassword();
                event.accepted = true;
            }

            Keys.onEnterPressed: event => {
                root.submitPassword();
                event.accepted = true;
            }

            Keys.onEscapePressed: event => {
                password.text = "";
                auth.clearStatus();
                event.accepted = true;
            }
        }
    }

    Connections {
        target: root.auth

        function onAuthenticationFailed() {
            password.text = "";
            Qt.callLater(() => password.forceActiveFocus());
        }

        function onBusyChanged() {
            if (!root.auth.busy)
                Qt.callLater(() => password.forceActiveFocus());
        }

        function onResponseRequiredChanged() {
            if (root.auth.responseRequired)
                Qt.callLater(() => password.forceActiveFocus());
        }
    }

    Component.onCompleted: {
        root.entered = true;
        Qt.callLater(() => password.forceActiveFocus());
    }
}
