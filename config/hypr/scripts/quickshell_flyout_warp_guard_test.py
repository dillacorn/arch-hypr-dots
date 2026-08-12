#!/usr/bin/env python3
from __future__ import annotations

import shutil
import subprocess
from datetime import datetime
from pathlib import Path

TARGET = Path.home() / ".config/hypr/scripts/quickshell_runtime_rules.sh"
BACKUP_ROOT = Path.home() / ".local/state/awtarchy"
START_MARKER = "local function stop_awtarchy_flyout_cursor_restore()\n"
END_MARKER = "-- Dismiss on an actual outside left click, not merely because follow_mouse\n"

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

-- Remove the older click-armed implementation. The compatibility functions
-- remain because the non-consuming outside-click bind may still call them.
stop_awtarchy_flyout_cursor_restore()

local function arm_awtarchy_flyout_cursor_restore(_target_monitor, _cursor)
    -- v2 is continuously armed by cursor/flyout state instead.
end

local function awtarchy_flyout_signature_v2(flyouts)
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

local function awtarchy_flyout_on_monitor_v2(flyouts, monitor_name)
    monitor_name = tostring(monitor_name or "")

    if monitor_name == "" then
        return false
    end

    for _, entry in ipairs(flyouts) do
        local window = entry.window
        local monitor = window ~= nil and window.monitor or nil
        if monitor ~= nil and tostring(monitor.name or "") == monitor_name then
            return true
        end
    end

    return false
end

local function awtarchy_monitor_center_v2(monitor)
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

    width = width / scale
    height = height / scale

    return x + width / 2, y + height / 2
end

local function awtarchy_cursor_near_center_v2(cursor, monitor)
    if cursor == nil or monitor == nil then
        return false
    end

    local center_x, center_y = awtarchy_monitor_center_v2(monitor)

    if center_x ~= nil and center_y ~= nil
        and math.abs(cursor.x - center_x) <= 24
        and math.abs(cursor.y - center_y) <= 24 then
        return true
    end

    local monitor_name = tostring(monitor.name or "")

    for _, window in ipairs(hl.get_windows()) do
        local window_monitor = window.monitor

        if window.visible == true
            and window_monitor ~= nil
            and tostring(window_monitor.name or "") == monitor_name then

            local at = window.at
            local size = window.size

            if at ~= nil and size ~= nil then
                local x = tonumber(at.x)
                local y = tonumber(at.y)
                local width = tonumber(size.x)
                local height = tonumber(size.y)

                if x ~= nil and y ~= nil
                    and width ~= nil and height ~= nil
                    and width > 0 and height > 0 then

                    local wx = x + width / 2
                    local wy = y + height / 2

                    if math.abs(cursor.x - wx) <= 24
                        and math.abs(cursor.y - wy) <= 24 then
                        return true
                    end
                end
            end
        end
    end

    return false
end

local function awtarchy_cancel_warp_filter_v2()
    if awtarchy_flyout_warp_filter_timer_v2 ~= nil then
        pcall(function()
            awtarchy_flyout_warp_filter_timer_v2:set_enabled(false)
        end)
        pcall(function()
            awtarchy_flyout_warp_filter_timer_v2:cancel()
        end)
        awtarchy_flyout_warp_filter_timer_v2 = nil
    end
end

awtarchy_cancel_warp_filter_v2()

awtarchy_flyout_warp_filter_state_v2 = {
    last_x = nil,
    last_y = nil,
    recent_bar = nil,
    last_flyout_signature = "",
    flyout_activity_age = 9999,
    pending = nil,
}

