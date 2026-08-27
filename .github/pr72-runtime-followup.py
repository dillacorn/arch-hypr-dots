#!/usr/bin/env python3
from hashlib import sha256
from pathlib import Path

qml_path = Path("config/quickshell/awtarchy/ClipboardMenu.qml")
helper_path = Path("config/quickshell/awtarchy/ClipboardLoadState.js")
history_path = Path("local/share/awtarchy/quickshell-managed-history.sha256")

helper = helper_path.read_text()
if "function globMatch(value, pattern)" not in helper:
    raise SystemExit("ClipboardLoadState globMatch helper is missing")

qml = qml_path.read_text()

old_filter = '''    function filteredEntries() {
        const query = search.text.trim().toLowerCase();
        const scored = entries.map(entry => ({
            entry: entry,
            score: fuzzyScore(String(entry.label || "").toLowerCase(), query)
        })).filter(item => item.score >= 0);

        if (query.length > 0)
            scored.sort((a, b) => b.score - a.score);
        return scored.map(item => item.entry);
    }'''
new_filter = '''    function filteredEntries() {
        const query = search.text.trim().toLowerCase();
        const useGlob = query.indexOf("*") >= 0;
        const scored = entries.map(entry => {
            const label = String(entry.label || "").toLowerCase();
            return {
                entry: entry,
                score: useGlob
                    ? (ClipboardLoadState.globMatch(label, query) ? 0 : -1)
                    : fuzzyScore(label, query)
            };
        }).filter(item => item.score >= 0);

        if (query.length > 0 && !useGlob)
            scored.sort((a, b) => b.score - a.score);
        return scored.map(item => item.entry);
    }'''
if qml.count(old_filter) != 1:
    raise SystemExit("could not locate filteredEntries implementation exactly once")
qml = qml.replace(old_filter, new_filter, 1)

old_duration = "duration: Math.min(row.index, 12) * 18"
new_duration = "duration: Math.min(Math.max(row.index, 0), 12) * 18"
if qml.count(old_duration) != 1:
    raise SystemExit("could not locate row stagger duration exactly once")
qml = qml.replace(old_duration, new_duration, 1)

old_list = '''                ListView {
                    id: clipboardList
                    Layout.row: root.bottomEdgeLayout ? 0 : 2
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: !root.detailOpen'''
new_list = '''                Item {
                    id: clipboardContent
                    Layout.row: root.bottomEdgeLayout ? 0 : 2
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ListView {
                        id: clipboardList
                        anchors.fill: parent
                        visible: !root.detailOpen'''
if qml.count(old_list) != 1:
    raise SystemExit("could not locate top-level clipboard ListView exactly once")
qml = qml.replace(old_list, new_list, 1)

old_status = '''                Item {
                    Layout.row: root.bottomEdgeLayout ? 0 : 2
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: !root.detailOpen
                        && (root.entries.length === 0 || clipboardList.count === 0)'''
new_status = '''                    Item {
                        anchors.fill: parent
                        visible: !root.detailOpen
                            && (root.entries.length === 0 || clipboardList.count === 0)'''
if qml.count(old_status) != 1:
    raise SystemExit("could not locate clipboard status overlay exactly once")
qml = qml.replace(old_status, new_status, 1)

old_detail = '''                Item {
                    Layout.row: root.bottomEdgeLayout ? 0 : 2
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.detailOpen'''
new_detail = '''                    Item {
                        anchors.fill: parent
                        visible: root.detailOpen'''
if qml.count(old_detail) != 1:
    raise SystemExit("could not locate clipboard detail surface exactly once")
qml = qml.replace(old_detail, new_detail, 1)

old_tail = '''                        }
                    }
                }
            }
        }
    }
}
'''
new_tail = '''                        }
                    }
                }
                }
            }
        }
    }
}
'''
if not qml.endswith(old_tail):
    raise SystemExit("unexpected ClipboardMenu.qml closing structure")
qml = qml[: -len(old_tail)] + new_tail

qml_path.write_text(qml)

top_level_row = "                Layout.row: root.bottomEdgeLayout ? 0 : 2"
if sum(line == top_level_row for line in qml.splitlines()) != 1:
    raise SystemExit("top-level clipboard GridLayout still has duplicate row assignments")
if "ClipboardLoadState.globMatch(label, query)" not in qml:
    raise SystemExit("wildcard matcher was not wired into ClipboardMenu")
if new_duration not in qml:
    raise SystemExit("row stagger duration was not clamped")
if "id: clipboardContent" not in qml:
    raise SystemExit("shared clipboard content container was not created")

history = history_path.read_text()
managed = [
    (helper_path, ".config/quickshell/awtarchy/ClipboardLoadState.js"),
    (qml_path, ".config/quickshell/awtarchy/ClipboardMenu.qml"),
]
new_lines = []
for source, installed in managed:
    digest = sha256(source.read_bytes()).hexdigest()
    line = f"{digest}\t{installed}"
    if line not in history:
        new_lines.append(line)

if new_lines:
    if not history.endswith("\n"):
        history += "\n"
    history += "# 2026-08-27 clipboard wildcard search and runtime warning cleanup.\n"
    history += "\n".join(new_lines) + "\n"
    history_path.write_text(history)
