local module_path = assert(arg[1], "Screen Share Guard module path is required")

local created = {}

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
    on = function() end,
    exec_cmd = function() end,
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
