--  ▄▄▄       █     █░▄▄▄█████▓ ▄▄▄       ██▀███   ▄████▄   ██░ ██▓██   ██▓
-- ▒████▄    ▓█░ █ ░█░▓  ██▒ ▓▒▒████▄    ▓██ ▒ ██▒▒██▀ ▀█  ▓██░ ██▒▒██  ██▒
-- ▒██  ▀█▄  ▒█░ █ ░█ ▒ ▓██░ ▒░▒██  ▀█▄  ▓██ ░▄█ ▒▒▓█    ▄ ▒██▀▀██░ ▒██ ██░
-- ░██▄▄▄▄██ ░█░ █ ░█ ░ ▓██▓ ░ ░██▄▄▄▄██ ▒██▀▀█▄  ▒▓▓▄ ▄██▒░▓█ ░██  ░ ▐██▓░
--  ▓█   ▓██▒░░██▒██▓   ▒██▒ ░  ▓█   ▓██▒░██▓ ▒██▒▒ ▓███▀ ░░▓█▒░██▓ ░ ██▒▓░
--  ▒▒   ▓▒█░░ ▓░▒ ▒    ▒ ░░    ▒▒   ▓▒█░░ ▒▓ ░▒▓░░ ░▒ ▒  ░ ▒ ░░▒░▒  ██▒▒▒
--   ▒   ▒▒ ░  ▒ ░ ░      ░      ▒   ▒▒ ░  ░▒ ░ ▒░  ░  ▒    ▒ ░▒░ ░▓██ ░▒░
--   ░   ▒     ░   ░    ░        ░   ▒     ░░   ░ ░         ░  ░░ ░▒ ▒ ░░
--       ░  ░    ░                   ░  ░   ░     ░ ░       ░  ░  ░░ ░
--                                                 ░                ░ ░

-- github.com/dillacorn/awtarchy/tree/main/config/hypr

-- ───────────────────────────────────────────────────────────────────────────────
-- MONITORS
-- ───────────────────────────────────────────────────────────────────────────────

-- list displays: hyprctl monitors
-- example syntax: monitor=(name),(resolution@refresh),(position_0x0),(scale),(vrr,1/0 = enable/disable VRR)
-- disable display example syntax: monitor=(name),disable

hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto", vrr = 0 })
hl.monitor({ output = "Virtual-1", mode = "1600x900@60", position = "auto", scale = 1, vrr = 0 })

-- ───────────────────────────────────────────────────────────────────────────────
-- ENV
-- ───────────────────────────────────────────────────────────────────────────────

hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("CLUTTER_BACKEND", "wayland")
hl.env("QT_STYLE_OVERRIDE", "kvantum")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("QT_QPA_PLATFORMTHEME", "qt5ct")
hl.env("QT6CT_PLATFORM_PLUGIN", "qt6ct")
hl.env("QT_QUICK_CONTROLS_STYLE", "org.hyprland.style")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("GDK_SCALE", "1")
hl.env("QT_SCALE_FACTOR", "1")
hl.env("XCURSOR_SIZE", "24")
hl.env("GTK_THEME", "Materia-dark")
hl.env("XCURSOR_THEME", "ComixCursors-White")
hl.env("GAMESCOPE_WSI", "vk_wayland")

-- Optional/problem-specific environment toggles.
-- hl.env("WLR_RENDERER_ALLOW_SOFTWARE", "0")
-- hl.env("WLR_DRM_NO_ATOMIC", "1") -- Old wlroots-era workaround; do not use on current Hyprland unless you know you need it.
-- hl.env("HYPRLAND_NO_RT", "1") -- Disable realtime scheduling if having issues
-- hl.env("__GL_GSYNC_ALLOWED", "1") -- Optional NVIDIA VRR/G-Sync toggle
-- hl.env("__GL_VRR_ALLOWED", "0") -- Optional NVIDIA Adaptive Sync toggle; 0 is safer for some games

-- NVIDIA/proprietary-driver-specific toggles.
-- hl.env("GBM_BACKEND", "nvidia-drm") -- NVIDIA GBM backend
-- hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia") -- NVIDIA GLX vendor
-- hl.env("LIBVA_DRIVER_NAME", "nvidia") -- NVIDIA VA-API driver
-- hl.env("NVD_BACKEND", "direct") -- Optional: enable only with libva-nvidia-driver / libva-nvidia-driver installed

-- ───────────────────────────────────────────────────────────────────────────────
-- PERMISSIONS (requires Hyprland restart after edits)
-- ───────────────────────────────────────────────────────────────────────────────

-- Add future apps (getting the correct path/regex):
-- 1) Best: when Hyprland prompts, copy the binary path it shows and paste it into:
--
-- 2) If you know the command name (replace `grim` with your app):
--    readlink -f "$(command -v grim)"
--
-- 3) If the app has a window open: focus it, then run:
--
-- Keyboard device names (for `keyboard` rules):
--   hyprctl devices

hl.config({
    ecosystem = {
        no_update_news = true,
        enforce_permissions = true,
    },
})

-- screencopy (direct capture)
hl.permission("/usr/bin/grim", "screencopy", "allow")
hl.permission("/usr/bin/wf-recorder", "screencopy", "allow")
hl.permission("/usr/bin/hyprpicker", "screencopy", "allow")
hl.permission("/usr/bin/hyprlock", "screencopy", "allow")
hl.permission("/usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland", "screencopy", "allow")

-- plugin (hyprpm)
hl.permission("/usr/(bin|local/bin)/hyprpm", "plugin", "allow")

-- keyboard allowlist template (default is allow)
-- hl.permission("^(YOUR KEYBOARD NAME REGEX)$", "keyboard", "allow")
-- hl.permission(".*", "keyboard", "deny")

-- ───────────────────────────────────────────────────────────────────────────────
-- AUTOSTART
-- ───────────────────────────────────────────────────────────────────────────────

hl.on("hyprland.start", function()
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE XDG_SESSION_TYPE")
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE XDG_SESSION_TYPE")

    hl.exec_cmd("sh -lc '$HOME/.config/hypr/scripts/portal_fixup.sh'")
    hl.exec_cmd("/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1")
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")

    -- hl.exec_cmd("~/.config/hypr/scripts/last_to_load_recorder.sh &")
    hl.exec_cmd("~/.config/hypr/scripts/quickshell.sh start &")
    hl.exec_cmd("~/.config/hypr/scripts/quickshell_ready_sound.sh &")

    hl.exec_cmd("hyprsunset &")
    hl.exec_cmd("nwg-look -a &")
    hl.exec_cmd("hypridle -c ~/.config/hypr/hypridle.conf &")
    hl.exec_cmd("~/.config/hypr/scripts/hyprpm-auto-reload.sh &")
    hl.exec_cmd("~/.config/hypr/scripts/awtwall-awtarchy-init.sh &")
    -- hl.exec_cmd("~/.config/hypr/scripts/wallpaper_engine.sh &")
    hl.exec_cmd("sh -lc 'exec alacritty --class awtarchy-tips-tui,awtarchy-tips-tui --title awtarchy-tips-tui -e \"$HOME/.config/hypr/scripts/awtarchy-tips-tui.sh\" --autostart'")
    -- hl.exec_cmd("~/.config/hypr/scripts/miclock.sh &")
    hl.exec_cmd("wl-paste --type text --watch cliphist store &")
    hl.exec_cmd("wl-paste --type image --watch cliphist store &")

    -- Optional: USB refresh helper
    -- List USB devices:
    -- lsusb
    -- Map a device once:
    -- ~/.config/hypr/scripts/usb_refresh_fixer.sh map 20b1:3008 ifi
    --
    -- Then optionally run at startup:
    --
    -- Non-audio USB device:
    -- hl.exec_cmd("~/.config/hypr/scripts/usb_refresh_fixer.sh refresh myusb &")
    --
    -- USB audio device, just refresh it and wait for the audio sink to exist again:
    -- hl.exec_cmd("~/.config/hypr/scripts/usb_refresh_fixer.sh refresh-audio ifi &")
    --
    -- USB audio device, refresh it and force it as default sink:
    -- hl.exec_cmd("~/.config/hypr/scripts/usb_refresh_fixer.sh refresh-audio-default ifi &")
end)

-- ───────────────────────────────────────────────────────────────────────────────
-- LOOK & FEEL
-- ───────────────────────────────────────────────────────────────────────────────

