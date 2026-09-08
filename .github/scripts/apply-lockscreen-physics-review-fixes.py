#!/usr/bin/env python3
from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    target = Path(path)
    text = target.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one replacement target, found {count}")
    target.write_text(text.replace(old, new, 1), encoding="utf-8")


surface = "config/quickshell/awtarchy-lock/LockSurface.qml"
state = "config/hypr/scripts/quickshell_application_state.sh"

replace_once(
    surface,
    '''        const dx = hasPrevious ? x - lastPointerX : 0;
        const dy = hasPrevious ? y - lastPointerY : 0;
        const distance = Math.sqrt(dx * dx + dy * dy);
        const elapsed = hasPrevious ? Math.max(1, now - lastPointerSampleTime) : 1;
        const speed = hasPrevious ? distance * 1000 / elapsed : 0;

        if (!hasPrevious || distance >= pointerMovementThreshold)
            pushGhostSample(x, y);
''',
    '''        const dx = hasPrevious ? x - lastPointerX : 0;
        const dy = hasPrevious ? y - lastPointerY : 0;
        const distance = Math.sqrt(dx * dx + dy * dy);
        const elapsed = hasPrevious ? Math.max(1, now - lastPointerSampleTime) : 1;
        const speed = hasPrevious ? distance * 1000 / elapsed : 0;
        const ghostDx = x - ghostHeadX;
        const ghostDy = y - ghostHeadY;
        const ghostDistance = Math.sqrt(ghostDx * ghostDx + ghostDy * ghostDy);

        if (!hasPrevious || ghostOpacity <= 0 || ghostDistance >= pointerMovementThreshold)
            pushGhostSample(x, y);
''')

replace_once(
    surface,
    '''                                readonly property real audioOffsetY: audioEnvelope <= 0 ? 0
                                    : Math.max(-root.audioDisplacementCap,
                                        Math.min(root.audioDisplacementCap,
                                            Math.cos(root.audioPhase * (0.82 + randomD * 0.50) + audioAngle)
                                                * audioEnvelope * root.audioDisplacementCap * 0.82))
''',
    '''                                readonly property real audioOffsetY: audioEnvelope <= 0 ? 0
                                    : Math.max(-root.audioDisplacementCap,
                                        Math.min(root.audioDisplacementCap,
                                            Math.cos(root.audioPhase * (0.82 + randomD * 0.50) + audioAngle)
                                                * audioEnvelope * root.audioDisplacementCap * 0.82))
                                readonly property real combinedOffsetX: Math.max(
                                    -root.pointerDisplacementCap,
                                    Math.min(root.pointerDisplacementCap,
                                        pointerOffsetX + audioOffsetX))
                                readonly property real combinedOffsetY: Math.max(
                                    -root.pointerDisplacementCap,
                                    Math.min(root.pointerDisplacementCap,
                                        pointerOffsetY + audioOffsetY))
''')

replace_once(
    surface,
    '''                                    + Math.sin(Math.PI * wordmarkCell.formationProgress) * curveX
                                    + pointerOffsetX + audioOffsetX
                                y: (1 - formationProgress) * startY
                                    + Math.sin(Math.PI * wordmarkCell.formationProgress) * curveY
                                    + pointerOffsetY + audioOffsetY
''',
    '''                                    + Math.sin(Math.PI * wordmarkCell.formationProgress) * curveX
                                    + combinedOffsetX
                                y: (1 - formationProgress) * startY
                                    + Math.sin(Math.PI * wordmarkCell.formationProgress) * curveY
                                    + combinedOffsetY
''')

replace_once(
    state,
    '''    jq --arg field "$field" --argjson enabled "$enabled" '.[$field] = $enabled'         "$STATE_FILE" >"$TMP_FILE"
''',
    '''    jq --arg field "$field" --argjson enabled "$enabled" '.[$field] = $enabled' \\
        "$STATE_FILE" >"$TMP_FILE"
''')

print("Applied lockscreen physics review fixes")
