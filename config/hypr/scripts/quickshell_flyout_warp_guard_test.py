#!/usr/bin/env python3
from __future__ import annotations

import shutil
import subprocess
from datetime import datetime
from pathlib import Path

RUNTIME = Path.home() / ".config/hypr/scripts/quickshell_runtime_rules.sh"
PREPARE = Path.home() / ".config/hypr/scripts/quickshell_flyout_prepare.sh"
BACKUP_ROOT = Path.home() / ".local/state/awtarchy"

START_MARKER = "local function stop_awtarchy_flyout_cursor_restore()\n"
END_MARKER = "-- Dismiss on an actual outside left click, not merely because follow_mouse\n"

PREPARE_NEEDLE = 'lua="awtarchy_prepared_flyout_rules_v1'
PREPARE_REPLACEMENT = (
    'lua="if awtarchy_arm_flyout_warp_guard_v3 ~= nil then '
    "awtarchy_arm_flyout_warp_guard_v3('$surface', '$monitor') end; "
    "awtarchy_prepared_flyout_rules_v1"
)

REPLACEMENT = r"""local function stop_awtarchy_flyout_cursor_restore()
    if awtarchy_flyout_cursor_restore_timer_v1 ~= nil then
        pcall(function()
            awtarchy_flyout_cursor_restore_timer_v1:set_enabled(false)
        end)
        pcall(function()
            awtarchy_flyout_cursor_restore_timer_v1:cancel()
        end)
        awtarchy_flyout_cursor_restore_timer_v1 = nil
    end

    awtarchy_flyout_cursor_restore_state_v1 = nil
end

stop_awtarchy_flyout_cursor_restore()

if awtarchy_flyout_warp_filter_timer_v2 ~= nil then
    pcall(function()
        awtarchy_flyout_warp_filter_timer_v2:set_enabled(false)
    end)
    pcall(function()
        awtarchy_flyout_warp_filter_timer_v2:cancel()
    end)
    awtarchy_flyout_warp_filter_timer_v2 = nil
end

if awtarchy_flyout_warp_guard_timer_v3 ~= nil then
    pcall(function()
        awtarchy_flyout_warp_guard_timer_v3:set_enabled(false)
    end)
    pcall(function()
        awtarchy_flyout_warp_guard_timer_v3:cancel()
    end)
    awtarchy_flyout_warp_guard_timer_v3 = nil
end

local awtarchy_flyout_titles_v3 = {
    launcher = "Awtarchy Application Search",
    clipboard = "Awtarchy Clipboard History",
    notifications = "Awtarchy Notification Center",
    ["quick-settings"] = "Awtarchy Quick Settings",
    network = "Awtarchy Network",
    bluetooth = "Awtarchy Bluetooth",
}

local function awtarchy_flyout_signature_v3(flyouts)
    local parts = {}

    for _, entry in ipairs(flyouts) do
        local window = entry.window
        if window ~= nil then
            local monitor = window.monitor
            local monitor_name = monitor ~= nil
                and tostring(monitor.name or "") or ""
            local address = tostring(window.address or "")
            local title = tostring(window.title or "")

            table.insert(parts, title .. "|" .. address .. "|" .. monitor_name)
        end
    end

    table.sort(parts)
    return table.concat(parts, ";")
end

local function awtarchy_target_flyout_present_v3(flyouts, surface, monitor_name)
    local expected_title = awtarchy_flyout_titles_v3[tostring(surface or "")]
    monitor_name = tostring(monitor_name or "")

    if expected_title == nil or monitor_name == "" then
        return false
    end

    for _, entry in ipairs(flyouts) do
        local window = entry.window
        local monitor = window ~= nil and window.monitor or nil

        if window ~= nil
            and tostring(window.title or "") == expected_title
            and monitor ~= nil
            and tostring(monitor.name or "") == monitor_name then
            return true
        end
    end

    return false
end

local function awtarchy_monitor_center_v3(monitor)
    if monitor == nil then
        return nil, nil
    end

    local x = tonumber(monitor.x)
    local y = tonumber(monitor.y)
    local width = tonumber(monitor.width)
    local height = tonumber(monitor.height)
    local scale = tonumber(monitor.scale) or 1
    local transform = tonumber(monitor.transform) or 0

    if x == nil or y == nil or width == nil or height == nil or scale <= 0 then
        return nil, nil
    end

    if transform % 2 == 1 then
        width, height = height, width
    end

    return x + width / scale / 2, y + height / scale / 2
end

local function awtarchy_cursor_near_compositor_center_v3(cursor)
    if cursor == nil then
        return false
    end

    local monitor = hl.get_monitor_at_cursor()
    local center_x, center_y = awtarchy_monitor_center_v3(monitor)

    if center_x ~= nil and center_y ~= nil
        and math.abs(cursor.x - center_x) <= 28
        and math.abs(cursor.y - center_y) <= 28 then
        return true
    end

    for _, window in ipairs(hl.get_windows()) do
        if window.visible == true and window.at ~= nil and window.size ~= nil then
            local x = tonumber(window.at.x)
            local y = tonumber(window.at.y)
            local width = tonumber(window.size.x)
            local height = tonumber(window.size.y)

            if x ~= nil and y ~= nil and width ~= nil and height ~= nil
                and width > 0 and height > 0 then

                local wx = x + width / 2
                local wy = y + height / 2

                if math.abs(cursor.x - wx) <= 28
                    and math.abs(cursor.y - wy) <= 28 then
                    return true
                end
            end
        end
    end

    return false
end

awtarchy_flyout_warp_guard_tracker_v3 = {
    last_x = nil,
    last_y = nil,
}

awtarchy_flyout_warp_guard_state_v3 = nil

function awtarchy_arm_flyout_warp_guard_v3(surface, target_monitor)
    local cursor = hl.get_cursor_pos()
    surface = tostring(surface or "")
    target_monitor = tostring(target_monitor or "")

    if cursor == nil
        or awtarchy_flyout_titles_v3[surface] == nil
        or target_monitor == "" then
        awtarchy_flyout_warp_guard_state_v3 = nil
        return
    end

    local flyouts = visible_awtarchy_flyouts()

    awtarchy_flyout_warp_guard_state_v3 = {
        surface = surface,
        target_monitor = target_monitor,
        restore_x = cursor.x,
        restore_y = cursor.y,
        age = 0,
        signature_at_arm = awtarchy_flyout_signature_v3(flyouts),
        pending = nil,
    }
end

local function arm_awtarchy_flyout_cursor_restore(_target_monitor, _cursor)
    -- Compatibility shim. v3 is armed only by quickshell_flyout_prepare.sh,
    -- which means workspace/bar clicks never arm the filter.
end

local function awtarchy_restore_flyout_cursor_v3(state, tracker)
    hl.dispatch(hl.dsp.cursor.move({
        x = state.restore_x,
        y = state.restore_y,
    }))

    awtarchy_flyout_warp_guard_state_v3 = nil
    tracker.last_x = nil
    tracker.last_y = nil
end

awtarchy_flyout_warp_guard_timer_v3 = hl.timer(function()
    local tracker = awtarchy_flyout_warp_guard_tracker_v3
    local cursor = hl.get_cursor_pos()

    if tracker == nil or cursor == nil then
        return
    end

    local state = awtarchy_flyout_warp_guard_state_v3
    local flyouts = visible_awtarchy_flyouts()
    local signature = awtarchy_flyout_signature_v3(flyouts)

    if state ~= nil then
        state.age = state.age + 1

        local target_present = awtarchy_target_flyout_present_v3(
            flyouts,
            state.surface,
            state.target_monitor
        )
        local lifecycle_changed = signature ~= state.signature_at_arm

        if state.pending ~= nil then
            state.pending.age = state.pending.age + 1

            local moved_from_landing = math.sqrt(
                (cursor.x - state.pending.landed_x) ^ 2
                + (cursor.y - state.pending.landed_y) ^ 2
            )

            if target_present or lifecycle_changed then
                if moved_from_landing <= 180 then
                    awtarchy_restore_flyout_cursor_v3(state, tracker)
                    return
                end

                state.pending = nil
            elseif state.pending.age > 150 then
                state.pending = nil
            end
        end

        if tracker.last_x ~= nil and tracker.last_y ~= nil then
            local step_distance = math.sqrt(
                (cursor.x - tracker.last_x) ^ 2
                + (cursor.y - tracker.last_y) ^ 2
            )

            local origin_distance = math.sqrt(
                (tracker.last_x - state.restore_x) ^ 2
                + (tracker.last_y - state.restore_y) ^ 2
            )

            if step_distance >= 240
                and origin_distance <= 220
                and awtarchy_cursor_near_compositor_center_v3(cursor) then

                local destination = hl.get_monitor_at_cursor()
                local destination_name = destination ~= nil
                    and tostring(destination.name or "") or ""

                if target_present
                    or lifecycle_changed
                    or destination_name == state.target_monitor then

                    if target_present or lifecycle_changed then
                        awtarchy_restore_flyout_cursor_v3(state, tracker)
                        return
                    end

                    state.pending = {
                        landed_x = cursor.x,
                        landed_y = cursor.y,
                        age = 0,
                    }
                end
            end
        end

        -- 2.4 seconds is intentionally much longer than v2s 96 ms window.
        -- Every real flyout open/transfer re-arms this state from prepare.sh.
        if state.age > 300 then
            awtarchy_flyout_warp_guard_state_v3 = nil
        end
    end

    tracker.last_x = cursor.x
    tracker.last_y = cursor.y
end, {
    timeout = 8,
    type = "repeat",
})

"""


