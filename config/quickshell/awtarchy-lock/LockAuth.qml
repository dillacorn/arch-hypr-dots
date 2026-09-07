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

    signal authenticated()
    signal authenticationFailed()

    function clearStatus() {
        if (pam.active)
            return;
        statusText = "";
        statusIsError = false;
    }

    function submit(response) {
        if (pam.active || response.length === 0)
            return false;

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

            pam.respond(pendingResponse);
            root.pendingResponse = "";
        }

        onPamMessage: {
            if (!responseRequired && messageIsError) {
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
