#!/usr/bin/env python3
from pathlib import Path


def read(path):
    return Path(path).read_text(encoding="utf-8")


def write(path, text):
    Path(path).write_text(text, encoding="utf-8")


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


# Put maximum output volume in the normal Quick Settings page.
path = "config/quickshell/awtarchy/QuickSettings.qml"
text = read(path)
anchor = "                        PowerModeCard {\n"
card = '''                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: outputVolumeContent.implicitHeight + 16
                            color: Theme.popupButton
                            border.width: 1
                            border.color: Theme.active

                            ColumnLayout {
                                id: outputVolumeContent
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true

                                    Text {
                                        Layout.fillWidth: true
                                        text: "Maximum output volume"
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(12)
                                        font.bold: true
                                    }

                                    Text {
                                        text: AudioLimitState.limitPercent + "%"
                                        color: Theme.foreground
                                        font.family: Theme.fontFamily
                                        font.pixelSize: root.scaledText(10)
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    SettingsButton {
                                        label: "−5"
                                        available: AudioLimitState.limitPercent > AudioLimitState.minimumPercent
                                        textSize: root.scaledText(10)
                                        onClicked: AudioLimitState.setLimit(
                                            AudioLimitState.limitPercent - AudioLimitState.stepPercent)
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 24
                                        color: Theme.active
                                        border.width: 0

                                        Rectangle {
                                            width: parent.width * AudioLimitState.limitPercent
                                                / AudioLimitState.maximumPercent
                                            height: parent.height
                                            color: Theme.focus
                                        }
                                    }

                                    SettingsButton {
                                        label: "+5"
                                        available: AudioLimitState.limitPercent < AudioLimitState.maximumPercent
                                        textSize: root.scaledText(10)
                                        onClicked: AudioLimitState.setLimit(
                                            AudioLimitState.limitPercent + AudioLimitState.stepPercent)
                                    }

                                    SettingsButton {
                                        label: "100%"
                                        available: AudioLimitState.limitPercent !== 100
                                        textSize: root.scaledText(9)
                                        onClicked: AudioLimitState.setLimit(100)
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: "Global limit for Wiremix and bar volume scrolling · range 10–200%"
                                    color: Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: root.scaledText(8)
                                    wrapMode: Text.Wrap
                                }
                            }
                        }

'''
text = replace_once(text, anchor, card + anchor, "QuickSettings volume card")
write(path, text)

# Remove duplicate gear-only volume row.
path = "config/quickshell/awtarchy/FlyoutSettings.qml"
text = read(path)
text = replace_once(
    text,
    '''    implicitHeight: copyOpen ? 104
        : 139 + (surfaceLabel === "Quick Settings"
            ? volumeLimitRow.implicitHeight + barSection.implicitHeight + 9 : 0)
''',
    '''    implicitHeight: copyOpen ? 104
        : 139 + (surfaceLabel === "Quick Settings" ? barSection.implicitHeight + 6 : 0)
''',
    "FlyoutSettings implicit height",
)
start = text.index('''        RowLayout {
            id: volumeLimitRow
''')
end = text.index('''        BarSettingsSection {
''', start)
text = text[:start] + text[end:]
write(path, text)

# Global notification popup limit.
path = "config/quickshell/awtarchy/BarState.qml"
text = read(path)
text = replace_once(
    text,
    '''    function notificationViewFor(name) {
        const view = flyoutViewFor("notification_views", name,
            referenceNotificationWidth, referenceNotificationHeight);
        const d = data();
        const views = d.notification_views && typeof d.notification_views === "object"
            ? d.notification_views : ({});
        const raw = views[name] && typeof views[name] === "object"
            && !Array.isArray(views[name]) ? views[name] : ({});
        const popupLimit = Number(raw.popup_limit);
        return Object.assign({}, view, {
            popupLimit: Number.isFinite(popupLimit) && popupLimit >= 1 && popupLimit <= 20
                ? Math.round(popupLimit) : notificationPopupLimit()
        });
    }
''',
    '''    function notificationViewFor(name) {
        return flyoutViewFor("notification_views", name,
            referenceNotificationWidth, referenceNotificationHeight);
    }
''',
    "BarState global popup limit",
)
write(path, text)

