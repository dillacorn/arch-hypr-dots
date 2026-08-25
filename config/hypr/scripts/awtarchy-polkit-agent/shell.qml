//@ pragma AppId awtarchy-polkit-agent
//@ pragma ShellId awtarchy-polkit-agent
//@ pragma IgnoreSystemSettings
//@ pragma DropExpensiveFonts

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Polkit

ShellRoot {
    id: root

    readonly property color backgroundColor: "#202020"
    readonly property color borderColor: "#8a8a8a"
    readonly property color foregroundColor: "#dedede"
    readonly property color mutedColor: "#969696"
    readonly property color accentColor: "#ff6cff"
    readonly property color cancelColor: "#ff6b65"
    readonly property color authenticateColor: "#a6e36a"
    readonly property color errorColor: "#ff7770"
    readonly property color fieldBackground: "#e7e3dc"
    readonly property color fieldForeground: "#171717"
    readonly property string fontFamily: "NotoSansM Nerd Font Mono"

    readonly property var flow: polkitAgent.flow
    property bool detailsExpanded: false
    property string actionDescription: ""
    property string actionVendor: ""
    property string actionMessage: ""

    function clearResponse() {
        inputField.text = "";
    }

    function identityText() {
        if (!flow || !flow.selectedIdentity)
            return "Unavailable";

        const identity = flow.selectedIdentity;
        let name = "";
        if (identity.string !== undefined && identity.string !== null)
            name = String(identity.string);
        else if (identity.displayName !== undefined && identity.displayName !== null)
            name = String(identity.displayName);

        if (name.length === 0)
            return "Unavailable";

        const isGroup = identity.isGroup === true;
        return (isGroup ? "unix-group:" : "unix-user:") + name;
    }

    function promptText() {
        if (!flow)
            return "Password:";
        const prompt = String(flow.inputPrompt || "").trim();
        return prompt.length > 0 ? prompt : "Password:";
    }

    function submitResponse() {
        if (!flow || !flow.isResponseRequired)
            return;

        const response = inputField.text;
        inputField.text = "";
        flow.submit(response);
    }

    function cancelRequest() {
        clearResponse();
        if (flow)
            flow.cancelAuthenticationRequest();
    }

    function resetActionMetadata() {
        actionDescription = "";
        actionVendor = "";
        actionMessage = "";
    }

    function parseActionMetadata(rawText) {
        resetActionMetadata();

        const lines = String(rawText || "").split("\n");
        for (const rawLine of lines) {
            const line = rawLine.trim();
            let separator = line.indexOf(":");
            if (separator <= 0)
                continue;

            const key = line.substring(0, separator).trim().toLowerCase();
            const value = line.substring(separator + 1).trim();
            if (key === "description")
                actionDescription = value;
            else if (key === "vendor")
                actionVendor = value;
            else if (key === "message")
                actionMessage = value;
        }
    }

    function refreshActionMetadata() {
        resetActionMetadata();
        if (!flow || !flow.actionId)
            return;

        actionInfoProcess.exec([
            "/usr/bin/pkaction",
            "--action-id",
            String(flow.actionId),
            "--verbose"
        ]);
    }

    function resetForNewFlow() {
        detailsExpanded = false;
        clearResponse();
        refreshActionMetadata();
        if (flow)
            focusTimer.restart();
    }

    PolkitAgent {
        id: polkitAgent
        path: "/org/awtarchy/PolkitAgent"
        onFlowChanged: root.resetForNewFlow()
    }

    Process {
        id: actionInfoProcess
        clearEnvironment: true
        environment: ({
            LANG: "C.UTF-8",
            LC_ALL: "C.UTF-8",
            PATH: "/usr/bin"
        })
        stdout: StdioCollector {
            onStreamFinished: root.parseActionMetadata(this.text)
        }
        stderr: StdioCollector {}
    }

    Timer {
        id: focusTimer
        interval: 80
        repeat: false
        onTriggered: {
            if (authWindow.visible && root.flow && root.flow.isResponseRequired)
                inputField.forceActiveFocus();
            else if (authWindow.visible)
                detailsToggle.forceActiveFocus();
        }
    }

    Connections {
        target: root.flow

        function onAuthenticationFailed() {
            root.clearResponse();
            focusTimer.restart();
        }

        function onAuthenticationSucceeded() {
            root.clearResponse();
        }

        function onAuthenticationRequestCancelled() {
            root.clearResponse();
        }

        function onIsResponseRequiredChanged() {
            root.clearResponse();
            if (root.flow && root.flow.isResponseRequired)
                focusTimer.restart();
        }
    }

    FloatingWindow {
        id: authWindow

        visible: polkitAgent.isActive
        title: "awtarchy-polkit-agent"
        implicitWidth: 900
        implicitHeight: 520
        minimumSize: Qt.size(900, 520)
        maximumSize: Qt.size(900, 520)
        color: root.backgroundColor

        onVisibleChanged: {
            if (visible)
                focusTimer.restart();
            else
                root.clearResponse();
        }

        Rectangle {
            anchors.fill: parent
            color: root.backgroundColor
            border.width: 1
            border.color: root.borderColor

            Text {
                x: 42
                y: 40
                text: "Authentication Required"
                color: root.accentColor
                font.family: root.fontFamily
                font.pixelSize: 17
                font.bold: true
                textFormat: Text.PlainText
            }

            Text {
                x: 42
                y: 86
                width: parent.width - 84
                height: 64
                text: root.flow ? String(root.flow.message || "Authentication is required.") : "Authentication is required."
                color: root.foregroundColor
                font.family: root.fontFamily
                font.pixelSize: 16
                wrapMode: Text.Wrap
                verticalAlignment: Text.AlignTop
                textFormat: Text.PlainText
            }

            Text {
                id: promptLabel
                x: 42
                y: 167
                width: 120
                text: root.promptText()
                color: root.foregroundColor
                font.family: root.fontFamily
                font.pixelSize: 16
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }

            Rectangle {
                x: 150
                y: 157
                width: 420
                height: 34
                color: root.fieldBackground
                border.width: inputField.activeFocus ? 2 : 1
                border.color: inputField.activeFocus ? root.accentColor : root.mutedColor
                opacity: root.flow && root.flow.isResponseRequired ? 1.0 : 0.55

                TextInput {
                    id: inputField
                    anchors.fill: parent
                    anchors.leftMargin: 9
                    anchors.rightMargin: 9
                    verticalAlignment: TextInput.AlignVCenter
                    color: root.fieldForeground
                    selectionColor: root.accentColor
                    selectedTextColor: root.fieldForeground
                    font.family: root.fontFamily
                    font.pixelSize: 16
                    enabled: root.flow && root.flow.isResponseRequired
                    activeFocusOnTab: true
                    echoMode: root.flow && root.flow.responseVisible ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "•"
                    clip: true
                    KeyNavigation.tab: detailsToggle
                    KeyNavigation.backtab: authenticateButton

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            root.cancelRequest();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            root.submitResponse();
                            event.accepted = true;
                        }
                    }
                }
            }

            Text {
                id: detailsToggle
                x: 42
                y: 215
                width: 210
                height: 30
                focus: false
                activeFocusOnTab: true
                text: (root.detailsExpanded ? "▼" : "▶") + " Details:"
                color: activeFocus ? root.foregroundColor : root.accentColor
                font.family: root.fontFamily
                font.pixelSize: 16
                font.bold: true
                textFormat: Text.PlainText
                KeyNavigation.tab: cancelButton
                KeyNavigation.backtab: inputField

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.detailsExpanded = !root.detailsExpanded;
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Escape) {
                        root.cancelRequest();
                        event.accepted = true;
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.detailsExpanded = !root.detailsExpanded;
                        detailsToggle.forceActiveFocus();
                    }
                }
            }

            Item {
                x: 62
                y: 249
                width: parent.width - 124
                height: 112
                visible: root.detailsExpanded

                Text {
                    x: 0
                    y: 0
                    text: "Action:"
                    color: root.mutedColor
                    font.family: root.fontFamily
                    font.pixelSize: 15
                    textFormat: Text.PlainText
                }
                Text {
                    x: 130
                    y: 0
                    width: parent.width - 130
                    text: root.flow ? String(root.flow.actionId || "Unavailable") : "Unavailable"
                    color: root.foregroundColor
                    font.family: root.fontFamily
                    font.pixelSize: 15
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }

                Text {
                    x: 0
                    y: 25
                    text: "Vendor:"
                    color: root.mutedColor
                    font.family: root.fontFamily
                    font.pixelSize: 15
                    textFormat: Text.PlainText
                }
                Text {
                    x: 130
                    y: 25
                    width: parent.width - 130
                    text: root.actionVendor.length > 0 ? root.actionVendor : "Unavailable"
                    color: root.foregroundColor
                    font.family: root.fontFamily
                    font.pixelSize: 15
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }

                Text {
                    x: 0
                    y: 50
                    text: "Description:"
                    color: root.mutedColor
                    font.family: root.fontFamily
                    font.pixelSize: 15
                    textFormat: Text.PlainText
                }
                Text {
                    x: 130
                    y: 50
                    width: parent.width - 130
                    text: root.actionDescription.length > 0 ? root.actionDescription
                        : (root.actionMessage.length > 0 ? root.actionMessage : "Unavailable")
                    color: root.foregroundColor
                    font.family: root.fontFamily
                    font.pixelSize: 15
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }

                Text {
                    x: 0
                    y: 75
                    text: "Identity:"
                    color: root.mutedColor
                    font.family: root.fontFamily
                    font.pixelSize: 15
                    textFormat: Text.PlainText
                }
                Text {
                    x: 130
                    y: 75
                    width: parent.width - 130
                    text: root.identityText()
                    color: root.foregroundColor
                    font.family: root.fontFamily
                    font.pixelSize: 15
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
            }

            Text {
                id: cancelButton
                x: 283
                y: 375
                width: 120
                height: 34
                focus: false
                activeFocusOnTab: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: "[ Cancel ]"
                color: activeFocus ? root.foregroundColor : root.cancelColor
                font.family: root.fontFamily
                font.pixelSize: 16
                font.bold: true
                textFormat: Text.PlainText
                KeyNavigation.tab: authenticateButton
                KeyNavigation.backtab: detailsToggle

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        root.cancelRequest();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Escape) {
                        root.cancelRequest();
                        event.accepted = true;
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.cancelRequest()
                }
            }

            Text {
                id: authenticateButton
                x: 455
                y: 375
                width: 190
                height: 34
                focus: false
                activeFocusOnTab: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: "[ Authenticate ]"
                color: activeFocus ? root.foregroundColor
                    : (root.flow && root.flow.isResponseRequired ? root.authenticateColor : root.mutedColor)
                font.family: root.fontFamily
                font.pixelSize: 16
                font.bold: true
                textFormat: Text.PlainText
                KeyNavigation.tab: inputField
                KeyNavigation.backtab: cancelButton

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        root.submitResponse();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Escape) {
                        root.cancelRequest();
                        event.accepted = true;
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: root.flow && root.flow.isResponseRequired ? Qt.PointingHandCursor : Qt.ArrowCursor
                    enabled: root.flow && root.flow.isResponseRequired
                    onClicked: root.submitResponse()
                }
            }

            Text {
                x: 42
                y: 424
                width: parent.width - 84
                height: 38
                visible: root.flow && String(root.flow.supplementaryMessage || "").length > 0
                text: root.flow ? String(root.flow.supplementaryMessage || "") : ""
                color: root.flow && root.flow.supplementaryIsError ? root.errorColor : root.foregroundColor
                font.family: root.fontFamily
                font.pixelSize: 14
                wrapMode: Text.Wrap
                textFormat: Text.PlainText
            }

            Text {
                x: 42
                y: 474
                text: "Tab/Shift+Tab: move   Enter: activate   Mouse: click   Esc: cancel"
                color: root.mutedColor
                font.family: root.fontFamily
                font.pixelSize: 13
                textFormat: Text.PlainText
            }
        }
    }
}
