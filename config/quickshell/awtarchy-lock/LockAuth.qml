import QtQuick
import Quickshell.Services.Pam

Item {
    id: root
    visible: false
    width: 0
    height: 0

    property string pendingResponse: ""
    property string statusText: ""
    property bool statusIsError: false

    readonly property bool busy: pam.active
    readonly property bool responseVisible: pam.responseVisible
    readonly property bool responseRequired: pam.responseRequired

    signal authenticated()
    signal authenticationFailed()

    function clearStatus() {
        if (pam.active)
            return;
        statusText = "";
        statusIsError = false;
    }

    function answerPendingResponse() {
        if (!pam.responseRequired || pendingResponse.length === 0)
            return false;

        pam.respond(pendingResponse);
        pendingResponse = "";
        return true;
    }

    function submit(response) {
        if (response.length === 0)
            return false;

        if (pam.active) {
            if (!pam.responseRequired)
                return false;

            pendingResponse = response;
            statusText = "Authenticating…";
            statusIsError = false;
            return answerPendingResponse();
        }

        pendingResponse = response;
        statusText = "Authenticating…";
        statusIsError = false;

        if (!pam.start()) {
            pendingResponse = "";
            statusText = "Authentication could not start";
            statusIsError = true;
            authenticationFailed();
            return false;
        }

        return true;
    }

    PamContext {
        id: pam
        config: "login"

        onResponseRequiredChanged: {
            if (!responseRequired || root.pendingResponse.length === 0)
                return;

            root.answerPendingResponse();
        }

        onPamMessage: {
            if (responseRequired) {
                root.statusText = pam.message;
                root.statusIsError = pam.messageIsError;
                return;
            }

            if (messageIsError) {
                root.statusText = "Authentication failed";
                root.statusIsError = true;
            }
        }

        onError: {
            root.pendingResponse = "";
            root.statusText = "Authentication error";
            root.statusIsError = true;
        }

        onCompleted: result => {
            root.pendingResponse = "";

            if (result === PamResult.Success) {
                root.statusText = "";
                root.statusIsError = false;
                root.authenticated();
                return;
            }

            root.statusText = "Authentication failed";
            root.statusIsError = true;
            root.authenticationFailed();
        }
    }
}