path = "config/quickshell/awtarchy/Notifications.qml"
text = read(path)
text = replace_once(
    text,
    '''    readonly property int effectivePopupLimit: Math.max(1, Math.min(20,
        popupLimitOverride >= 0 ? popupLimitOverride : popupLimitForMonitor(activeMonitorName)))
''',
    '''    readonly property int effectivePopupLimit: Math.max(1, Math.min(20,
        popupLimitOverride >= 0 ? popupLimitOverride : BarState.notificationPopupLimit()))
''',
    "Notifications effective global limit",
)
text = replace_once(
    text,
    '''    function popupLimitForMonitor(name) {
        return BarState.notificationViewFor(String(name || "")).popupLimit;
    }
''',
    '''    function popupLimitForMonitor(name) {
        return BarState.notificationPopupLimit();
    }
''',
    "Notifications popup limit lookup",
)
text = replace_once(text, "        popupLimitOverride = persisted.popupLimit;\n",
                    "        popupLimitOverride = BarState.notificationPopupLimit();\n",
                    "Notifications load global limit")
text = replace_once(
    text,
    '''        queueStateCommand([
            "save-flyout", "notifications", activeMonitorName,
            String(livePanelWidth), String(livePanelHeight),
            String(effectiveTextScale), String(effectiveIconScale),
            captureAllowed ? "true" : "false",
            String(effectivePopupLimit)
        ]);
''',
    '''        queueStateCommand([
            "save-flyout", "notifications", activeMonitorName,
            String(livePanelWidth), String(livePanelHeight),
            String(effectiveTextScale), String(effectiveIconScale),
            captureAllowed ? "true" : "false"
        ]);
        queueStateCommand([
            "set-notification-popup-limit", String(effectivePopupLimit)
        ]);
''',
    "Notifications save global limit",
)
text = replace_once(
    text,
    '''        queueStateCommand(["reset-flyout", "notifications", activeMonitorName]);
        queueStateCommand([
            "set-notification-popup-limit", activeMonitorName,
            String(BarState.defaultNotificationPopupLimit)
        ]);
''',
    '''        queueStateCommand(["reset-flyout", "notifications", activeMonitorName]);
        queueStateCommand([
            "set-notification-popup-limit",
            String(BarState.defaultNotificationPopupLimit)
        ]);
''',
    "Notifications reset global limit",
)
text = replace_once(
    text,
    '''        queueStateCommand([
            "copy-flyout", "notifications",
            String(livePanelWidth), String(livePanelHeight),
            String(effectiveTextScale), String(effectiveIconScale),
            ...targets
        ]);
        for (const target of targets) {
            queueStateCommand([
                "set-notification-popup-limit", String(target), String(effectivePopupLimit)
            ]);
        }
''',
    '''        queueStateCommand([
            "copy-flyout", "notifications",
            String(livePanelWidth), String(livePanelHeight),
            String(effectiveTextScale), String(effectiveIconScale),
            ...targets
        ]);
''',
    "Notifications copy global limit",
)
text = replace_once(text,
                    '                            text: "Maximum simultaneous popups · " + root.activeMonitorName\n',
                    '                            text: "Maximum simultaneous popups · Global"\n',
                    "Notifications global label")
write(path, text)

