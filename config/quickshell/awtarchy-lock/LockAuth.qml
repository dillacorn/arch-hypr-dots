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
    readonly property bool responseRequired: pam.responseRequired

    signal authenticated()
    signal authenticationFailed()

    function clearStatus() {
        if (pam.active)
            return;
        statusText = "";
        statusIsError = false;
    }

    function submit(response) {
        if (response.length === 0 || pam.active)
            return false;

        pendingResponse = response;
        statusText = "Authenticating…";
        statusIsError = false;
        pam.start();
        return true;
    }

    PamContext {
        id: pam
        configDirectory: "pam"
        config: "password.conf"

        onPamMessage: {
            if (responseRequired && root.pendingResponse.length > 0) {
                pam.respond(root.pendingResponse);
                root.pendingResponse = "";
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
            root.authenticationFailed();
        }

        onCompleted: result => {
            root.pendingResponse = "";

            if (result === PamResult.Success) {
                root.statusText = "";
                root.statusIsError = false;
                root.authenticated();
                return;
            }

            root.statusText = "Incorrect password";
            root.statusIsError = true;
            root.authenticationFailed();
        }
    }
}