hl.config({
    general = {
        gaps_in = 6,
        gaps_out = 9,
        border_size = 1,
        resize_on_border = true,
        allow_tearing = true,
        layout = "dwindle",

        col = {
            active_border = "rgba(a0a0a0ff)",
            inactive_border = "rgba(4b4b4bff)",
        },
    },

    decoration = {
        rounding = 0,
        rounding_power = 2,
        active_opacity = 1,
        inactive_opacity = 1,

        shadow = {
            enabled = true,
            range = 4,
            render_power = 3,
            color = "rgba(1a1a1aee)",
        },

        blur = {
            enabled = true,
            size = 3,
            passes = 1,
            vibrancy = 0.1696,
        },
    },

    debug = {
        damage_tracking = 2,
    },

    render = {
        -- Direct scanout: 0 = off, 1 = on, 2 = auto (only when content_type == "game")
        -- Reduces latency when a single fullscreen client (e.g. nested gamescope) owns the monitor.
        direct_scanout = 2,

        -- Non-shader color management:
        -- 2 is the “DS + passthrough only” mode, which pairs cleanly with gamescope.
        non_shader_cm = 2,

        -- Fullscreen HDR color-management auto-switch:
        -- cm_fs_passthrough was removed in Hyprland 0.55.
        cm_auto_hdr = 1,
    },

    cursor = {
        sync_gsettings_theme = true,
        no_hardware_cursors = 2,
        use_cpu_buffer = 2,
        zoom_disable_aa = true,
        no_warps = false,
        persistent_warps = false,
        warp_on_change_workspace = 0,
        enable_hyprcursor = true,
    },

    animations = {
        enabled = true,
    },

    dwindle = {
        preserve_split = true,
        force_split = 0,
        special_scale_factor = 0.9,
        -- smart_split = true,
        -- single_window_aspect_ratio = "1 0.6852",
    },

    master = {
        new_status = "master",
        new_on_top = 1,
        mfact = 0.5,
    },

    misc = {
        -- Visuals (startup / defaults)
        force_default_wallpaper = -1,
        disable_hyprland_logo = true,
        disable_splash_rendering = true,

        -- Rendering / display behavior
        vrr = 2,
        mouse_move_enables_dpms = true,

        -- Input convenience
        middle_click_paste = false,

        -- Focus / workspace behavior
        focus_on_activate = false,
        initial_workspace_tracking = 0,

        -- Swallowing (terminal -> spawned app)
        enable_swallow = false,
        swallow_regex = "^([Aa]lacritty)$",

        -- Stability / UX dialogs
        enable_anr_dialog = true,
        allow_session_lock_restore = true,

        -- Suppress helper warnings/checks
        disable_hyprland_guiutils_check = true,
    },

    xwayland = {
        enabled = true,
        force_zero_scaling = true,
    },
})

-- Shaders (uncomment only one)
-- hl.config({ decoration = { screen_shader = "/home/dillacorn/.config/hypr/shaders/vibrance" } })
-- hl.config({ decoration = { screen_shader = "~/.config/hypr/shaders/cathode_ray_tube_optional_vibrance" } })
-- hl.config({ decoration = { screen_shader = "~/.config/hypr/shaders/subtle_crt" } })
-- hl.config({ decoration = { screen_shader = "~/.config/hypr/shaders/gimmicky-crt" } })

-- Shaders that require debug damage_tracking = 0 or you will see config errors.
-- hl.config({ decoration = { screen_shader = "~/.config/hypr/shaders/vhs" } })
-- hl.config({ decoration = { screen_shader = "~/.config/hypr/shaders/acid_trip" } })

-- hl.config({
--     opengl = {
--         nvidia_anti_flicker = true,
--     },
-- })

hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.curve("easeInOutSlight", { type = "bezier", points = { { 0.4, 0.1 }, { 0.2, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.curve("softFade", { type = "bezier", points = { { 0.2, 0.5 }, { 0.3, 1 } } })
hl.curve("fastOut", { type = "bezier", points = { { 0.2, 0 }, { 0.6, 1 } } })

for _, animation in ipairs({
    { leaf = "global", enabled = 1, speed = 8, bezier = "default" },
    { leaf = "border", enabled = 1, speed = 3, bezier = "easeOutQuint" },
    { leaf = "borderangle", enabled = 1, speed = 40, bezier = "linear", style = "once" },
    { leaf = "windows", enabled = 1, speed = 3, bezier = "easeOutQuint" },
    { leaf = "windowsIn", enabled = 1, speed = 2, bezier = "easeOutQuint", style = "popin 87%" },
    { leaf = "windowsOut", enabled = 1, speed = 1.5, bezier = "linear", style = "popin 87%" },
    { leaf = "fadeIn", enabled = 1, speed = 1.5, bezier = "softFade" },
    { leaf = "fadeOut", enabled = 1, speed = 1.3, bezier = "softFade" },
    { leaf = "fade", enabled = 1, speed = 2, bezier = "softFade" },
    { leaf = "layers", enabled = 1, speed = 2.5, bezier = "easeInOutSlight" },
    { leaf = "layersIn", enabled = 1, speed = 2, bezier = "easeInOutSlight", style = "fade" },
    { leaf = "layersOut", enabled = 1, speed = 1.5, bezier = "fastOut", style = "fade" },
    { leaf = "fadeLayersIn", enabled = 1, speed = 1.4, bezier = "softFade" },
    { leaf = "fadeLayersOut", enabled = 1, speed = 1.3, bezier = "softFade" },
    { leaf = "workspaces", enabled = 1, speed = 1.8, bezier = "easeInOutSlight", style = "fade" },
    { leaf = "workspacesIn", enabled = 1, speed = 1.3, bezier = "softFade", style = "fade" },
    { leaf = "workspacesOut", enabled = 1, speed = 1.4, bezier = "softFade", style = "fade" },
    { leaf = "specialWorkspace", enabled = 1, speed = 1.9, bezier = "easeInOutSlight", style = "fade" },
}) do
    hl.animation(animation)
end

if hl.plugin and hl.plugin.hyprbars then
    hl.config({
        plugin = {
            hyprbars = {
                bar_height = 20,
                bar_color = "rgb(1e1e1e)",
                bar_blur = false,

                -- title text (optional)
                col = {
                    text = "rgb(d0d0d0)",
                },

                -- layout
                bar_title_enabled = true,
                bar_buttons_alignment = "right",
                bar_padding = 5,
                bar_button_padding = 7,
                bar_text_align = "left",
                bar_text_size = 10,
                bar_text_font = "NotoSansM Nerd Font Mono",
                on_double_click = "hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"toggle\" })'",
            },
        },
    })
end

-- buttons: same as bar background; icons are light gray
if hl.plugin and hl.plugin.hyprbars and hl.plugin.hyprbars.add_button then
    for _, button in ipairs({
        { bg_color = "rgb(1e1e1e)", fg_color = "rgb(d0d0d0)", size = 20, icon = "", action = "hyprctl dispatch 'hl.dsp.window.close()'" },
        { bg_color = "rgb(1e1e1e)", fg_color = "rgb(d0d0d0)", size = 20, icon = "󰨤", action = "hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = \"maximized\", action = \"toggle\" })'" },
        { bg_color = "rgb(1e1e1e)", fg_color = "rgb(d0d0d0)", size = 20, icon = "", action = "hyprctl dispatch 'hl.dsp.window.float({ action = \"toggle\" })'" },
    }) do
        hl.plugin.hyprbars.add_button(button)
    end
end

-- Quickshell application launcher: bar-aware floating search window.
hl.window_rule({
    name = "awtarchy-quickshell-launcher",
    match = { title = "Awtarchy Application Search" },
    float = true,
    border_size = 0,
    rounding = 0,
    decorate = false,
    no_shadow = true,
    no_follow_mouse = true,
})

-- ───────────────────────────────────────────────────────────────────────────────
-- INPUT
-- ───────────────────────────────────────────────────────────────────────────────
--
-- Mouse notes:
-- - maccel handles pointer movement/accel.
-- - Scroll-wheel behavior is separate from maccel.
-- - `emulate_discrete_scroll` is global, not per-mouse.
-- - Logitech high-resolution wheels may need Solaar's "Scroll Wheel Resolution" enabled.
-- - Get mouse names with:
--     hyprctl devices | sed -n '/^mice:/,/^keyboards:/p'

hl.config({
    input = {
        kb_layout = "us",
        follow_mouse = 1,
        repeat_delay = 250,
        repeat_rate = 35,
        numlock_by_default = true,

        touchpad = {
            natural_scroll = true,
            disable_while_typing = true,
            clickfinger_behavior = true,
            scroll_factor = 0.5,
        },

        -- No acceleration (1:1 raw input)
        accel_profile = "flat",
        sensitivity = 0,
        force_no_accel = 1,

        -- Scroll defaults
        scroll_factor = 1.0,

        -- High-resolution wheel handling:
        -- 1 = emulate normal discrete wheel steps from high-res scroll events
        -- 0 = pass smoother high-res scrolling through without discrete emulation
        emulate_discrete_scroll = 1,
    },
})

-- ───────────────────────────────────────────────────────────────────────────────
-- PER-MOUSE OVERRIDES
-- ───────────────────────────────────────────────────────────────────────────────
--
-- Optional per-mouse settings.
-- `emulate_discrete_scroll` is global and does not work here.

-- hl.device({
--     name = "logitech-g303-1",
--     scroll_factor = 5.0,
-- })

-- ──────────────────────────────────────────────────────────────
-- Game profiles @ 400 DPI w/ maccel
-- ──────────────────────────────────────────────────────────────

-- CS2 (Tactical - no accel)
-- Sens:                  1.62
-- eDPI:                  648
-- Style:                 Tac shooters where 180-degree flicks / rotations are not a priority.
-- maccel:                No Accel, SENS_MULT 0.40

-- The Finals (Arena - with accel)
-- Hardware DPI:          1600
-- Base sens:             35             -- eDPI: ~636
-- Fast sens:             47             -- eDPI: ~855
-- Accel ratio:           47/35 = 1.34   -- fast/base = OutputCap

-- maccel setup:
--   - Mode:              Linear
--   - SENS_MULT:         0.40
--   - Y/X Ratio:         1.00
--   - INPUT_DPI:         1600
--   - Angle Rotation:    0.0
--   - Accel:             1000
--   - Offset:            15
--   - OutputCap:         1.34

-- Stretched resolution Y/X ratio:
--   Use this when playing a non-16:9 resolution stretched to a 16:9 display.
--
--   maccel uses Y/X Ratio.
--   This multiplies vertical sensitivity relative to horizontal sensitivity.
--
--   Simple formula:
--     Y/X Ratio = display width / stretched resolution width
--
--   Common values:
--   - 16:9 native:       1.00     -- 1920x1080
--   - 16:10 stretched:   1.11     -- 1728x1080 stretched to 1920x1080
--   - 4:3 stretched:     1.33     -- 1440x1080 stretched to 1920x1080
--
--   4:3 stretched example:
--     1920 / 1440 = 1.33
--
--   16:10 stretched example:
--     1920 / 1728 = 1.11
--
--   This compensates for horizontal stretching so mouse movement feels closer
--   to native 16:9.

-- Angle Rotation:
--   Sensor rotation matters. Even a small tilted sensor or natural grip angle
--   can add unwanted Y movement during horizontal flicks.
--
--   Test:
--   - Open paint, Krita, GIMP, Xournal++, or any drawing app.
--   - Use the pencil/brush tool.
--   - Flick the mouse left/right in straight horizontal lines.
--   - Adjust Angle Rotation until the drawn flick lines are close to horizontal.
--   - Goal: near-zero Y lift/drop at both ends of the flick.

-- ──────────────────────────────────────────────────────────────
-- maccel setup guide
-- https://github.com/Gnarus-G/maccel
--
-- How to calculate your OutputCap: (value varies between all games)
-- 1. Play without accel - find your comfortable "fast" sens (e.g., 47)
-- 2. Find the "slow" sens you want for precision (e.g., 35)
-- 3. Calculate: OutputCap = fast_sens / slow_sens
--
-- Example:
--   47 / 35 = 1.34
--
-- Result:
--   Fast flicks    = 47 sens
--   Slow movements = 35 sens
--
-- Game example:
--   The Finals
--
-- ──────────────────────────────────────────────────────────────

-- ───────────────────────────────────────────────────────────────────────────────
-- GESTURES
-- ───────────────────────────────────────────────────────────────────────────────

-- See https://wiki.hypr.land/Configuring/Gestures
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })

-- ───────────────────────────────────────────────────────────────────────────────
-- MODIFIERS
-- ───────────────────────────────────────────────────────────────────────────────

local mod = "ALT"
local super = "SUPER"
local tempalt = "ALT"
local submap_file = "/tmp/hypr-submap"

-- ───────────────────────────────────────────────────────────────────────────────
-- LAUNCHERS / COMMANDS
-- ───────────────────────────────────────────────────────────────────────────────

-- Base paths (using variables instead of repeating ~/.config/hypr/scripts everywhere)
local hypr_dir = "~/.config/hypr"
local hypr_scripts = "~/.config/hypr/scripts"
local launch = "~/.config/hypr/scripts/launch_handler.sh"

-- Core apps (define before anything that uses them)
local terminal = "alacritty"
local web_browser = "firefox"
local calculator = "speedcrunch"
local yazi = "alacritty -e yazi"

-- App/menu launchers
local app_launcher = "~/.config/hypr/scripts/quickshell_launcher.sh"
local power_menu = "~/.config/hypr/scripts/quickshell_power_menu.sh"
local hypr_quicksettings = "~/.config/hypr/scripts/quickshell_quick_settings_toggle.sh"
local awtarchy_tips_tui = "~/.config/hypr/scripts/launch_handler.sh awtarchy-tips-tui \"alacritty --class awtarchy-tips-tui -e ~/.config/hypr/scripts/awtarchy-tips-tui.sh\""

-- Audio
local wiremix = "~/.config/hypr/scripts/launch_handler.sh wiremix \"alacritty --class Wiremix -e wiremix\""
local pavucontrol = "~/.config/hypr/scripts/launch_handler.sh pavucontrol \"pavucontrol\""
local pulsemixer = "~/.config/hypr/scripts/launch_handler.sh pulsemixer \"alacritty --class Pulsemixer -e pulsemixer\""
local mute_unmute = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
local play_pause = "~/.config/hypr/scripts/play_pause.sh"

-- Bars / UI toggles
local hyprbars_toggle = "~/.config/hypr/scripts/hyprbars_toggle.sh"
local bar_toggle = "~/.config/hypr/scripts/quickshell_bar_toggle.sh"
local bar_flip = "~/.config/hypr/scripts/quickshell_bar_flip.sh"
local bar_rotate = "~/.config/hypr/scripts/quickshell_bar_rotate.sh"
local toggle_animations = "~/.config/hypr/scripts/toggle_animations.sh"
local notification_dismiss = "~/.config/hypr/scripts/quickshell_notification_dismiss.sh"

-- Themes / wallpaper
local wallpicker = "~/.config/hypr/scripts/launch_handler.sh wallpicker \"alacritty --class wallpicker -e awtwall --resume\""
local theme_select = "~/.config/hypr/scripts/theme_select.sh"

-- Capture / clipboard / QR
local screenshot_select = "env XDG_ACTIVATION_TOKEN=$XDG_ACTIVATION_TOKEN ~/.config/hypr/scripts/screenshot_area.sh"
local screenshot_full = "~/.config/hypr/scripts/screenshot_fullscreen.sh"
local screenshot_display = "~/.config/hypr/scripts/screenshot_display.sh"
local gif_capture = "~/.config/hypr/scripts/gif_capture.sh"
local clipboard_history = "~/.config/hypr/scripts/quickshell_clipboard_toggle.sh"
local qr_scan = "~/.config/hypr/scripts/qr_scan.sh"

-- Utilities
local workspace_mix = "~/.config/hypr/scripts/workspace_mix.sh"
local zoom = "~/.config/hypr/scripts/zoom.sh"
local hyprpicker = "hyprpicker -a -f hex"
local hypr_ddc_brightness = "~/.config/hypr/scripts/hypr-ddc-brightness.sh"
local vibrance_shader = "~/.config/hypr/scripts/vibrance_shader.sh"
local hyprsunset_ctl = "~/.config/hypr/scripts/hyprsunset_ctl.sh"

-- Terminal tools
local maccel = "~/.config/hypr/scripts/launch_handler.sh maccel \"alacritty --class maccel -e maccel\""
local smtty = "~/.config/hypr/scripts/launch_handler.sh smtty \"~/.config/hypr/scripts/default_terminal.sh --class smtty -- smtty\""
local btop = "~/.config/hypr/scripts/launch_handler.sh btop \"alacritty --class btop -e btop\""

-- Complex one-off
local smtty_O = "~/.config/hypr/scripts/launch_handler.sh smtty-O \"~/.config/hypr/scripts/default_terminal.sh --class smtty-O --hold -- smtty -O\""

-- Submap references (Toggle on)  [write name to file on entry]
local function _submap_on_cmd(name)
    return "sh -c 'echo " .. name .. " > /tmp/hypr-submap; notify-send -a Hyprland -t 1000 \"" .. name .. " mode: ON\"; hyprctl dispatch \"hl.dsp.submap(\\\"" .. name .. "\\\")\"'"
end

local function _submap_off_cmd(name)
    return "sh -c 'truncate -s 0 /tmp/hypr-submap; notify-send -a Hyprland -t 1000 \"" .. name .. " mode: OFF\"; hyprctl dispatch \"hl.dsp.submap(\\\"reset\\\")\"'"
end

local noalt_on = _submap_on_cmd("noalt")
local mouse_on = _submap_on_cmd("mouse")
local vm_on = _submap_on_cmd("vm")

-- Shared bind tables. Native Lua only, no helpers, no translator.
local workspace_keys = {
    { "1", 1 },
    { "2", 2 },
    { "3", 3 },
    { "4", 4 },
    { "5", 5 },
    { "6", 6 },
    { "7", 7 },
    { "8", 8 },
    { "9", 9 },
    { "0", 10 },
}

local movement_keys = {
    { "left", "l" },
    { "right", "r" },
    { "up", "u" },
    { "down", "d" },
    { "h", "l" },
    { "j", "d" },
    { "k", "u" },
    { "l", "r" },
}

local resize_keys = {
    { "right", 30, 0 },
    { "left", -30, 0 },
    { "up", 0, -30 },
    { "down", 0, 30 },
    { "h", -30, 0 },
    { "j", 0, 30 },
    { "k", 0, -30 },
    { "l", 30, 0 },
}

local media_binds = {
    { "XF86AudioRaiseVolume", "wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+", { repeating = true, locked = true } },
    { "XF86AudioLowerVolume", "wpctl set-volume      @DEFAULT_AUDIO_SINK@ 5%-", { repeating = true, locked = true } },
    { "XF86AudioMute", "wpctl set-mute        @DEFAULT_AUDIO_SINK@ toggle", { repeating = true, locked = true } },
    { "XF86AudioMicMute", "wpctl set-mute        @DEFAULT_AUDIO_SOURCE@ toggle", { repeating = true, locked = true } },
    { "XF86MonBrightnessUp", "brightnessctl -e4 -n2 set 5%+", { repeating = true, locked = true } },
    { "XF86MonBrightnessDown", "brightnessctl -e4 -n2 set 5%-", { repeating = true, locked = true } },
    { "XF86AudioPlay", play_pause, { locked = true } },
    { "XF86AudioNext", "playerctl next", { locked = true } },
    { "XF86AudioPrev", "playerctl previous", { locked = true } },
}

-- ───────────────────────────────────────────────────────────────────────────────
-- DEFAULT MODE (ALT is modifier; SUPER is app/meta)
-- ───────────────────────────────────────────────────────────────────────────────

-- App launchers / terminals
for _, bind in ipairs({
    { "ALT + P", app_launcher },
    { "SUPER + D", app_launcher },
    { "ALT + SHIFT + RETURN", terminal },
    { "SUPER + SHIFT + RETURN", terminal },
    { "SUPER + RETURN", terminal },
    { "ALT + SHIFT + B", btop },
    { "SUPER + SHIFT + B", btop },
    { "SUPER + B", web_browser },
    { "ALT + SHIFT + C", calculator },
    { "SUPER + SHIFT + C", calculator },
    { "ALT + SHIFT + M", maccel },
    { "SUPER + SHIFT + M", maccel },
}) do
    hl.bind(bind[1], hl.dsp.exec_cmd(bind[2]), {})
end

-- Audio mixer
hl.bind("ALT + V", hl.dsp.exec_cmd(wiremix), {})
hl.bind("SUPER + V", hl.dsp.exec_cmd(wiremix), {})

-- Notification dismiss
for _, key in ipairs({
    "ALT + SPACE",
    "ALT + CTRL + SPACE",
    "ALT + SHIFT + SPACE",
    "ALT + CTRL + SHIFT + SPACE",
    "SUPER + SPACE",
}) do
    hl.bind(key, hl.dsp.exec_cmd(notification_dismiss), {})
end

-- Terminal utilities (smtty)
hl.bind("SUPER + ALT + G", hl.dsp.exec_cmd(smtty), {})
hl.bind("SUPER + ALT + L", hl.dsp.exec_cmd("smtty -S -l"), {})
hl.bind("SUPER + ALT + O", hl.dsp.exec_cmd(smtty_O), {})
hl.bind("SUPER + ALT + K", hl.dsp.exec_cmd("smtty -k"), {})

-- UI / compositor toggles
for _, bind in ipairs({
    { "SUPER + ALT + T", hyprbars_toggle },
    { "SUPER + ALT + B", bar_rotate },
    { "SUPER + ALT + CTRL + B", bar_toggle },
    { "SUPER + CTRL + B", bar_flip },
    { "SUPER + A", toggle_animations },
}) do
    hl.bind(bind[1], hl.dsp.exec_cmd(bind[2]), {})
end

-- Brightness / color temperature
hl.bind("SUPER + ALT + backspace", hl.dsp.exec_cmd(hypr_quicksettings), {})
hl.bind("SUPER + ALT + equal", hl.dsp.exec_cmd(hypr_ddc_brightness .. " up 5"), {})
hl.bind("SUPER + ALT + minus", hl.dsp.exec_cmd(hypr_ddc_brightness .. " down 5"), {})
hl.bind("SUPER + ALT + CTRL + equal", hl.dsp.exec_cmd(hyprsunset_ctl .. " up"), {})
hl.bind("SUPER + ALT + CTRL + minus", hl.dsp.exec_cmd(hyprsunset_ctl .. " down"), {})
hl.bind("SUPER + ALT + CTRL + backspace", hl.dsp.exec_cmd(hyprsunset_ctl .. " toggle"), {})

-- File managers / system
hl.bind("SUPER + E", hl.dsp.exec_cmd("pcmanfm-qt"), {})
hl.bind("SUPER + SHIFT + E", hl.dsp.exec_cmd(yazi), {})
hl.bind("SUPER + L", hl.dsp.exec_cmd("hyprlock"), {})
hl.bind("SUPER + I", hl.dsp.exec_cmd(hyprpicker), {})
hl.bind("SUPER + P", hl.dsp.exec_cmd(power_menu), {})

-- Themes / wallpaper
for _, bind in ipairs({
    { "SUPER + W", wallpicker },
    { "SUPER + SHIFT + W", "awtwall --random-current" },
    { "SUPER + CTRL + W", "awtwall --random-all" },
    { "SUPER + ALT + W", "awtwall --random-all-different" },
    { "SUPER + T", theme_select },
}) do
    hl.bind(bind[1], hl.dsp.exec_cmd(bind[2]), {})
end

-- Capture / clipboard / misc
for _, bind in ipairs({
    { "SUPER + C", clipboard_history },
    { "SUPER + S", qr_scan },
    { "SUPER + SHIFT + S", screenshot_select },
    { "SUPER + SHIFT + F", screenshot_full },
    { "SUPER + SHIFT + D", screenshot_display },
    { "SUPER + SHIFT + G", gif_capture },
}) do
    hl.bind(bind[1], hl.dsp.exec_cmd(bind[2]), {})
end

-- Window management
for _, bind in ipairs({
    { "SUPER + Q", hl.dsp.window.close() },
    { "SUPER + SHIFT + Q", hl.dsp.window.close() },
    { "ALT + SHIFT + Q", hl.dsp.window.close() },
    { "ALT + F4", hl.dsp.window.close() },
    { "SUPER + ALT + Q", hl.dsp.exec_cmd("hyprctl kill") },
    { "ALT + Y", hl.dsp.window.pin() },
    { "SUPER + Y", hl.dsp.window.pin() },
    { "ALT + R", hl.dsp.layout("swapsplit") },
    { "ALT + SHIFT + R", hl.dsp.layout("togglesplit") },
    { "SUPER + R", hl.dsp.layout("swapsplit") },
    { "SUPER + SHIFT + R", hl.dsp.layout("togglesplit") },
    { "ALT + F", hl.dsp.window.float({ action = "toggle" }) },
    { "ALT + CTRL + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }) },
    { "SUPER + F", hl.dsp.window.float({ action = "toggle" }) },
    { "SUPER + CTRL + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }) },
    { "ALT + TAB", hl.dsp.window.cycle_next({ next = true }) },
    { "ALT + TAB", (hl.dsp.window.bring_to_top and hl.dsp.window.bring_to_top() or hl.dsp.window.alter_zorder({ mode = "top" })) },
    { "ALT + SHIFT + TAB", hl.dsp.window.cycle_next({ next = false }) },
}) do
    hl.bind(bind[1], bind[2], {})
end

-- Focus move (ALT/SUPER arrows + hjkl)
for _, bind in ipairs(movement_keys) do
    local key = bind[1]
    local direction = bind[2]

    hl.bind("ALT + " .. key, hl.dsp.focus({ direction = direction }), {})
    hl.bind("SUPER + " .. key, hl.dsp.focus({ direction = direction }), {})
end

-- Window move (ALT/SUPER+SHIFT arrows + hjkl)
for _, bind in ipairs(movement_keys) do
    local key = bind[1]
    local direction = bind[2]

    hl.bind("ALT + SHIFT + " .. key, hl.dsp.window.move({ direction = direction, }), {})
    hl.bind("SUPER + SHIFT + " .. key, hl.dsp.window.move({ direction = direction, }), {})
end

-- Send current workspace to monitor (ALT/SUPER+CTRL+SHIFT arrows + brackets)
for _, bind in ipairs({
    { "left", "-1" },
    { "right", "+1" },
    { "up", "-1" },
    { "down", "+1" },
    { "bracketleft", "-1" },
    { "bracketright", "+1" },
}) do
    local key = bind[1]
    local monitor = bind[2]

    hl.bind("ALT + CTRL + SHIFT + " .. key, hl.dsp.workspace.move({ monitor = monitor }), {})
    hl.bind("SUPER + CTRL + SHIFT + " .. key, hl.dsp.workspace.move({ monitor = monitor }), {})
end

-- Workspaces (ALT/SUPER numbers)
for _, bind in ipairs(workspace_keys) do
    local key = bind[1]
    local workspace = bind[2]

    hl.bind("ALT + " .. key, hl.dsp.focus({ workspace = workspace }), {})
    hl.bind("SUPER + " .. key, hl.dsp.focus({ workspace = workspace }), {})
end

-- Prev/next workspace with (ALT/SUPER "[" or "]")
for _, modifier in ipairs({ "ALT", "SUPER" }) do
    hl.bind(modifier .. " + bracketleft", hl.dsp.focus({ workspace = "-1" }), {})
    hl.bind(modifier .. " + bracketright", hl.dsp.focus({ workspace = "+1" }), {})
end

-- Move window to workspace (ALT/SUPER+SHIFT numbers)
for _, bind in ipairs(workspace_keys) do
    local key = bind[1]
    local workspace = bind[2]

    hl.bind("ALT + SHIFT + " .. key, hl.dsp.window.move({ workspace = workspace, follow = false }), {})
    hl.bind("SUPER + SHIFT + " .. key, hl.dsp.window.move({ workspace = workspace, follow = false }), {})
end

-- Resize (ALT/SUPER+CTRL arrows + hjkl / hold)
for _, bind in ipairs(resize_keys) do
    local key = bind[1]
    local x = bind[2]
    local y = bind[3]
    local action = hl.dsp.window.resize({ x = x, y = y, relative = true })

    hl.bind("ALT + CTRL + " .. key, action, { repeating = true })
    hl.bind("SUPER + CTRL + " .. key, action, { repeating = true })
end

-- Mouse (ALT/SUPER mouse-left/right / hold)
hl.bind("ALT + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("ALT + mouse:273", hl.dsp.window.resize(), { mouse = true })
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Digital vibrance quick adjust (SUPER+ALT+[] & SUPER+ALT+\; SUPER+ALT+CTRL+V toggle)
hl.bind("SUPER + ALT + bracketright", hl.dsp.exec_cmd(vibrance_shader .. " up"), {})
hl.bind("SUPER + ALT + bracketleft", hl.dsp.exec_cmd(vibrance_shader .. " down"), {})
hl.bind("SUPER + ALT + backslash", hl.dsp.exec_cmd(vibrance_shader .. " toggle"), {})
hl.bind("SUPER + ALT + CTRL + V", hl.dsp.exec_cmd(vibrance_shader .. " toggle"), {})

-- Workspace mixing script (SUPER+ALT+CTRL numbers)
for _, bind in ipairs(workspace_keys) do
    hl.bind("SUPER + ALT + CTRL + " .. bind[1], hl.dsp.exec_cmd(workspace_mix .. " toggle " .. bind[2]), {})
end
hl.bind("SUPER + ALT + CTRL + F", hl.dsp.exec_cmd(workspace_mix .. " focus"), {})
hl.bind("SUPER + ALT + CTRL + R", hl.dsp.exec_cmd(workspace_mix .. " restore"), {})

-- Zoom script (SUPER +/-)
for _, bind in ipairs({
    { "SUPER + equal", "+", true },
    { "SUPER + minus", "-", true },
    { "SUPER + SHIFT + equal", "++", true },
    { "SUPER + SHIFT + minus", "--", true },
    { "SUPER + backspace", "reset", false },
    { "SUPER + backslash", "rigid", false },
    { "SUPER + CTRL + equal", "+ step:5%", true },
    { "SUPER + CTRL + minus", "- step:5%", true },
}) do
    hl.bind(bind[1], hl.dsp.exec_cmd(zoom .. " " .. bind[2]), bind[3] and { repeating = true } or {})
end

-- Scratchpad (SUPER+x,X)
hl.bind("SUPER + X", hl.dsp.workspace.toggle_special("magic"), {})
hl.bind("SUPER + SHIFT + X", hl.dsp.window.move({ workspace = "special:magic", follow = true }), {})

-- Misc (SUPER+F12)
hl.bind("SUPER + F12", hl.dsp.exec_cmd("sh -c 'ver=$(hyprctl version | awk \"/^Hyprland /{print \\$2; exit}\"); [ -z \\\"$ver\\\" ] && ver=\\\"unknown\\\"; notify-send \"Hyprland Version\" \"$ver\"'"), {})
hl.bind("SUPER + CTRL + F12", hl.dsp.exec_cmd("notify-send \"Debug\" \"$(hyprctl activewindow -j | jq -r '.class, .title')\""), {})

-- Media & Brightness
for _, bind in ipairs(media_binds) do
    hl.bind(bind[1], hl.dsp.exec_cmd(bind[2]), bind[3])
end
hl.bind("SUPER + M", hl.dsp.exec_cmd(mute_unmute), {})

-- Submap binds                        (Toggle on/off)
hl.bind("SUPER + ALT + N", hl.dsp.exec_cmd(noalt_on), {})
hl.bind("SUPER + ALT + M", hl.dsp.exec_cmd(mouse_on), {})
hl.bind("SUPER + ALT + V", hl.dsp.exec_cmd(vm_on), {})

-- ───────────────────────────────────────────────────────────────────────────────
-- noalt SUBMAP; alt is disabled for most tasks
-- ───────────────────────────────────────────────────────────────────────────────

hl.define_submap("noalt", function()
    -- Submap references in "noalt" (toggle off/on)  [empty file on exit]
    local noalt_off = _submap_off_cmd("noalt")
    local mouse_on = _submap_on_cmd("mouse")
    local vm_on = _submap_on_cmd("vm")

    -- App launchers / terminals in "noalt"
    for _, bind in ipairs({
        { "ALT + P", app_launcher },
        { "SUPER + D", app_launcher },
        { "ALT + SHIFT + RETURN", terminal },
        { "SUPER + SHIFT + RETURN", terminal },
        { "SUPER + RETURN", terminal },
        { "ALT + SHIFT + B", btop },
        { "SUPER + SHIFT + B", btop },
        { "SUPER + B", web_browser },
        { "ALT + SHIFT + C", calculator },
        { "SUPER + SHIFT + C", calculator },
        { "ALT + SHIFT + M", maccel },
        { "SUPER + SHIFT + M", maccel },
    }) do
        hl.bind(bind[1], hl.dsp.exec_cmd(bind[2]), {})
    end

    -- Audio mixer in "noalt"
    hl.bind("ALT + V", hl.dsp.exec_cmd(wiremix), {})
    hl.bind("SUPER + V", hl.dsp.exec_cmd(wiremix), {})

    -- Notification dismiss in "noalt"
    for _, key in ipairs({
        "ALT + SPACE",
        "ALT + CTRL + SPACE",
        "ALT + SHIFT + SPACE",
        "ALT + CTRL + SHIFT + SPACE",
        "SUPER + SPACE",
    }) do
        hl.bind(key, hl.dsp.exec_cmd(notification_dismiss), {})
    end

    -- Terminal utilities (smtty) in "noalt"
    hl.bind("SUPER + ALT + G", hl.dsp.exec_cmd(smtty), {})
    hl.bind("SUPER + ALT + L", hl.dsp.exec_cmd("smtty -S -l"), {})
    hl.bind("SUPER + ALT + O", hl.dsp.exec_cmd(smtty_O), {})
    hl.bind("SUPER + ALT + K", hl.dsp.exec_cmd("smtty -k"), {})

    -- UI / compositor toggles in "noalt"
    for _, bind in ipairs({
        { "SUPER + ALT + T", hyprbars_toggle },
        { "SUPER + ALT + B", bar_rotate },
        { "SUPER + ALT + CTRL + B", bar_toggle },
        { "SUPER + CTRL + B", bar_flip },
        { "SUPER + A", toggle_animations },
    }) do
        hl.bind(bind[1], hl.dsp.exec_cmd(bind[2]), {})
    end

    -- Brightness / color temperature in "noalt"
    hl.bind("SUPER + ALT + backspace", hl.dsp.exec_cmd(hypr_quicksettings), {})
    hl.bind("SUPER + ALT + equal", hl.dsp.exec_cmd(hypr_ddc_brightness .. " up 5"), {})
    hl.bind("SUPER + ALT + minus", hl.dsp.exec_cmd(hypr_ddc_brightness .. " down 5"), {})
    hl.bind("SUPER + ALT + CTRL + equal", hl.dsp.exec_cmd(hyprsunset_ctl .. " up"), {})
    hl.bind("SUPER + ALT + CTRL + minus", hl.dsp.exec_cmd(hyprsunset_ctl .. " down"), {})
    hl.bind("SUPER + ALT + CTRL + backspace", hl.dsp.exec_cmd(hyprsunset_ctl .. " toggle"), {})

    -- File managers / system in "noalt"
    hl.bind("SUPER + E", hl.dsp.exec_cmd("pcmanfm-qt"), {})
    hl.bind("SUPER + SHIFT + E", hl.dsp.exec_cmd(yazi), {})
    hl.bind("SUPER + L", hl.dsp.exec_cmd("hyprlock"), {})
    hl.bind("SUPER + I", hl.dsp.exec_cmd(hyprpicker), {})
    hl.bind("SUPER + P", hl.dsp.exec_cmd(power_menu), {})

    -- Themes / wallpaper
    for _, bind in ipairs({
        { "SUPER + W", wallpicker },
        { "SUPER + SHIFT + W", "awtwall --random-current" },
        { "SUPER + CTRL + W", "awtwall --random-all" },
        { "SUPER + ALT + W", "awtwall --random-all-different" },
        { "SUPER + T", theme_select },
    }) do
        hl.bind(bind[1], hl.dsp.exec_cmd(bind[2]), {})
    end

    -- Capture / clipboard / misc in "noalt"
    for _, bind in ipairs({
        { "SUPER + C", clipboard_history },
        { "SUPER + S", qr_scan },
        { "SUPER + SHIFT + S", screenshot_select },
        { "SUPER + SHIFT + F", screenshot_full },
        { "SUPER + SHIFT + D", screenshot_display },
        { "SUPER + SHIFT + G", gif_capture },
    }) do
        hl.bind(bind[1], hl.dsp.exec_cmd(bind[2]), {})
    end

    -- Window management in "noalt"
    for _, bind in ipairs({
        { "SUPER + Q", hl.dsp.window.close() },
        { "SUPER + SHIFT + Q", hl.dsp.window.close() },
        { "ALT + F4", hl.dsp.window.close() },
        { "SUPER + ALT + Q", hl.dsp.exec_cmd("hyprctl kill") },
        { "SUPER + Y", hl.dsp.window.pin() },
        { "SUPER + SHIFT + R", hl.dsp.layout("togglesplit") },
        { "SUPER + R", hl.dsp.layout("swapsplit") },
        { "SUPER + F", hl.dsp.window.float({ action = "toggle" }) },
        { "SUPER + CTRL + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }) },
        { "ALT + TAB", hl.dsp.window.cycle_next({ next = true }) },
        { "ALT + TAB", (hl.dsp.window.bring_to_top and hl.dsp.window.bring_to_top() or hl.dsp.window.alter_zorder({ mode = "top" })) },
        { "ALT + SHIFT + TAB", hl.dsp.window.cycle_next({ next = false }) },
    }) do
        hl.bind(bind[1], bind[2], {})
    end

    -- Focus move in "noalt" (SUPER arrows + hjkl)
    for _, bind in ipairs(movement_keys) do
        hl.bind("SUPER + " .. bind[1], hl.dsp.focus({ direction = bind[2] }), {})
    end

    -- Window move in "noalt" (SUPER+SHIFT arrows + hjkl)
    for _, bind in ipairs(movement_keys) do
        hl.bind("SUPER + SHIFT + " .. bind[1], hl.dsp.window.move({ direction = bind[2], }), {})
    end

    -- Send current workspace to monitor in "noalt" (SUPER+CTRL+SHIFT arrows + brackets)
    for _, bind in ipairs({
        { "left", "-1" },
        { "right", "+1" },
        { "up", "-1" },
        { "down", "+1" },
        { "bracketleft", "-1" },
        { "bracketright", "+1" },
    }) do
        hl.bind("SUPER + CTRL + SHIFT + " .. bind[1], hl.dsp.workspace.move({ monitor = bind[2] }), {})
    end

    -- Workspaces in "noalt" (SUPER numbers)
    for _, bind in ipairs(workspace_keys) do
        hl.bind("SUPER + " .. bind[1], hl.dsp.focus({ workspace = bind[2] }), {})
    end

    -- Prev/next workspace with (SUPER "[" or "]")
    hl.bind("SUPER + bracketleft", hl.dsp.focus({ workspace = "-1" }), {})
    hl.bind("SUPER + bracketright", hl.dsp.focus({ workspace = "+1" }), {})

    -- Move window to workspace in "noalt" (SUPER+SHIFT numbers)
    for _, bind in ipairs(workspace_keys) do
        hl.bind("SUPER + SHIFT + " .. bind[1], hl.dsp.window.move({ workspace = bind[2], follow = false }), {})
    end

    -- Resize in "noalt" (SUPER+CTRL arrows + hjkl / hold)
    for _, bind in ipairs(resize_keys) do
        hl.bind("SUPER + CTRL + " .. bind[1], hl.dsp.window.resize({ x = bind[2], y = bind[3], relative = true }), { repeating = true })
    end

    -- Mouse in "noalt" (SUPER mouse-left/right / hold)
    hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
    hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

    -- Digital vibrance quick adjust (SUPER+ALT+[] & SUPER+ALT+\; SUPER+ALT+CTRL+V toggle)
    hl.bind("SUPER + ALT + bracketright", hl.dsp.exec_cmd(vibrance_shader .. " up"), {})
    hl.bind("SUPER + ALT + bracketleft", hl.dsp.exec_cmd(vibrance_shader .. " down"), {})
    hl.bind("SUPER + ALT + backslash", hl.dsp.exec_cmd(vibrance_shader .. " toggle"), {})
    hl.bind("SUPER + ALT + CTRL + V", hl.dsp.exec_cmd(vibrance_shader .. " toggle"), {})

    -- Workspace mixing script (SUPER+ALT+CTRL numbers)
    for _, bind in ipairs(workspace_keys) do
        hl.bind("SUPER + ALT + CTRL + " .. bind[1], hl.dsp.exec_cmd(workspace_mix .. " toggle " .. bind[2]), {})
    end
    hl.bind("SUPER + ALT + CTRL + F", hl.dsp.exec_cmd(workspace_mix .. " focus"), {})
    hl.bind("SUPER + ALT + CTRL + R", hl.dsp.exec_cmd(workspace_mix .. " restore"), {})

    -- Zoom script in "noalt" (SUPER +/-)
    for _, bind in ipairs({
        { "SUPER + equal", "+", true },
        { "SUPER + minus", "-", true },
        { "SUPER + SHIFT + equal", "++", true },
        { "SUPER + SHIFT + minus", "--", true },
        { "SUPER + backspace", "reset", false },
        { "SUPER + backslash", "rigid", false },
        { "SUPER + CTRL + equal", "+ step:5%", true },
        { "SUPER + CTRL + minus", "- step:5%", true },
    }) do
        hl.bind(bind[1], hl.dsp.exec_cmd(zoom .. " " .. bind[2]), bind[3] and { repeating = true } or {})
    end

    -- Scratchpad in "noalt" (SUPER+x,X)
    hl.bind("SUPER + X", hl.dsp.workspace.toggle_special("magic"), {})
    hl.bind("SUPER + SHIFT + X", hl.dsp.window.move({ workspace = "special:magic", follow = true }), {})

    -- Misc in "noalt" (SUPER+F12)
    hl.bind("SUPER + F12", hl.dsp.exec_cmd("sh -c 'ver=$(hyprctl version | awk \"/^Hyprland /{print \\$2; exit}\"); [ -z \\\"$ver\\\" ] && ver=\\\"unknown\\\"; notify-send \"Hyprland Version\" \"$ver\"'"), {})
    hl.bind("SUPER + CTRL + F12", hl.dsp.exec_cmd("notify-send \"Debug\" \"$(hyprctl activewindow -j | jq -r '.class, .title')\""), {})

    -- Media & Brightness
    for _, bind in ipairs(media_binds) do
        hl.bind(bind[1], hl.dsp.exec_cmd(bind[2]), bind[3])
    end
    hl.bind("SUPER + M", hl.dsp.exec_cmd(mute_unmute), {})

    -- Submap binds in "noalt"             (Toggle off/on)
    hl.bind("SUPER + ALT + N", hl.dsp.exec_cmd(noalt_off), {})
    hl.bind("SUPER + ALT + M", hl.dsp.exec_cmd(mouse_on), {})
    hl.bind("SUPER + ALT + V", hl.dsp.exec_cmd(vm_on), {})
end)

-- ───────────────────────────────────────────────────────────────────────────────
-- MOUSE SUBMAP
-- ───────────────────────────────────────────────────────────────────────────────

hl.define_submap("mouse", function()
    -- Submap references in "mouse" (toggle off)  [empty file on exit]
    local mouse_off = _submap_off_cmd("mouse")

    -- Resize (MOUSE-left/right / hold)
    for _, bind in ipairs(resize_keys) do
        hl.bind(bind[1], hl.dsp.window.resize({ x = bind[2], y = bind[3], relative = true }), { repeating = true })
    end

    hl.bind("mouse:272", hl.dsp.window.drag(), { mouse = true })
    hl.bind("mouse:273", hl.dsp.window.resize(), { mouse = true })
    hl.bind("mouse:274", hl.dsp.window.float({ action = "toggle" }), {})
    hl.bind("Escape", hl.dsp.exec_cmd(mouse_off), {})
    hl.bind("Return", hl.dsp.exec_cmd(mouse_off), {})

    -- Submap binds in "mouse"  (Toggle off/on)
    hl.bind("SUPER + ALT + M", hl.dsp.exec_cmd(mouse_off), {})
    hl.bind("SUPER + ALT + N", hl.dsp.exec_cmd(noalt_on), {})
    hl.bind("SUPER + ALT + V", hl.dsp.exec_cmd(vm_on), {})
end)

-- ───────────────────────────────────────────────────────────────────────────────
-- VIRTUAL MACHINE SUBMAP
-- ───────────────────────────────────────────────────────────────────────────────

hl.define_submap("vm", function()
    -- Submap references in "vm" (Toggle off)  [empty file on exit]
    local vm_off = _submap_off_cmd("vm")
    
    -- Binds
    for _, bind in ipairs({
        { "SUPER + ALT + Q", hl.dsp.window.close(), {} },
        { "SUPER + ALT + F", hl.dsp.window.float({ action = "toggle" }), {} },
        { "SUPER + ALT + P", hl.dsp.exec_cmd(app_launcher), {} },
        { "SUPER + ALT + C", hl.dsp.exec_cmd(calculator), {} },
        { "SUPER + ALT + CTRL + V", hl.dsp.exec_cmd(wiremix), {} },
        { "SUPER + ALT + CTRL + S", hl.dsp.exec_cmd(qr_scan), {} },
        { "SUPER + ALT + S", hl.dsp.exec_cmd(screenshot_select), {} },
        { "SUPER + ALT + D", hl.dsp.exec_cmd(screenshot_display), {} },
        { "SUPER + ALT + G", hl.dsp.exec_cmd(gif_capture), {} },
        { "SUPER + ALT + RETURN", hl.dsp.exec_cmd(terminal), {} },
        { "SUPER + ALT + SPACE", hl.dsp.exec_cmd(notification_dismiss), { repeating = true } },
        { "SUPER + ALT + mouse:272", hl.dsp.window.drag(), { mouse = true } },
        { "SUPER + ALT + mouse:273", hl.dsp.window.resize(), { mouse = true } },
        { "SUPER + ALT + mouse:274", hl.dsp.window.float({ action = "toggle" }), {} },
    }) do
        hl.bind(bind[1], bind[2], bind[3])
    end

    -- Workspaces (SUPER+ALT numbers)
    for _, bind in ipairs(workspace_keys) do
        hl.bind("SUPER + ALT + " .. bind[1], hl.dsp.focus({ workspace = bind[2] }), {})
    end

    -- Move window to workspace (SUPER+ALT+SHIFT numbers)
    for _, bind in ipairs(workspace_keys) do
        hl.bind("SUPER + ALT + SHIFT + " .. bind[1], hl.dsp.window.move({ workspace = bind[2], follow = false }), {})
    end

    -- Submap binds in "vm"            (Toggle off/on)
    hl.bind("SUPER + ALT + V", hl.dsp.exec_cmd(vm_off), {})
    hl.bind("SUPER + ALT + M", hl.dsp.exec_cmd(mouse_on), {})
    hl.bind("SUPER + ALT + N", hl.dsp.exec_cmd(noalt_on), {})
end)

-- ───────────────────────────────────────────────────────────────────────────────
-- RULES
-- ───────────────────────────────────────────────────────────────────────────────

-- Games: send to workspace 1, strip effects, fullscreen, allow tearing, keep awake
-- Note: Proton/Wine windows often have class like "game.exe" (not "Wine"), so we also match *.exe.
local games = "^(steam_app_.*|lutris_game_class|minigalaxy|playnite_game_class|gamescope|chiaki|moonlight|com\\.moonlight_stream\\.Moonlight|.*\\.exe)$"
-- Mark these windows as "game" content type so render:direct_scanout=2 can auto-engage
hl.window_rule({ match = { class = games }, content = "game" })
-- other $games window rules
hl.window_rule({ match = { class = games }, workspace = "1 silent" })
hl.window_rule({ match = { class = games }, no_anim = true })
hl.window_rule({ match = { class = games }, no_blur = true })
hl.window_rule({ match = { class = games }, no_shadow = true })
hl.window_rule({ match = { class = games }, decorate = false })
hl.window_rule({ match = { class = games }, border_size = 0 })
hl.window_rule({ match = { class = games }, rounding = 0 })
hl.window_rule({ match = { class = games }, fullscreen = true })
hl.window_rule({ match = { class = games }, immediate = true })
hl.window_rule({ match = { class = games }, idle_inhibit = "always" })

-- Workspace auto-assignments
hl.window_rule({ match = { class = "^(firefox|librewolf|Mullvad Browser|Cromite|brave-browser|io\\.github\\.ungoogled_software\\.ungoogled_chromium)$" }, workspace = "2 silent" })
hl.window_rule({ match = { class = "^(discord|com\\.discordapp\\.Discord|vesktop|dev\\.vencord\\.Vesktop|brave-app\\.revolt\\.chat__-.*|chat\\.revolt\\.RevoltDesktop|info\\.mumble\\.Mumble|fluxer|Fluxer)$" }, workspace = "3 silent" })
hl.window_rule({ match = { class = "^(steam|com\\.valvesoftware\\.Steam|SteamChat|net\\.lutris\\.Lutris|itch|io\\.itch\\.itch|heroic|com\\.heroicgameslauncher\\.hgl|r2modman)$" }, workspace = "4 silent" })
hl.window_rule({ match = { class = "^(Spotify|com\\.spotify\\.Client|brave-music\\.youtube\\.com__-.*)$" }, workspace = "5 silent" })
hl.window_rule({ match = { title = "^(.*YouTube Music.*)$" }, workspace = "5 silent" })
hl.window_rule({ match = { class = "^(org\\.telegram\\.desktop|brave-web\\.telegram\\.org__a_-.*|brave-messages\\.google\\.com__-.*)$" }, workspace = "6 silent" })
hl.window_rule({ match = { title = "^(Telegram Web)$" }, workspace = "6 silent" })
hl.window_rule({ match = { class = "^(Messages)$" }, workspace = "6 silent" })
hl.window_rule({ match = { class = "^(Telegram)$" }, workspace = "6 silent" })
hl.window_rule({ match = { class = "^(Vncviewer|rustdesk)$" }, workspace = "7 silent" })
hl.window_rule({ match = { class = "^(com\\.github\\.IsmaelMartinez\\.teams_for_linux)$" }, workspace = "8 silent" })
hl.window_rule({ match = { class = "^(kdenlive|org\\.kde\\.kdenlive|org\\.shotcut\\.Shotcut|krita|org\\.kde\\.krita)$" }, workspace = "9 silent" })
hl.window_rule({ match = { class = "^(obs|com\\.obsproject\\.Studio|gpu-screen-recorder|gpu-screen-recorder-gtk|gpu-screen-recorder-ui|gsr-ui|com\\.dec05eba\\.gpu_screen_recorder)$" }, workspace = "10 silent" })

-- Global behavior / XWayland quirks
hl.window_rule({ match = { class = ".*" }, suppress_event = "maximize" })
hl.window_rule({ match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false }, no_focus = true })
hl.window_rule({ match = { xwayland = true }, no_blur = true })
hl.window_rule({ match = { class = "^(steam)$", title = "^$" }, stay_focused = true })
hl.window_rule({ match = { class = "^(steam)$", title = "^$" }, min_size = { 1, 1 } })

-- Picture-in-Picture
local pip = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$"
hl.window_rule({ match = { title = pip }, float = true })
hl.window_rule({ match = { title = pip }, keep_aspect_ratio = true })
hl.window_rule({ match = { title = pip }, move = { "(monitor_w*0.73)", "(monitor_h*0.70)" } })
hl.window_rule({ match = { title = pip }, size = { "(monitor_w*0.25)", "(monitor_h*0.25)" } })
hl.window_rule({ match = { title = pip }, pin = true })

-- Dialogs float+center
local dialogs = "^(Open File|Select a File|Choose wallpaper|Open Folder|Save As|Library|File Upload)(.*)$"
hl.window_rule({ match = { title = dialogs }, float = true })
hl.window_rule({ match = { title = dialogs }, center = true })

-- Transparency
hl.window_rule({ match = { class = "^(wofi)$" }, opacity = "0.85 0.85" })
hl.window_rule({ match = { class = "^(Spotify)$" }, opacity = "0.85 0.85" })
hl.window_rule({ match = { title = "^(YouTube Music|YouTube Music - .+ - YouTube Music|YouTube Music - 1\\. YouTube Music)$" }, opacity = "0.85 0.85" })
hl.window_rule({ match = { class = "^(com\\.github\\.th_ch\\.youtube_music|brave-music\\.youtube\\.com__-.*)$" }, opacity = "0.85 0.85" })
hl.window_rule({ match = { class = "^(pcmanfm-qt|localsend|org\\.pulseaudio\\.pavucontrol|org\\.speedcrunch\\.speedcrunch|net\\.davidotek\\.pupgui2|wallpicker)$" }, opacity = "0.95 0.95" })

-- Float + size + center
hl.window_rule({ match = { class = "^org\\.speedcrunch\\.speedcrunch$" }, float = true })
hl.window_rule({ match = { class = "^org\\.speedcrunch\\.speedcrunch$" }, size = { "(monitor_w*0.15)", "(monitor_h*0.55)" } })
hl.window_rule({ match = { class = "^org\\.speedcrunch\\.speedcrunch$" }, center = true })

hl.window_rule({ match = { class = "^org\\.pulseaudio\\.pavucontrol$" }, float = true })
hl.window_rule({ match = { class = "^org\\.pulseaudio\\.pavucontrol$" }, size = { "(monitor_w*0.55)", "(monitor_h*0.70)" } })
hl.window_rule({ match = { class = "^org\\.pulseaudio\\.pavucontrol$" }, center = true })

hl.window_rule({ match = { class = "^(Pulsemixer)$" }, float = true })
hl.window_rule({ match = { class = "^(Pulsemixer)$" }, size = { "(monitor_w*0.55)", "(monitor_h*0.70)" } })
hl.window_rule({ match = { class = "^(Pulsemixer)$" }, center = true })

hl.window_rule({ match = { class = "^(Wiremix)$" }, float = true })
hl.window_rule({ match = { class = "^(Wiremix)$" }, size = { "(monitor_w*0.65)", "(monitor_h*0.70)" } })
hl.window_rule({ match = { class = "^(Wiremix)$" }, center = true })

hl.window_rule({ match = { class = "^(hypr_quicksettings)$" }, float = true })
hl.window_rule({ match = { class = "^(hypr_quicksettings)$" }, size = { "(monitor_w*0.70)", "(monitor_h*0.50)" } })
hl.window_rule({ match = { class = "^(hypr_quicksettings)$" }, center = true })

hl.window_rule({ match = { class = "^(awtarchy-tips-tui)$" }, float = true })
hl.window_rule({ match = { class = "^(awtarchy-tips-tui)$" }, size = { "(monitor_w*0.50)", "(monitor_h*0.50)" } })
hl.window_rule({ match = { class = "^(awtarchy-tips-tui)$" }, center = true })

hl.window_rule({ match = { class = "^(maccel)$" }, float = true })
hl.window_rule({ match = { class = "^(maccel)$" }, size = { "(monitor_w*0.90)", "(monitor_h*0.96)" } })
hl.window_rule({ match = { class = "^(maccel)$" }, center = true })

hl.window_rule({ match = { class = "^(hyprbars)$" }, float = true })
hl.window_rule({ match = { class = "^(hyprbars)$" }, size = { "(monitor_w*0.30)", "(monitor_h*0.10)" } })
hl.window_rule({ match = { class = "^(hyprbars)$" }, center = true })

hl.window_rule({ match = { class = "^(smtty)$" }, float = true })
hl.window_rule({ match = { class = "^(smtty)$" }, size = { "(monitor_w*0.50)", "(monitor_h*0.65)" } })
hl.window_rule({ match = { class = "^(smtty)$" }, center = true })

hl.window_rule({ match = { class = "^(smtty-O)$" }, float = true })
hl.window_rule({ match = { class = "^(smtty-O)$" }, size = { "(monitor_w*0.50)", "(monitor_h*0.65)" } })
hl.window_rule({ match = { class = "^(smtty-O)$" }, center = true })

hl.window_rule({ match = { class = "^(wallpicker)$" }, float = true })
hl.window_rule({ match = { class = "^(wallpicker)$" }, size = { "(monitor_w*0.85)", "(monitor_h*0.90)" } })
hl.window_rule({ match = { class = "^(wallpicker)$" }, center = true })


hl.window_rule({ match = { class = "^(net\\.davidotek\\.pupgui2)$" }, float = true })
hl.window_rule({ match = { class = "^(net\\.davidotek\\.pupgui2)$" }, size = { "(monitor_w*0.45)", "(monitor_h*0.45)" } })
hl.window_rule({ match = { class = "^(net\\.davidotek\\.pupgui2)$" }, center = true })

hl.window_rule({ match = { class = "^(btop)$" }, float = true })
hl.window_rule({ match = { class = "^(btop)$" }, size = { "(monitor_w*0.80)", "(monitor_h*0.85)" } })
hl.window_rule({ match = { class = "^(btop)$" }, center = true })

-- Force Tile
hl.window_rule({ match = { class = "^(steam|com\\.valvesoftware\\.Steam)$", title = "^(Steam)$" }, tile = true })
hl.window_rule({ match = { class = "^(steam|com\\.valvesoftware\\.Steam)$", title = "^(Friends List)$" }, tile = true })

-- ───────────────────────────────────────────────────────────────────────────────
-- SCREENSHARE GUARD
-- ───────────────────────────────────────────────────────────────────────────────

hl.window_rule({ match = { class = "^(Bitwarden|com\\.bitwarden\\.desktop|KeePassXC|org\\.keepassxc\\.KeePassXC|1Password|com\\.1password\\.1password|Enpass|org\\.gnome\\.Secrets|org\\.gnome\\.seahorse\\.Application|OTPClient|otpclient|org\\.rasalminen\\.OTPClient|Mullvad Browser|mullvad-browser|com\\.mullvad\\.Browser|localsend|LocalSend|org\\.localsend\\.localsend|io\\.github\\.localsend\\.localsend)$" }, no_screen_share = true })
hl.window_rule({ match = { class = "^(firefox)$", title = "^(Extension: \\(Bitwarden Password Manager\\).*)$" }, no_screen_share = true })
hl.window_rule({ match = { class = "^(brave-browser|chromium|google-chrome|chrome|vivaldi-stable|microsoft-edge)$", title = "^(Bitwarden Password Manager.*)$" }, no_screen_share = true })
hl.window_rule({ match = { class = "^(org\\.telegram\\.desktop|TelegramDesktop|telegram-desktop|Telegram)$" }, no_screen_share = true })
hl.window_rule({ match = { class = "^(brave-browser|chromium|google-chrome|chrome|vivaldi-stable|microsoft-edge)$", title = "^.*Telegram.*$" }, no_screen_share = true })
hl.window_rule({ match = { class = "^(Element|io\\.element\\.Element|im\\.riot\\.Riot|chat\\.element\\.desktop|SchildiChat|im\\.fluffychat\\.Fluffychat|Fractal|org\\.gnome\\.Fractal|nheko)$" }, no_screen_share = true })
hl.window_rule({ match = { class = "^(discord|com\\.discordapp\\.Discord|vesktop|dev\\.vencord\\.Vesktop|Fluxer|fluxer)$" }, no_screen_share = true })
hl.window_rule({ match = { class = "^(com\\.github\\.IsmaelMartinez\\.teams_for_linux)$" }, no_screen_share = true })
hl.window_rule({ match = { class = "^(Messages)$" }, no_screen_share = true })

-- Layers (notifications/swaync are layer surfaces, not windows)
hl.layer_rule({ match = { namespace = "^(notifications|swaync.*)$" }, no_screen_share = true })

-- optional
-- hl.window_rule({ match = { class = "^(obs|com\\.obsproject\\.Studio|obs-studio|com\\.obsproject\\.Studio\\.obs)$" }, no_screen_share = true })
-- hl.window_rule({ match = { class = "^(steam|com\\.valvesoftware\\.Steam)$" }, no_screen_share = true })
-- hl.window_rule({ match = { class = "^(rustdesk|com\\.rustdesk\\.RustDesk)$" }, no_screen_share = true })
-- hl.window_rule({ match = { class = "^(pcmanfm-qt|Pcmanfm-qt|pcmanfm)$" }, no_screen_share = true })
-- hl.window_rule({ match = { class = "^(wallpicker)$" }, no_screen_share = true })
-- hl.window_rule({ match = { class = "^(virt-manager)$" }, no_screen_share = true })
-- hl.window_rule({ match = { class = "^(Alacritty)$" }, no_screen_share = true })
-- hl.window_rule({ match = { class = "^(mpv)$" }, no_screen_share = true })
-- hl.layer_rule({ match = { namespace = "^(ags)$" }, no_screen_share = true })
-- hl.layer_rule({ match = { namespace = "^(logout_dialog)$" }, no_screen_share = true })
-- hl.layer_rule({ match = { namespace = "^(waybar)$" }, no_screen_share = true })

-- ───────────────────────────────────────────────────────────────────────────────
-- MANUAL SETUP
-- ───────────────────────────────────────────────────────────────────────────────

-- Sunshine / Moonlight Fix
-- Configure in Sunshine Web-UI → “Do Command” (on connect):
--   /usr/bin/env bash -lc "$HOME/.config/hypr/scripts/sunshine-moonlight-fix.sh"
-- READ SCRIPT:        cat ~/.config/hypr/scripts/sunshine-moonlight-fix.sh

-- ───────────────────────────────────────────────────────────────────────────────
-- .DESKTOP NOTES
-- ───────────────────────────────────────────────────────────────────────────────

-- ~/.local/share/applications/*

-- Steam Splitratio Script
-- Set split ratio between Steam and Friends List (runs once at startup with a timeout of 300s)
-- READ SCRIPT:        cat ~/.config/hypr/scripts/splitratio_steam.sh
-- .desktop override:  Exec=sh -lc 'pgrep -x steam >/dev/null && exit 0; /usr/bin/steam --disable-gpu "$@" & ALLOW_WAIT=1 "$HOME/.config/hypr/scripts/splitratio_steam.sh" &' _ %U
-- Check file:         cat ~/.local/share/applications/steam.desktop