# Persist one global notification popup limit and remove stale per-monitor copies.
path = "config/hypr/scripts/quickshell_application_state.sh"
text = read(path)
text = replace_once(
    text,
    '''        .[$view_key] = (if (.[$view_key] | type) == "object" then .[$view_key] else {} end)
        | .[$view_key][$monitor] = ({
            width:$width,
            height:$height,
            text_scale:$text_scale,
            icon_scale:$icon_scale,
            saved:true,
            save_version:$save_version
        } + (if $popup_limit == null then {} else {popup_limit:$popup_limit} end))
        | .capture_allowed = (if (.capture_allowed | type) == "object" then .capture_allowed else {} end)
        | .capture_allowed[$surface_key] = $capture
''',
    '''        .[$view_key] = (if (.[$view_key] | type) == "object" then .[$view_key] else {} end)
        | .[$view_key][$monitor] = {
            width:$width,
            height:$height,
            text_scale:$text_scale,
            icon_scale:$icon_scale,
            saved:true,
            save_version:$save_version
        }
        | .capture_allowed = (if (.capture_allowed | type) == "object" then .capture_allowed else {} end)
        | .capture_allowed[$surface_key] = $capture
        | if $popup_limit == null then . else
            .notification_popup_limit = $popup_limit
            | .notification_popup_limit_save_version = $save_version
            | .notification_views = ((if (.notification_views | type) == "object"
                then .notification_views else {} end)
                | with_entries(.value = (if (.value | type) == "object"
                    then (.value | del(.popup_limit)) else .value end)))
          end
''',
    "application state global save",
)
text = replace_once(
    text,
    '''set_notification_popup_limit() {
    local monitor="$1" popup_limit="$2"
    [[ -n "$monitor" ]] || { printf 'monitor is required\\n' >&2; exit 2; }
    validate_int_range "$popup_limit" 1 20 'notification popup limit'
    new_tmp
    jq \\
        --arg monitor "$monitor" \\
        --argjson popup_limit "$popup_limit" '
        .notification_views = (if (.notification_views | type) == "object"
            then .notification_views else {} end)
        | .notification_views[$monitor] = ((if (.notification_views[$monitor] | type) == "object"
            then .notification_views[$monitor] else {} end) + {popup_limit:$popup_limit})
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}
''',
    '''set_notification_popup_limit() {
    local popup_limit="$1"
    validate_int_range "$popup_limit" 1 20 'notification popup limit'
    new_tmp
    jq \\
        --argjson popup_limit "$popup_limit" \\
        --argjson save_version "$SAVE_VERSION" '
        .notification_popup_limit = $popup_limit
        | .notification_popup_limit_save_version = $save_version
        | .notification_views = ((if (.notification_views | type) == "object"
            then .notification_views else {} end)
            | with_entries(.value = (if (.value | type) == "object"
                then (.value | del(.popup_limit)) else .value end)))
    ' "$STATE_FILE" >"$TMP_FILE"
    commit_tmp
}
''',
    "application state global setter",
)
text = replace_once(
    text,
    '''        | .capture_allowed[$surface_key] = false
''',
    '''        | .capture_allowed[$surface_key] = false
        | if $view_key == "notification_views" then
            del(.notification_popup_limit, .notification_popup_limit_save_version)
            | .notification_views = (.notification_views
                | with_entries(.value = (if (.value | type) == "object"
                    then (.value | del(.popup_limit)) else .value end)))
          else . end
''',
    "application state reset global popup limit",
)
text = replace_once(
    text,
    '''    set-notification-popup-limit)
        [[ -n ${2:-} && -n ${3:-} ]] || exit 2
        set_notification_popup_limit "$2" "$3"
        ;;
''',
    '''    set-notification-popup-limit)
        [[ -n ${2:-} ]] || exit 2
        set_notification_popup_limit "$2"
        ;;
''',
    "application state global command",
)
text = text.replace("set-notification-popup-limit <MON> <1-20>",
                    "set-notification-popup-limit <1-20>")
write(path, text)

# Regression expectations.
path = "tests/test-quickshell-production-readiness.sh"
text = read(path)
text = replace_once(
    text,
    '''assert_contains "$APP_STATE" 'set-notification-popup-limit'
assert_contains "$APP_STATE" '{popup_limit:$popup_limit}'
assert_not_contains "$APP_STATE" '.notification_popup_limit = $popup_limit'
assert_contains "${REPO_ROOT}/config/quickshell/awtarchy/FlyoutSettings.qml" 'text: "Maximum output volume"'
assert_contains "${REPO_ROOT}/config/quickshell/awtarchy/Notifications.qml" 'persisted.popupLimit'
assert_not_contains "${REPO_ROOT}/config/quickshell/awtarchy/Notifications.qml" 'notification-popup-limits.json'
''',
    '''assert_contains "$APP_STATE" 'set-notification-popup-limit'
assert_contains "$APP_STATE" '.notification_popup_limit = $popup_limit'
assert_not_contains "$APP_STATE" '{popup_limit:$popup_limit}'
assert_contains "${REPO_ROOT}/config/quickshell/awtarchy/QuickSettings.qml" 'text: "Maximum output volume"'
assert_not_contains "${REPO_ROOT}/config/quickshell/awtarchy/FlyoutSettings.qml" 'text: "Maximum output volume"'
assert_contains "${REPO_ROOT}/config/quickshell/awtarchy/Notifications.qml" 'Maximum simultaneous popups · Global'
assert_not_contains "${REPO_ROOT}/config/quickshell/awtarchy/Notifications.qml" 'persisted.popupLimit'
assert_not_contains "${REPO_ROOT}/config/quickshell/awtarchy/Notifications.qml" 'notification-popup-limits.json'
''',
    "production readiness assertions",
)
write(path, text)