def run(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        list(args),
        check=check,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )


def patch_runtime(text: str) -> str:
    start = text.find(START_MARKER)
    end = text.find(END_MARKER, start if start >= 0 else 0)

    if start < 0:
        raise RuntimeError("runtime cursor-guard start marker not found")
    if end < 0 or end <= start:
        raise RuntimeError("runtime cursor-guard end marker not found")
    if "'" in REPLACEMENT:
        raise RuntimeError("runtime replacement contains a single quote")

    return text[:start] + REPLACEMENT + text[end:]


def patch_prepare(text: str) -> str:
    if "awtarchy_arm_flyout_warp_guard_v3" in text:
        return text

    if text.count(PREPARE_NEEDLE) != 1:
        raise RuntimeError(
            f"expected one prepare Lua marker, found {text.count(PREPARE_NEEDLE)}"
        )

    return text.replace(PREPARE_NEEDLE, PREPARE_REPLACEMENT, 1)


def main() -> int:
    for path in (RUNTIME, PREPARE):
        if not path.is_file():
            raise SystemExit(f"ERROR: missing live file: {path}")

    runtime_before = RUNTIME.read_text(encoding="utf-8")
    prepare_before = PREPARE.read_text(encoding="utf-8")

    if (
        "awtarchy_flyout_warp_guard_timer_v3" in runtime_before
        and "awtarchy_arm_flyout_warp_guard_v3" in prepare_before
    ):
        result = run(str(RUNTIME), check=False)
        print(result.stdout, end="")
        if result.returncode != 0:
            raise SystemExit(
                f"ERROR: existing v3 guard failed to apply: exit {result.returncode}"
            )
        print("Flyout warp guard v3 is already installed and was reapplied.")
        return 0

    runtime_after = patch_runtime(runtime_before)
    prepare_after = patch_prepare(prepare_before)

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup_dir = BACKUP_ROOT / f"quickshell-warp-guard-v3-{stamp}"
    backup_dir.mkdir(parents=True, exist_ok=False)

    runtime_backup = backup_dir / RUNTIME.name
    prepare_backup = backup_dir / PREPARE.name
    shutil.copy2(RUNTIME, runtime_backup)
    shutil.copy2(PREPARE, prepare_backup)

    RUNTIME.write_text(runtime_after, encoding="utf-8")
    PREPARE.write_text(prepare_after, encoding="utf-8")

    try:
        for path in (RUNTIME, PREPARE):
            syntax = run("bash", "-n", str(path), check=False)
            if syntax.returncode != 0:
                raise RuntimeError(f"bash -n failed for {path}:\n{syntax.stdout}")

        applied = run(str(RUNTIME), check=False)
        if applied.returncode != 0:
            raise RuntimeError(
                f"runtime-rule apply failed with exit {applied.returncode}:\n"
                f"{applied.stdout}"
            )
    except BaseException:
        shutil.copy2(runtime_backup, RUNTIME)
        shutil.copy2(prepare_backup, PREPARE)
        run(str(RUNTIME), check=False)
        raise

    print("PASS: installed durable flyout warp guard v3")
    print(f"Backup: {backup_dir}")
    print("Normal cursor:no_warps remains unchanged.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
