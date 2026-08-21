function edgeOf(placement) {
    var value = String(placement || "").toLowerCase();
    if (value.indexOf("bottom") === 0)
        return "bottom";
    if (value.indexOf("top") === 0)
        return "top";
    if (value.indexOf("left") === 0)
        return "left";
    if (value.indexOf("right") === 0)
        return "right";
    return "center";
}

function isBottom(placement) {
    return edgeOf(placement) === "bottom";
}

function sectionRow(bottomEdge, logicalIndex, sectionCount) {
    return bottomEdge ? sectionCount - logicalIndex - 1 : logicalIndex;
}

function notificationPositionOptions() {
    return [
        "automatic",
        "top-left",
        "top-center",
        "top-right",
        "bottom-left",
        "bottom-center",
        "bottom-right"
    ];
}

function isNotificationPosition(position) {
    return notificationPositionOptions().indexOf(String(position || "")) >= 0;
}

function resolveNotificationPosition(savedPosition, barPlacement) {
    var requested = String(savedPosition || "automatic");
    if (requested !== "automatic" && isNotificationPosition(requested))
        return requested;

    var edge = edgeOf(barPlacement);
    if (edge === "bottom")
        return "bottom-right";
    if (edge === "left")
        return "top-left";
    return "top-right";
}

function positionIsTop(position) {
    return String(position || "").indexOf("top-") === 0;
}

function positionIsBottom(position) {
    return String(position || "").indexOf("bottom-") === 0;
}

function positionIsLeft(position) {
    return String(position || "").lastIndexOf("-left") === String(position || "").length - 5;
}

function positionIsRight(position) {
    return String(position || "").lastIndexOf("-right") === String(position || "").length - 6;
}

if (typeof module !== "undefined") {
    module.exports = {
        edgeOf: edgeOf,
        isBottom: isBottom,
        sectionRow: sectionRow,
        notificationPositionOptions: notificationPositionOptions,
        isNotificationPosition: isNotificationPosition,
        resolveNotificationPosition: resolveNotificationPosition,
        positionIsTop: positionIsTop,
        positionIsBottom: positionIsBottom,
        positionIsLeft: positionIsLeft,
        positionIsRight: positionIsRight
    };
}
