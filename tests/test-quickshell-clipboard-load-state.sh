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
assert.deepStrictEqual(withThumbnail.map(entry => entry.index), [0, 1],
  "thumbnail update changed the model identity or order");
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

assert.strictEqual(helper.globMatch("awtarchy-text", "awtarchy*"), true,
  "trailing wildcard did not match a clipboard label prefix");
assert.strictEqual(helper.globMatch("prefix-awtarchy-text", "awtarchy*"), false,
  "trailing wildcard ignored the requested prefix anchor");
assert.strictEqual(helper.globMatch("text-awtarchy", "*awtarchy"), true,
  "leading wildcard did not match a clipboard label suffix");
assert.strictEqual(helper.globMatch("text-awtarchy-suffix", "*awtarchy"), false,
  "leading wildcard ignored the requested suffix anchor");
assert.strictEqual(helper.globMatch("before-awtarchy-after", "*awtarchy*"), true,
  "leading and trailing wildcards did not match text containing the query");
assert.strictEqual(helper.globMatch("awtZZZarchy", "awt*archy"), true,
  "middle wildcard did not match arbitrary text");
assert.strictEqual(helper.globMatch("AWTARCHY-TEXT", "awtarchy*"), true,
  "wildcard matching was not case-insensitive");
assert.strictEqual(helper.globMatch("awtarchy[1]-text", "awtarchy[1]*"), true,
  "wildcard search treated regex metacharacters as executable syntax");
assert.strictEqual(helper.globMatch("anything at all", "*"), true,
  "a wildcard-only query did not match all clipboard labels");

let transition = helper.requestListLoad(false, false);
assert.deepStrictEqual(transition, {
  startNow: true,
  stopNow: false,
  restartPending: false
}, "idle clipboard list did not start immediately");

transition = helper.requestListLoad(true, false);
assert.deepStrictEqual(transition, {
  startNow: false,
  stopNow: true,
  restartPending: true
}, "active clipboard list was restarted before its old process exited");

transition = helper.requestListLoad(false, true);
assert.deepStrictEqual(transition, {
  startNow: false,
  stopNow: false,
  restartPending: true
}, "clipboard reopen did not wait for the stopping process to exit");

assert.deepStrictEqual(helper.finishListLoad(true, true), {
  startNext: true,
  keepLoading: true
}, "pending clipboard restart was not continued after process exit");
assert.deepStrictEqual(helper.finishListLoad(true, false), {
  startNext: false,
  keepLoading: false
}, "closed clipboard restarted a stale list process");

console.log("PASS: progressive clipboard model preserves stable rows, wildcard matching, and restart ordering.");
NODE

require_source 'import "ClipboardLoadState.js" as ClipboardLoadState' \
  'Clipboard menu does not use the tested progressive-load model'
require_source 'stdout: SplitParser {' \
  'Clipboard list still waits for the complete process output'
require_source 'onRead: line => root.appendClipboardRecord(line)' \
  'Clipboard list does not append records as they arrive'
require_source 'ClipboardLoadState.requestListLoad(' \
  'Clipboard list does not use the tested stop-before-restart lifecycle'
require_source 'ClipboardLoadState.enqueueThumbnail(' \
  'Clipboard menu does not deduplicate lazy thumbnail requests'
require_source 'ClipboardLoadState.globMatch(' \
  'Clipboard wildcard searches do not use the tested glob matcher'
require_source 'query.indexOf("*") >= 0' \
  'Clipboard search does not switch to glob semantics when a wildcard is present'
require_source '[root.backend, "thumb", String(root.activeThumbnailIndex)]' \
  'Clipboard menu does not request thumbnails through the lazy backend action'
require_source 'reuseItems: true' \
  'Clipboard list does not recycle delegates while scrolling'
require_source 'cacheBuffer: 0' \
  'Clipboard list eagerly instantiates rows outside the visible viewport'
require_source 'objectProp: "index"' \
  'Clipboard list has no stable key for in-place thumbnail updates'
require_source 'visible: root.listLoading && root.entries.length === 0' \
  'Clipboard menu has no initial loading state'
require_source 'text: "Loading clipboard history…"' \
  'Clipboard loading state has no user-visible label'
require_source 'visible: !root.listLoading && root.entries.length === 0' \
  'Clipboard menu has no empty-history state'
require_source 'text: "No clipboard matches"' \
  'Clipboard menu leaves an empty search result blank'
require_source 'Behavior on opacity {' \
  'Progressively loaded clipboard rows do not animate into view'
require_source 'duration: Math.min(Math.max(row.index, 0), 12) * 18' \
  'Clipboard row animation can still receive a negative recycled delegate index'
require_source 'id: clipboardContent' \
  'Clipboard list and status/detail surfaces do not share one layout cell container'
require_source 'id: clipboardStatus' \
  'Clipboard status overlay is not inside the shared clipboard content container'
require_source 'id: clipboardDetail' \
  'Clipboard detail surface is not inside the shared clipboard content container'
require_source 'function deleteEntry(entry)' \
  'Clipboard menu has no per-entry delete action'
require_source 'deleteProcess.exec([backend, "delete", String(entry.index)]);' \
  'Clipboard delete action does not target the stable backend row index'
require_source 'id: deleteProcess' \
  'Clipboard deletion does not use a dedicated process lifecycle'
require_source 'if (exitCode === 0 && root.clipboardWindowVisible())' \
  'Clipboard deletion does not preserve the open flyout before refreshing'
require_source 'root.beginListLoad();' \
  'Clipboard deletion does not refresh the progressive list after success'
require_source 'id: deleteButton' \
  'Clipboard rows have no permanent-delete control'
require_source 'root.deleteEntry(row.modelData);' \
  'Clipboard row delete control is not wired to the selected model entry'

# Real-session diagnostics exposed both failures this section guards: recycled
# delegates produced negative animation durations, and list/status/detail items
# competed for one outer GridLayout cell.
if grep -A5 -F 'id: clipboardList' "$QML" | grep -Fq 'Layout.row:'; then
  fail 'Clipboard ListView still participates directly in the outer GridLayout'
fi
if grep -A5 -F 'id: clipboardStatus' "$QML" | grep -Fq 'Layout.row:'; then
  fail 'Clipboard status overlay still participates directly in the outer GridLayout'
fi
if grep -A5 -F 'id: clipboardDetail' "$QML" | grep -Fq 'Layout.row:'; then
  fail 'Clipboard detail surface still participates directly in the outer GridLayout'
fi

# Per-entry deletion is permanent and must preserve the flyout while refreshing.
