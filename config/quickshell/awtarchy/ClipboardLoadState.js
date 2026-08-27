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

if (typeof module !== "undefined") {
    module.exports = {
        parseRecord: parseRecord,
        appendRecord: appendRecord,
        updateThumbnail: updateThumbnail,
        enqueueThumbnail: enqueueThumbnail
    };
}
