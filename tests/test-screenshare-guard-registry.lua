local module_path = assert(arg[1], "Screen Share Guard module path is required")

local created = {}
local events = {}
local dispatched = {}
local opened_window = {
    address = "0xabc",
    class = "signal",
    initial_class = "signal",
    title = "Signal",
    initial_title = "Signal",
}
local protected_window = {
    address = "0xdef",
    class = "localsend",
    initial_class = "localsend",
    title = "LocalSend",
    initial_title = "LocalSend",
}

hl = {
    window_rule = function(spec)
        local handle = { spec = spec, enabled = true }
        function handle:set_enabled(value)
            self.enabled = value == true
        end
        function handle:is_enabled()
            return self.enabled
        end
        created[#created + 1] = handle
        return handle
    end,
    layer_rule = function(spec)
        local handle = { spec = spec, enabled = true }
        function handle:set_enabled(value)
            self.enabled = value == true
        end
        function handle:is_enabled()
            return self.enabled
        end
        created[#created + 1] = handle
        return handle
    end,
    on = function(name, callback)
        events[name] = callback
        return { remove = function() end }
    end,
    exec_cmd = function() end,
    get_windows = function(match)
        if match.class == "^(signal|org\\.signal\\.Signal)$" then
            return { opened_window }
        end
        if match.class == "^(localsend|LocalSend|org\\.localsend\\.localsend|io\\.github\\.localsend\\.localsend)$" then
            return { protected_window }
        end
        return {}
    end,
    dispatch = function(action)
        dispatched[#dispatched + 1] = action
    end,
    dsp = {
        window = {
            set_prop = function(spec)
                return spec
            end,
        },
    },
}

local guard = dofile(module_path)

assert(type(guard.register) == "function", "Screen Share Guard does not expose custom registration")
assert(type(guard.registry) == "function", "Screen Share Guard does not expose runtime registry metadata")
assert(type(_G.awtarchy_screenshare_guard_register_v1) == "function",
    "Screen Share Guard module does not publish custom registration to hyprland.lua")
assert(type(_G.awtarchy_screenshare_guard_registry_v1) == "function",
    "Screen Share Guard module does not publish runtime registry metadata")

local before = #created
awtarchy_screenshare_guard_register_v1({
    id = "signal",
    label = "Signal",
    section = "protected",
    default_protected = true,
    match = { class = "^(signal|org\\.signal\\.Signal)$" },
})
assert(#created == before + 1, "custom registration did not create exactly one named window rule")
assert(created[#created].spec.name == "awtarchy-screenshare-user-signal-v1", "custom rule name is not stable")
assert(created[#created].spec.no_screen_share == true, "custom registration did not create a no_screen_share rule")
assert(created[#created].enabled == true, "custom protected target did not start enabled")

local registry = awtarchy_screenshare_guard_registry_v1()
assert(registry:find("signal\tSignal\tprotected\ttrue\t^(signal|org\\.signal\\.Signal)$\t", 1, true),
    "runtime registry does not expose custom target metadata")

assert(guard.set_group("signal", false) == true, "custom target could not be toggled")
assert(created[#created].enabled == false, "custom target rule handle remained enabled")
assert(guard.status():find("signal=false", 1, true), "custom target status did not follow the rule handle")

assert(type(events["window.open"]) == "function",
    "Screen Share Guard does not reapply disabled state after window rules run on a new window")
events["window.open"](opened_window)
assert(#dispatched == 1, "new matching window did not receive exactly one Screen Share Guard property correction")
assert(dispatched[1].prop == "no_screen_share", "new-window correction changed the wrong property")
assert(dispatched[1].value == "false", "new window did not inherit the disabled Screen Share Guard state")
assert(dispatched[1].window == opened_window, "new-window correction did not target the opened window")

events["window.open"](protected_window)
assert(#dispatched == 2, "protected new window did not receive exactly one Screen Share Guard property correction")
assert(dispatched[2].prop == "no_screen_share", "protected new-window correction changed the wrong property")
assert(dispatched[2].value == "true", "new window lost an enabled Screen Share Guard protection")
assert(dispatched[2].window == protected_window, "protected new-window correction did not target the opened window")

local duplicate_ok = pcall(function()
    awtarchy_screenshare_guard_register_v1({
        id = "signal",
        label = "Signal duplicate",
        section = "protected",
        default_protected = true,
        match = { class = "^(signal)$" },
    })
end)
assert(not duplicate_ok, "duplicate custom Screen Share Guard id was accepted")

local invalid_ok = pcall(function()
    awtarchy_screenshare_guard_register_v1({
        id = "bad id",
        label = "Invalid",
        section = "protected",
        default_protected = true,
        match = { class = "^(invalid)$" },
    })
end)
assert(not invalid_ok, "unsafe custom Screen Share Guard id was accepted")

print("Screen Share Guard runtime registry tests passed.")
