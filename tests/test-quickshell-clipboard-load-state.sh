#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="${ROOT}/config/quickshell/awtarchy/ClipboardLoadState.js"
QML="${ROOT}/config/quickshell/awtarchy/ClipboardMenu.qml"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_source() {
  local expected="$1" description="$2"
  grep -Fq -- "$expected" "$QML" || fail "$description"
}

node - "$HELPER" <<'NODE'
const fs = require("fs");
const assert = require("assert");
const helperPath = process.argv[2];

assert.ok(fs.existsSync(helperPath), "clipboard progressive-load state helper is missing");
const helper = require(helperPath);

let entries = [];
entries = helper.appendRecord(entries,
  '{"index":0,"label":"newest","thumb":"","binary":false}');
entries = helper.appendRecord(entries,
  '{"index":1,"label":"older image","thumb":"","binary":true}');

assert.deepStrictEqual(entries.map(entry => entry.label), ["newest", "older image"],
  "streamed clipboard records did not retain newest-first arrival order");
assert.notStrictEqual(entries, helper.appendRecord(entries, "not json"),
  "malformed records should return an independently owned list");
assert.deepStrictEqual(helper.appendRecord(entries, "not json"), entries,
  "malformed clipboard records changed the current model");

const withThumbnail = helper.updateThumbnail(entries, 1, "/tmp/cached.png");
assert.strictEqual(withThumbnail[0].thumb, "",
  "thumbnail update changed the wrong clipboard entry");
assert.strictEqual(withThumbnail[1].thumb, "/tmp/cached.png",
  "thumbnail update did not target the requested clipboard entry");
assert.strictEqual(entries[1].thumb, "",
  "thumbnail update mutated the prior model in place");

let queueState = helper.enqueueThumbnail([], {}, 1);
assert.deepStrictEqual(queueState.queue, [1],
  "binary clipboard entry was not queued for lazy thumbnail loading");
queueState = helper.enqueueThumbnail(queueState.queue, queueState.known, 1);
assert.deepStrictEqual(queueState.queue, [1],
  "duplicate thumbnail request was queued twice");
queueState = helper.enqueueThumbnail(queueState.queue, queueState.known, -1);
assert.deepStrictEqual(queueState.queue, [1],
  "invalid thumbnail index was accepted");

console.log("PASS: progressive clipboard model preserves order and deduplicates thumbnails.");
NODE

require_source 'import "ClipboardLoadState.js" as ClipboardLoadState' \
  'Clipboard menu does not use the tested progressive-load model'
require_source 'stdout: SplitParser {' \
  'Clipboard list still waits for the complete process output'
require_source 'onRead: line => root.appendClipboardRecord(line)' \
  'Clipboard list does not append records as they arrive'
require_source 'ClipboardLoadState.enqueueThumbnail(' \
  'Clipboard menu does not deduplicate lazy thumbnail requests'
require_source '[root.backend, "thumb", String(root.activeThumbnailIndex)]' \
  'Clipboard menu does not request thumbnails through the lazy backend action'
require_source 'reuseItems: true' \
  'Clipboard list does not recycle delegates while scrolling'
require_source 'cacheBuffer: 0' \
  'Clipboard list eagerly instantiates rows outside the visible viewport'
require_source 'visible: root.listLoading && root.entries.length === 0' \
  'Clipboard menu has no initial loading state'
require_source 'text: "Loading clipboard history…"' \
  'Clipboard loading state has no user-visible label'
require_source 'visible: !root.listLoading && root.entries.length === 0' \
  'Clipboard menu has no empty-history state'
require_source 'Behavior on opacity {' \
  'Progressively loaded clipboard rows do not animate into view'
require_source 'duration: Math.min(row.index, 12) * 18' \
  'Clipboard row animation does not visibly progress newest-first'