awtarchy_flyout_warp_filter_timer_v2 = hl.timer(function()
    local state = awtarchy_flyout_warp_filter_state_v2
    local cursor = hl.get_cursor_pos()

    if state == nil or cursor == nil then
        return
    end

    local flyouts = visible_awtarchy_flyouts()
    local signature = awtarchy_flyout_signature_v2(flyouts)

    if signature ~= state.last_flyout_signature then
        state.last_flyout_signature = signature
        state.flyout_activity_age = 0
    else
        state.flyout_activity_age = state.flyout_activity_age + 1
    end

    local bar = awtarchy_bar_under_pointer()

    if bar ~= nil then
        state.recent_bar = {
            x = cursor.x,
            y = cursor.y,
            age = 0,
        }
    elseif state.recent_bar ~= nil then
        state.recent_bar.age = state.recent_bar.age + 1
        if state.recent_bar.age > 12 then
            state.recent_bar = nil
        end
    end

    if state.pending ~= nil then
        state.pending.age = state.pending.age + 1

        local moved_from_landing = math.sqrt(
            (cursor.x - state.pending.landed_x) ^ 2
            + (cursor.y - state.pending.landed_y) ^ 2
        )

        if moved_from_landing > 80 or state.pending.age > 12 then
            state.pending = nil
        elseif state.flyout_activity_age <= 10
            and awtarchy_flyout_on_monitor_v2(
                flyouts,
                state.pending.destination_monitor
            ) then

            hl.dispatch(hl.dsp.cursor.move({
                x = state.pending.restore_x,
                y = state.pending.restore_y,
            }))

            state.pending = nil
            state.recent_bar = nil
            state.last_x = cursor.x
            state.last_y = cursor.y
            return
        end
    end

    if state.last_x ~= nil
        and state.last_y ~= nil
        and state.recent_bar ~= nil then

        local step_distance = math.sqrt(
            (cursor.x - state.last_x) ^ 2
            + (cursor.y - state.last_y) ^ 2
        )

        local last_to_bar = math.sqrt(
            (state.last_x - state.recent_bar.x) ^ 2
            + (state.last_y - state.recent_bar.y) ^ 2
        )

        if step_distance >= 240
            and state.recent_bar.age <= 6
            and last_to_bar <= 96 then

            local destination = hl.get_monitor_at_cursor()

            if destination ~= nil
                and awtarchy_cursor_near_center_v2(cursor, destination) then

                local destination_name = tostring(destination.name or "")

                if state.flyout_activity_age <= 10
                    and awtarchy_flyout_on_monitor_v2(
                        flyouts,
                        destination_name
                    ) then

                    hl.dispatch(hl.dsp.cursor.move({
                        x = state.recent_bar.x,
                        y = state.recent_bar.y,
                    }))

                    state.recent_bar = nil
                    state.last_x = cursor.x
                    state.last_y = cursor.y
                    return
                end

                -- The compositor can warp before the new native flyout is
                -- visible to Lua. Keep this candidate for less than 100 ms
                -- and restore only if a flyout actually arrives there.
                state.pending = {
                    restore_x = state.recent_bar.x,
                    restore_y = state.recent_bar.y,
                    landed_x = cursor.x,
                    landed_y = cursor.y,
                    destination_monitor = destination_name,
                    age = 0,
                }
            end
        end
    end

    state.last_x = cursor.x
    state.last_y = cursor.y
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


def main() -> int:
    if not TARGET.is_file():
        raise SystemExit(f"ERROR: missing live runtime script: {TARGET}")

    text = TARGET.read_text(encoding="utf-8")

    if "awtarchy_flyout_warp_filter_timer_v2" in text:
        result = run(str(TARGET), check=False)
        print(result.stdout, end="")
        if result.returncode != 0:
            raise SystemExit(
                f"ERROR: existing v2 filter failed to apply: exit {result.returncode}"
            )
        print("Flyout warp filter v2 is already installed and was reapplied.")
        return 0

    start = text.find(START_MARKER)
    end = text.find(END_MARKER, start if start >= 0 else 0)

    if start < 0:
        raise SystemExit("ERROR: old flyout cursor guard start marker not found")
    if end < 0 or end <= start:
        raise SystemExit("ERROR: old flyout cursor guard end marker not found")

    if "'" in REPLACEMENT:
        raise SystemExit("ERROR: replacement contains a single quote")

    updated = text[:start] + REPLACEMENT + text[end:]

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    BACKUP_ROOT.mkdir(parents=True, exist_ok=True)
    backup = BACKUP_ROOT / f"quickshell-runtime-before-warp-filter-v2-{stamp}.backup"
    shutil.copy2(TARGET, backup)

    TARGET.write_text(updated, encoding="utf-8")

    try:
        syntax = run("bash", "-n", str(TARGET), check=False)
        if syntax.returncode != 0:
            raise RuntimeError(f"bash -n failed:\n{syntax.stdout}")

        applied = run(str(TARGET), check=False)
        if applied.returncode != 0:
            raise RuntimeError(
                f"runtime-rule apply failed with exit {applied.returncode}:\n"
                f"{applied.stdout}"
            )
    except BaseException:
        shutil.copy2(backup, TARGET)
        run(str(TARGET), check=False)
        raise

    print("PASS: installed shared flyout warp filter v2")
    print(f"Backup: {backup}")
    print("Normal cursor:no_warps remains unchanged.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
