function parseRecord(line) {
    var value;
    try {
        value = JSON.parse(String(line || "").trim());
    } catch (error) {
        return null;
    }

    if (!value || typeof value !== "object"
            || typeof value.index !== "number"
            || !isFinite(value.index)
            || Math.floor(value.index) !== value.index
            || value.index < 0
            || typeof value.label !== "string"
            || typeof value.binary !== "boolean")
        return null;

    return {
        index: value.index,
        label: value.label,
        thumb: typeof value.thumb === "string" ? value.thumb : "",
        binary: value.binary
    };
}

function appendRecord(entries, line) {
    var current = Array.isArray(entries) ? entries : [];
    var record = parseRecord(line);
    return record ? current.concat([record]) : current.slice();
}

function updateThumbnail(entries, index, path) {
    var current = Array.isArray(entries) ? entries : [];
    var requestedIndex = Number(index);
    var thumbnailPath = String(path || "").trim();

    return current.map(function(entry) {
        if (!entry || entry.index !== requestedIndex || thumbnailPath.length === 0)
            return entry;
        return {
            index: entry.index,
            label: entry.label,
            thumb: thumbnailPath,
            binary: entry.binary
        };
    });
}

function removeRecord(entries, index) {
    var current = Array.isArray(entries) ? entries : [];
    var requestedIndex = Number(index);

    if (!isFinite(requestedIndex)
            || Math.floor(requestedIndex) !== requestedIndex
            || requestedIndex < 0)
        return current.slice();

    return current.filter(function(entry) {
        return !entry || entry.index !== requestedIndex;
    });
}

function enqueueThumbnail(queue, known, index) {
    var nextQueue = Array.isArray(queue) ? queue.slice() : [];
    var nextKnown = Object.assign({}, known || {});
    var requestedIndex = Number(index);

    if (!isFinite(requestedIndex)
            || Math.floor(requestedIndex) !== requestedIndex
            || requestedIndex < 0)
        return { queue: nextQueue, known: nextKnown };

    var key = String(requestedIndex);
    if (nextKnown[key] === true)
        return { queue: nextQueue, known: nextKnown };

    nextKnown[key] = true;
    nextQueue.push(requestedIndex);
    return { queue: nextQueue, known: nextKnown };
}

function globMatch(value, pattern) {
    var text = String(value || "").toLowerCase();
    var parts = String(pattern || "").toLowerCase().split("*");
    var escaped = parts.map(function(part) {
        return part.replace(/[\\^$.*+?()[\]{}|]/g, "\\$&");
    });
    return new RegExp("^" + escaped.join(".*") + "$").test(text);
}

function requestListLoad(processRunning, processStopping) {
    var running = processRunning === true;
    var stopping = processStopping === true;
    return {
        startNow: !running && !stopping,
        stopNow: running && !stopping,
        restartPending: running || stopping
    };
}

function finishListLoad(restartPending, windowVisible) {
    var startNext = restartPending === true && windowVisible === true;
    return {
        startNext: startNext,
        keepLoading: startNext
    };
}

if (typeof module !== "undefined") {
    module.exports = {
        parseRecord: parseRecord,
        appendRecord: appendRecord,
        updateThumbnail: updateThumbnail,
        removeRecord: removeRecord,
        enqueueThumbnail: enqueueThumbnail,
        globMatch: globMatch,
        requestListLoad: requestListLoad,
        finishListLoad: finishListLoad
    };
}
