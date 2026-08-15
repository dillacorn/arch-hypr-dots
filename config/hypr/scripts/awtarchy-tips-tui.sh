#!/usr/bin/env bash
# FILE: ~/.config/hypr/scripts/awtarchy-tips-tui.sh
# Awtarchy local help/manual TUI.

set -euo pipefail
export LC_ALL=C.UTF-8

DISABLE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/awtarchy-tips-disabled"
REPO_DIR="${AWTARCHY_REPO_DIR:-$HOME/awtarchy}"
EXTRA_NOTES_DIR="${REPO_DIR}/extra_notes"
DEFAULT_TERMINAL="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts/default_terminal.sh"

C_RESET=$'\033[0m'
C_BOLD=$'\033[1m'
C_DIM=$'\033[2m'
C_CYAN=$'\033[36m'
C_REVERSE=$'\033[7m'

MOUSE_BUTTON=-1
MOUSE_X=0
MOUSE_Y=0
MOUSE_RELEASE=0
MENU_FIRST_ROW=0
MENU_VISIBLE_START=0
MENU_VISIBLE_END=0
MENU_PAGE_SIZE=0
declare -A MENU_SELECTIONS=()

cleanup_terminal() {
    printf '\033[?1000l\033[?1006l\033[?25h\033[0m' >&3 2>/dev/null || true
}

open_tty() {
    exec 3<>/dev/tty || {
        printf 'awtarchy-tips-tui: /dev/tty is unavailable\n' >&2
        exit 1
    }
    trap cleanup_terminal EXIT INT TERM HUP
}

clear_screen() {
    printf '\033[H\033[2J' >&3
}

enable_mouse() {
    printf '\033[?1000h\033[?1006h\033[?25l' >&3
}

disable_mouse() {
    printf '\033[?1000l\033[?1006l\033[?25h' >&3
}

term_lines() {
    local value
    value="$(tput lines 2>/dev/null || printf '30')"
    [[ "$value" =~ ^[0-9]+$ ]] || value=30
    printf '%s\n' "$value"
}

term_cols() {
    local value
    value="$(tput cols 2>/dev/null || printf '100')"
    [[ "$value" =~ ^[0-9]+$ ]] || value=100
    printf '%s\n' "$value"
}

read_key() {
    local key="" next=""

    IFS= read -rsn1 key <&3 || return 1
    if [[ "$key" != $'\033' ]]; then
        printf '%s' "$key"
        return 0
    fi

    if ! IFS= read -rsn1 -t 0.04 next <&3; then
        printf '%s' "$key"
        return 0
    fi
    key+="$next"

    if [[ "$next" == "[" ]]; then
        if IFS= read -rsn1 -t 0.04 next <&3; then
            key+="$next"
            if [[ "$next" == "<" ]]; then
                while IFS= read -rsn1 -t 0.04 next <&3; do
                    key+="$next"
                    [[ "$next" == "M" || "$next" == "m" ]] && break
                done
            elif [[ "$next" =~ [0-9] ]]; then
                while IFS= read -rsn1 -t 0.04 next <&3; do
                    key+="$next"
                    [[ "$next" == "~" || "$next" =~ [A-Za-z] ]] && break
                done
            fi
        fi
    fi

    printf '%s' "$key"
}

parse_mouse_event() {
    local event="$1" body suffix
    MOUSE_BUTTON=-1
    MOUSE_X=0
    MOUSE_Y=0
    MOUSE_RELEASE=0

    [[ "$event" == $'\033[<'* ]] || return 1
    suffix="${event: -1}"
    [[ "$suffix" == "M" || "$suffix" == "m" ]] || return 1
    body="${event#$'\033[<'}"
    body="${body%?}"
    IFS=';' read -r MOUSE_BUTTON MOUSE_X MOUSE_Y <<<"$body"
    [[ "$MOUSE_BUTTON" =~ ^[0-9]+$ && "$MOUSE_X" =~ ^[0-9]+$ && "$MOUSE_Y" =~ ^[0-9]+$ ]] || return 1
    [[ "$suffix" == "m" ]] && MOUSE_RELEASE=1
    return 0
}

prompt_filter() {
    local prompt="$1" value=""
    disable_mouse
    printf '\n%s' "$prompt" >&3
    IFS= read -r value <&3 || true
    enable_mouse
    printf '%s' "$value"
}

menu_select() {
    local title="$1" items_name="$2" subtitle="${3:-}" initial_original="${4:-0}"
    local -n items_ref="$items_name"
    local selected=0 filter="" key="" i original total lines cols start end row label restore_initial=1
    local -a view=()

    [[ "$initial_original" =~ ^[0-9]+$ ]] || initial_original=0

    while true; do
        view=()
        for i in "${!items_ref[@]}"; do
            label="${items_ref[$i]}"
            if [[ -z "$filter" || "${label,,}" == *"${filter,,}"* ]]; then
                view+=("$i")
            fi
        done

        total="${#view[@]}"
        if (( restore_initial )); then
            selected=0
            if (( total > 0 )); then
                for i in "${!view[@]}"; do
                    if [[ "${view[$i]}" == "$initial_original" ]]; then
                        selected="$i"
                        break
                    fi
                done
            fi
            restore_initial=0
        fi

        if (( total == 0 )); then
            selected=0
        elif (( selected >= total )); then
            selected=$((total - 1))
        elif (( selected < 0 )); then
            selected=0
        fi

        lines="$(term_lines)"
        cols="$(term_cols)"
        MENU_PAGE_SIZE=$((lines - 8))
        (( MENU_PAGE_SIZE < 5 )) && MENU_PAGE_SIZE=5
        (( MENU_PAGE_SIZE > 30 )) && MENU_PAGE_SIZE=30

        start=$((selected - MENU_PAGE_SIZE / 2))
        (( start < 0 )) && start=0
        if (( start + MENU_PAGE_SIZE > total )); then
            start=$((total - MENU_PAGE_SIZE))
            (( start < 0 )) && start=0
        fi
        end=$((start + MENU_PAGE_SIZE))
        (( end > total )) && end=$total

        clear_screen
        row=1
        printf '%s%s%s\n' "$C_BOLD$C_CYAN" "$title" "$C_RESET" >&3
        ((row++)) || true
        if [[ -n "$subtitle" ]]; then
            printf '%s%s%s\n' "$C_DIM" "$subtitle" "$C_RESET" >&3
            ((row++)) || true
        fi
        if [[ -n "$filter" ]]; then
            printf 'Filter: %s%s%s\n' "$C_CYAN" "$filter" "$C_RESET" >&3
            ((row++)) || true
        fi
        printf '\n' >&3
        ((row++)) || true
        MENU_FIRST_ROW=$row
        MENU_VISIBLE_START=$start
        MENU_VISIBLE_END=$end

        if (( total == 0 )); then
            printf '  No matches. Press / to search again or c to clear.\n' >&3
        else
            for ((i = start; i < end; i++)); do
                original="${view[$i]}"
                label="${items_ref[$original]}"
                if (( i == selected )); then
                    printf '%s  %-*.*s  %s\n' "$C_REVERSE" "$((cols - 4))" "$((cols - 4))" "$label" "$C_RESET" >&3
                else
                    printf '  %-*.*s\n' "$((cols - 4))" "$((cols - 4))" "$label" >&3
                fi
            done
        fi

        printf '\n%sUp/Down or wheel = move  Enter/click = open  / = search  c = clear  Esc/q = back%s\n' "$C_DIM" "$C_RESET" >&3

        key="$(read_key || true)"
        if parse_mouse_event "$key"; then
            (( MOUSE_RELEASE == 1 )) && continue
            case "$MOUSE_BUTTON" in
                64)
                    (( total > 0 && selected > 0 )) && ((selected--)) || true
                    ;;
                65)
                    (( total > 0 && selected + 1 < total )) && ((selected++)) || true
                    ;;
                0)
                    if (( total > 0 && MOUSE_Y >= MENU_FIRST_ROW && MOUSE_Y < MENU_FIRST_ROW + (end - start) )); then
                        i=$((start + MOUSE_Y - MENU_FIRST_ROW))
                        if (( i >= start && i < end )); then
                            selected=$i
                            printf '%s\n' "${view[$selected]}"
                            return 0
                        fi
                    fi
                    ;;
            esac
            continue
        fi

        case "$key" in
            $'\033[A'|k|K)
                (( total > 0 && selected > 0 )) && ((selected--)) || true
                ;;
            $'\033[B'|j|J)
                (( total > 0 && selected + 1 < total )) && ((selected++)) || true
                ;;
            $'\033[5~')
                selected=$((selected - MENU_PAGE_SIZE))
                (( selected < 0 )) && selected=0
                ;;
            $'\033[6~')
                selected=$((selected + MENU_PAGE_SIZE))
                (( total > 0 && selected >= total )) && selected=$((total - 1))
                ;;
            $'\033[H'|$'\033[1~') selected=0 ;;
            $'\033[F'|$'\033[4~') (( total > 0 )) && selected=$((total - 1)) ;;
            /)
                filter="$(prompt_filter 'Search: ')"
                selected=0
                ;;
            c|C)
                filter=""
                selected=0
                ;;
            $'\033'|q|Q)
                return 1
                ;;
            ""|$'\r'|$'\n')
                if (( total > 0 )); then
                    printf '%s\n' "${view[$selected]}"
                    return 0
                fi
                ;;
        esac
    done
}

wrap_content() {
    local width="$1"
    fold -s -w "$width"
}

view_text() {
    local title="$1" text="$2"
    local offset=0 lines cols page total max_offset key i
    local -a content=()

    while true; do
        lines="$(term_lines)"
        cols="$(term_cols)"
        page=$((lines - 6))
        (( page < 4 )) && page=4
        (( cols < 24 )) && cols=24

        mapfile -t content < <(printf '%s\n' "$text" | wrap_content "$((cols - 4))")
        total="${#content[@]}"
        max_offset=$((total - page))
        (( max_offset < 0 )) && max_offset=0
        (( offset > max_offset )) && offset=$max_offset
        (( offset < 0 )) && offset=0

        clear_screen
        printf '%s%s%s\n' "$C_BOLD$C_CYAN" "$title" "$C_RESET" >&3
        printf '%sLines %d-%d of %d%s\n\n' "$C_DIM" "$((total == 0 ? 0 : offset + 1))" "$((offset + page < total ? offset + page : total))" "$total" "$C_RESET" >&3

        for ((i = offset; i < offset + page && i < total; i++)); do
            printf '%s\n' "${content[$i]}" >&3
        done

        printf '\n%sUp/Down or wheel = scroll  PgUp/PgDn = page  Home/End = jump  Esc/q = back%s\n' "$C_DIM" "$C_RESET" >&3
        key="$(read_key || true)"

        if parse_mouse_event "$key"; then
            (( MOUSE_RELEASE == 1 )) && continue
            case "$MOUSE_BUTTON" in
                64) offset=$((offset - 3)) ;;
                65) offset=$((offset + 3)) ;;
            esac
        else
            case "$key" in
                $'\033[A'|k|K) ((offset--)) || true ;;
                $'\033[B'|j|J) ((offset++)) || true ;;
                $'\033[5~') offset=$((offset - page)) ;;
                $'\033[6~'|' ') offset=$((offset + page)) ;;
                $'\033[H'|$'\033[1~'|g) offset=0 ;;
                $'\033[F'|$'\033[4~'|G) offset=$max_offset ;;
                $'\033'|q|Q|b|B) return 0 ;;
            esac
        fi

        (( offset < 0 )) && offset=0
        (( offset > max_offset )) && offset=$max_offset
    done
}

view_file() {
    local file="$1"
    [[ -f "$file" ]] || {
        view_text "Extra Note" "File not found:\n$file"
        return
    }
    view_text "$(basename "$file" .md)" "$(cat -- "$file")"
}

system_context() {
    local kernel gpu shell_state
    kernel="$(uname -r 2>/dev/null || printf 'unknown')"
    gpu="unknown GPU"
    if command -v lspci >/dev/null 2>&1; then
        gpu="$(lspci 2>/dev/null | awk '/VGA compatible controller|3D controller|Display controller/ {sub(/^.*: /, ""); print; exit}')"
        [[ -n "$gpu" ]] || gpu="unknown GPU"
    fi
    if pgrep -x qs >/dev/null 2>&1 || pgrep -x quickshell >/dev/null 2>&1; then
        shell_state="Quickshell running"
    else
        shell_state="Quickshell not detected"
    fi
    printf 'Kernel: %s | %s | %s' "$kernel" "$gpu" "$shell_state"
}

article_text() {
    case "$1" in
        getting-started)
            cat <<'TEXT'
Awtarchy is an overlay for a normal Arch Linux installation. It manages the Hyprland/Quickshell environment, helper scripts, package selections, desktop integration, and maintenance tooling.

Start here:
  awtarchy
      Opens the maintenance menu.

  awtarchy update
      Updates managed Awtarchy files. Preserve mode is the normal choice when you have local configuration changes you want to keep.

  SUPER+ALT+BACKSPACE
      Opens Quickshell Quick Settings.

  SUPER+D or ALT+P
      Opens the Quickshell application launcher.

Use reset/reinstall when you intentionally want Awtarchy's managed defaults written back over managed configuration. Use updater preserve/review workflows when local changes matter.
TEXT
            ;;
        update-reset)
            cat <<'TEXT'
Awtarchy has two different maintenance intents:

UPDATE / PRESERVE
  Use this when you want new managed files while retaining local changes that differ from Awtarchy's previous baseline. The updater can preserve, review, or clean changed files depending on the selected mode.

RESET / REINSTALL
  Use this when you intentionally want Awtarchy's managed configuration restored to repository defaults. Treat it as destructive for managed configs.

Before a major migration, review updater output and keep the generated backups until the new session has been tested.
TEXT
            ;;
        login-tips)
            cat <<TEXT
Awtarchy Tips can open automatically at login.

Current state file:
  $DISABLE_FILE

If the file exists, autostart tips are disabled. The Home menu has a "Tips on Login" row that toggles this state without requiring a command.
TEXT
            ;;
        keybind-core)
            cat <<'TEXT'
Core launchers

  SUPER+D / ALT+P              Application launcher
  SUPER+RETURN                 Terminal
  SUPER+B                      Web browser
  SUPER+E                      PCManFM-Qt
  SUPER+SHIFT+E                Yazi
  SUPER+P                      Power menu
  SUPER+W                      Wallpaper picker
  SUPER+C                      Clipboard history
  SUPER+ALT+BACKSPACE          Quick Settings

Many actions have both ALT-oriented and SUPER-oriented forms. The noalt submap keeps the SUPER-oriented workflow available when ALT needs to pass through to an application.
TEXT
            ;;
        keybind-window)
            cat <<'TEXT'
Window and workspace basics

  SUPER+Q                      Close window
  SUPER+F                      Toggle floating
  SUPER+CTRL+F                 Toggle fullscreen
  SUPER+arrow / SUPER+hjkl     Move focus
  SUPER+SHIFT+arrow / hjkl     Move window
  SUPER+1..0                   Focus workspace 1..10
  SUPER+SHIFT+1..0             Send window to workspace
  SUPER+[ / SUPER+]            Previous / next workspace
  SUPER+mouse-left             Drag window
  SUPER+mouse-right            Resize window
TEXT
            ;;
        keybind-display)
            cat <<'TEXT'
Display controls

  SUPER+ALT+-                  Brightness -5%
  SUPER+ALT+=                  Brightness +5%

  SUPER+ALT+CTRL+-             Night Light warmer
  SUPER+ALT+CTRL+=             Night Light cooler
  SUPER+ALT+CTRL+BACKSPACE     Night Light toggle

  SUPER+ALT+[                  Vibrance down
  SUPER+ALT+]                  Vibrance up
  SUPER+ALT+\                  Vibrance toggle
  SUPER+ALT+CTRL+V             Vibrance toggle
TEXT
            ;;
        keybind-capture)
            cat <<'TEXT'
Capture and clipboard

  SUPER+C                      Clipboard history
  SUPER+S                      QR scan
  SUPER+SHIFT+S                Area screenshot
  SUPER+SHIFT+F                Fullscreen screenshot
  SUPER+SHIFT+D                Current-display screenshot
  SUPER+SHIFT+G                GIF capture

Quickshell flyouts also have per-surface capture privacy controls. Protected surfaces are hidden from screen capture while still remaining usable locally.
TEXT
            ;;
        keybind-submaps)
            cat <<'TEXT'
Submaps

  SUPER+ALT+N                  Toggle noalt mode
  SUPER+ALT+M                  Toggle mouse mode
  SUPER+ALT+V                  Toggle VM mode

noalt keeps SUPER-centric desktop controls available while reducing normal ALT bindings.

mouse mode exposes direct keyboard-driven resize/mouse operations.

VM mode remaps desktop actions behind SUPER+ALT so common guest shortcuts can pass through. VM mode intentionally keeps its own SUPER+ALT+CTRL+V behavior for Wiremix.
TEXT
            ;;
        quickshell-bar)
            cat <<'TEXT'
The Awtarchy bar is owned by Quickshell and configured per display.

Bar placement can be moved between top, bottom, left, and right. Holding Alt while dragging the bar lifts it and shows destination-edge feedback. Horizontal flicking allows left/right placement without requiring the pointer to physically reach the edge.

Quick Settings includes per-display bar appearance controls for thickness, text size, and icon size, plus reset and multi-display targeting.
TEXT
            ;;
        quickshell-settings)
            cat <<'TEXT'
Quick Settings opens with SUPER+ALT+BACKSPACE or directly from the bar.

It includes:
  - Internal and external display brightness
  - Bar visibility and edge placement
  - Night Light
  - Digital vibrance
  - Hyprland submap switching
  - Wallpaper picker
  - Awtarchy Tips
  - smtty
  - sched-ext controls

The gear panel stores Quick Settings size, text scale, icon scale, and capture visibility per display.
TEXT
            ;;
        quickshell-launcher)
            cat <<'TEXT'
The Quickshell application launcher replaces the older external launcher workflow.

Open it with SUPER+D or ALT+P. It reads desktop applications, supports search, and follows the focused display/bar placement behavior.

Firefox web-app desktop entries are treated as normal launchable desktop applications when their .desktop entries are valid.
TEXT
            ;;
        quickshell-notifications)
            cat <<'TEXT'
Notifications and clipboard history are native Awtarchy Quickshell surfaces.

Notifications support swipe-to-dismiss and close correctly when workspace/flyout state changes.

Clipboard history opens with SUPER+C and uses cliphist as the storage backend. Text and image clipboard entries are watched from the Hyprland session.
TEXT
            ;;
        quickshell-network)
            cat <<'TEXT'
Network and Bluetooth flyouts are native Quickshell surfaces.

Network uses NetworkManager state for Wi-Fi and wired connections, and exposes the Awtarchy WireGuard workflow from ~/vpn.

Bluetooth uses the Quickshell Bluetooth API for adapter, discovery, pairing, connection, and rfkill state.

Both surfaces support capture privacy controls so sensitive flyout contents can be hidden from recordings.
TEXT
            ;;
        quickshell-privacy)
            cat <<'TEXT'
Awtarchy uses Hyprland no-screen-share rules for sensitive windows and Quickshell surfaces.

Quickshell privacy controls are per surface. When protection is enabled, the protected flyout is excluded from capture rather than blacking the entire desktop.

Use the capture setting inside the relevant flyout only when you intentionally want that surface visible in recordings or screen shares.
TEXT
            ;;
        display-ddc)
            cat <<'TEXT'
Brightness uses Awtarchy's hypr-ddc-brightness.sh helper. Internal LVDS/eDP panels use
brightnessctl, while external monitors use ddcutil.

Quick Settings targets displays by Hyprland connector identity. The helper debounces repeated
changes, and its external-monitor path caches DDC bus mappings so rapid input does not have to
block on every physical DDC transaction.

Useful checks:
  brightnessctl -c backlight --list
  ddcutil detect
  hyprctl monitors

If an external monitor fails, verify its DDC/CI setting in the monitor OSD before changing
Awtarchy configuration.
TEXT
            ;;
        display-night)
            cat <<'TEXT'
Night Light is driven by hyprsunset and Awtarchy's hyprsunset_ctl.sh helper.

  SUPER+ALT+CTRL+-             Warmer
  SUPER+ALT+CTRL+=             Cooler
  SUPER+ALT+CTRL+BACKSPACE     Toggle

The Quick Settings card exposes the same controls and current temperature state.
TEXT
            ;;
        display-vibrance)
            cat <<'TEXT'
Digital vibrance uses Awtarchy's Hyprland screen shader helper.

  SUPER+ALT+[                  Decrease
  SUPER+ALT+]                  Increase
  SUPER+ALT+\                  Toggle
  SUPER+ALT+CTRL+V             Toggle

The helper manages the active vibrance shader and keeps the current value in the shader configuration. The VM submap keeps its own shortcut map instead of exposing this toggle.
TEXT
            ;;
        display-multi)
            cat <<'TEXT'
Awtarchy treats bar and flyout appearance as per-display state.

Quick Settings can edit the current display, copy appearance settings to selected displays, or reset a display to Awtarchy defaults. Bar thickness, text scale, and icon scale are independent values.

Use:
  hyprctl monitors

to confirm connector names and active monitor state when troubleshooting a multi-monitor layout.
TEXT
            ;;
        gaming-kernels)
            cat <<'TEXT'
Kernel guidance

Stock Arch kernel:
  Use it when you want the simplest supported Arch path. It is a better default than maintaining a custom-built kernel you do not specifically need.

linux-lts:
  Keep it available as a conservative fallback when useful.

linux-cachyos:
  Awtarchy supports CachyOS kernel naming in its GPU/kernel handling. It is the preferred optional performance-oriented path when you want a tuned kernel without maintaining a local custom kernel build.
TEXT
            ;;
        gaming-smtty)
            cat <<'TEXT'
Gaming helpers

smtty manages Steam/game sessions and launch options:
  SUPER+ALT+G                  Interactive smtty
  SUPER+ALT+L                  Launch last profile
  SUPER+ALT+O                  Write Steam launch options
  SUPER+ALT+K                  End session / restore cleanup

Awtarchy also ships GameMode configuration and supports gamescope-oriented launch workflows. Use per-game profiles instead of forcing one global launch string onto every title.
TEXT
            ;;
        gaming-streaming)
            cat <<'TEXT'
Sunshine / Moonlight

Awtarchy includes:
  ~/.config/hypr/scripts/sunshine-moonlight-fix.sh

The helper is intended for display/session adjustments around Sunshine streaming. The matching Extra Note contains additional troubleshooting context.
TEXT
            ;;
        packages-selector)
            cat <<'TEXT'
The Awtarchy installer has built-in package selection for Arch repository packages, AUR packages, and Flatpaks.

The terminal UI is implemented directly in Bash. It does not require fzf, gum, dialog, or whiptail.

Arch package categories can be edited before install. AUR additions are resolved against AUR search results rather than blindly accepting an arbitrary package string.
TEXT
            ;;
        packages-aur)
            cat <<'TEXT'
AUR Guard wraps Awtarchy's yay/AUR workflow so AUR package installation is explicit and isolated from the normal Arch repository package stage.

Keep Arch repository packages in the Arch package selector when they exist there. Use the AUR path only for packages that actually require it.

For cleanup guidance, see the AUR and Arch orphan-removal Extra Notes.
TEXT
            ;;
        packages-orphans)
            cat <<'TEXT'
Package cleanup can remove software you still rely on if it is treated as an orphan incorrectly.

Awtarchy keeps dedicated Extra Notes for Arch and AUR orphan cleanup. Read the relevant note before executing removal commands, especially on systems with alternate kernels or manually installed tooling.
TEXT
            ;;
        maintenance-update)
            cat <<'TEXT'
Normal maintenance starts with:
  awtarchy update

Use preserve behavior when local configuration edits matter. The updater compares the previous managed baseline, your live file, and the new target so unchanged managed files can update cleanly while diverged files can be preserved/reviewed.

Use clean/reset behavior only when you intend to replace local managed changes.
TEXT
            ;;
        maintenance-review)
            cat <<'TEXT'
Awtarchy updater backups are designed for manual review and recovery.

Useful maintenance entry points include:
  awtarchy update
  awtarchy review
  awtarchy clean-backups --dry-run

Review generated backups before deleting them after a large shell migration.
TEXT
            ;;
        maintenance-reset)
            cat <<'TEXT'
Reset/reinstall semantics are intentionally different from updater preserve mode.

A reset/reinstall writes repository-managed defaults back over managed configuration. Use it when you want a known Awtarchy baseline, not when you are trying to preserve a personalized managed file.

For day-to-day updates on a customized system, use updater preserve/review workflows instead.
TEXT
            ;;
        maintenance-cleaner)
            cat <<'TEXT'
The backup cleaner can scan Awtarchy-managed locations and supports dry-run, age filtering, archive handling, and interactive keep/delete review.

Start safely:
  awtarchy clean-backups --dry-run

Only remove backups once the corresponding updated configuration has been tested.
TEXT
            ;;
        networking-network)
            cat <<'TEXT'
The Quickshell Network flyout uses NetworkManager for normal Wi-Fi and wired connection management.

It can show local interface/router information and can request public IP information when the user explicitly asks for it. The Awtarchy Tips TUI itself does not perform public-IP or telemetry network requests.
TEXT
            ;;
        networking-wireguard)
            cat <<'TEXT'
Awtarchy's Quickshell WireGuard workflow uses:
  ~/vpn

Put the WireGuard profiles you want exposed to the Network flyout in that directory. The flyout can list, activate/deactivate, and edit those profiles through Awtarchy's helper.

Keep private keys protected. Do not paste complete WireGuard configurations into public bug reports.
TEXT
            ;;
        networking-bluetooth)
            cat <<'TEXT'
The Quickshell Bluetooth flyout handles adapter power/rfkill state, discovery, pairing, connection, and device state without depending on blueman-applet.

If Bluetooth disappears entirely, first check:
  systemctl status bluetooth
  rfkill list bluetooth
TEXT
            ;;
        troubleshoot-hypr)
            cat <<'TEXT'
Hyprland configuration check

Run:
  hyprctl configerrors

No output is the normal clean result. If errors appear after an Awtarchy update, identify the exact key/rule first instead of replacing your entire live Hyprland configuration just to test one fix.
TEXT
            ;;
        troubleshoot-shell)
            cat <<'TEXT'
Restart Quickshell cleanly:
  ~/.config/hypr/scripts/quickshell.sh restart

Check status:
  ~/.config/hypr/scripts/quickshell.sh status

Log:
  ~/.cache/awtarchy/quickshell.log

Awtarchy performs a full Quickshell process restart when component discovery requires more than a soft QML reload.
TEXT
            ;;
        troubleshoot-portals)
            cat <<'TEXT'
Screen sharing, file pickers, and some Wayland integration depend on XDG portals.

Awtarchy includes:
  ~/.config/hypr/scripts/portal_fixup.sh

Useful checks:
  systemctl --user status xdg-desktop-portal.service
  systemctl --user status xdg-desktop-portal-hyprland.service

Fix the portal/backend mismatch before adding random environment overrides.
TEXT
            ;;
        troubleshoot-ddc)
            cat <<'TEXT'
DDC troubleshooting

  ddcutil detect
  hyprctl monitors

External monitors must expose DDC/CI; compare their detected DDC bus with the Hyprland
connector Awtarchy is targeting. Laptop LVDS/eDP panels use the kernel backlight through
brightnessctl and do not require DDC/CI.
TEXT
            ;;
        troubleshoot-update)
            cat <<'TEXT'
If an update produces a bad managed file, do not erase the updater evidence first.

1. Keep the generated backup.
2. Review the live file against the backup/new target.
3. Restore only the affected file if needed.
4. Re-run the relevant syntax/config check.

For Hyprland, use hyprctl configerrors. For Bash scripts, use bash -n. For Awtarchy's main maintenance path, dry-run/review modes should be used before destructive cleanup.
TEXT
            ;;
        *) printf 'No article is available for this item.\n' ;;
    esac
}

show_article() {
    local id="$1" title="$2"
    view_text "$title" "$(article_text "$id")"
}

run_article_menu() {
    local title="$1" labels_name="$2" ids_name="$3"
    local -n labels_ref="$labels_name"
    local -n ids_ref="$ids_name"
    local choice menu_key="article:$labels_name"

    while choice="$(menu_select "$title" "$labels_name" "" "${MENU_SELECTIONS[$menu_key]:-0}")"; do
        MENU_SELECTIONS["$menu_key"]="$choice"
        show_article "${ids_ref[$choice]}" "${labels_ref[$choice]}"
    done
}

menu_extra_notes() {
    local choice file
    local menu_key="extra-notes"
    local -a files=() labels=()

    if [[ ! -d "$EXTRA_NOTES_DIR" ]]; then
        view_text "Extra Notes" "Extra Notes directory not found:\n$EXTRA_NOTES_DIR\n\nSet AWTARCHY_REPO_DIR if your Awtarchy checkout is stored somewhere else."
        return
    fi

    while true; do
        files=()
        labels=()
        while IFS= read -r -d '' file; do
            files+=("$file")
            labels+=("$(basename "$file" .md | tr '_' ' ')")
        done < <(find "$EXTRA_NOTES_DIR" -maxdepth 1 -type f -name '*.md' -print0 | sort -z)

        if (( ${#files[@]} == 0 )); then
            view_text "Extra Notes" "No Markdown notes were found in:\n$EXTRA_NOTES_DIR"
            return
        fi

        choice="$(menu_select "Extra Notes" labels "Local files from $EXTRA_NOTES_DIR" "${MENU_SELECTIONS[$menu_key]:-0}")" || return
        MENU_SELECTIONS["$menu_key"]="$choice"
        view_file "${files[$choice]}"
    done
}

toggle_login_tips() {
    if [[ -e "$DISABLE_FILE" ]]; then
        rm -f -- "$DISABLE_FILE"
    else
        mkdir -p "$(dirname "$DISABLE_FILE")"
        : >"$DISABLE_FILE"
    fi
}

run_tui() {
    open_tty
    enable_mouse

    local choice login_state context
    local -a home=()

    local -a getting_labels=(
        "Awtarchy Overview"
        "Update vs Reset"
        "Tips on Login"
    )
    local -a getting_ids=(getting-started update-reset login-tips)

    local -a keybind_labels=(
        "Core Launchers"
        "Windows and Workspaces"
        "Display Controls"
        "Capture and Clipboard"
        "Submaps"
    )
    local -a keybind_ids=(keybind-core keybind-window keybind-display keybind-capture keybind-submaps)

    local -a quickshell_labels=(
        "Bar Basics"
        "Quick Settings"
        "Application Launcher"
        "Notifications and Clipboard"
        "Network and Bluetooth"
        "Capture Privacy"
    )
    local -a quickshell_ids=(quickshell-bar quickshell-settings quickshell-launcher quickshell-notifications quickshell-network quickshell-privacy)

    local -a display_labels=(
        "Brightness and DDC"
        "Night Light"
        "Digital Vibrance"
        "Multi-Monitor State"
    )
    local -a display_ids=(display-ddc display-night display-vibrance display-multi)

    local -a gaming_labels=(
        "Kernel Choices"
        "smtty, GameMode, and gamescope"
        "Sunshine and Moonlight"
    )
    local -a gaming_ids=(gaming-kernels gaming-smtty gaming-streaming)

    local -a package_labels=(
        "Package Selector"
        "AUR Guard"
        "Safe Orphan Cleanup"
    )
    local -a package_ids=(packages-selector packages-aur packages-orphans)

    local -a maintenance_labels=(
        "Normal Updates"
        "Review and Backups"
        "Reset / Reinstall"
        "Backup Cleaner"
    )
    local -a maintenance_ids=(maintenance-update maintenance-review maintenance-reset maintenance-cleaner)

    local -a networking_labels=(
        "Network Flyout"
        "WireGuard Profiles"
        "Bluetooth"
    )
    local -a networking_ids=(networking-network networking-wireguard networking-bluetooth)

    local -a troubleshooting_labels=(
        "Hyprland Config Errors"
        "Restart Quickshell"
        "XDG Portals"
        "DDC / Brightness"
        "Update Recovery"
    )
    local -a troubleshooting_ids=(troubleshoot-hypr troubleshoot-shell troubleshoot-portals troubleshoot-ddc troubleshoot-update)

    while true; do
        if [[ -e "$DISABLE_FILE" ]]; then
            login_state="Disabled"
        else
            login_state="Enabled"
        fi
        context="$(system_context)"
        home=(
            "Getting Started"
            "Essential Keybinds"
            "Quickshell"
            "Display"
            "Gaming"
            "Packages / AUR"
            "Maintenance"
            "Networking"
            "Troubleshooting"
            "Extra Notes"
            "Tips on Login: $login_state"
            "Quit"
        )

        choice="$(menu_select "Awtarchy Tips" home "$context" "${MENU_SELECTIONS[home]:-0}")" || break
        MENU_SELECTIONS["home"]="$choice"
        case "$choice" in
            0) run_article_menu "Getting Started" getting_labels getting_ids ;;
            1) run_article_menu "Essential Keybinds" keybind_labels keybind_ids ;;
            2) run_article_menu "Quickshell" quickshell_labels quickshell_ids ;;
            3) run_article_menu "Display" display_labels display_ids ;;
            4) run_article_menu "Gaming" gaming_labels gaming_ids ;;
            5) run_article_menu "Packages / AUR" package_labels package_ids ;;
            6) run_article_menu "Maintenance" maintenance_labels maintenance_ids ;;
            7) run_article_menu "Networking" networking_labels networking_ids ;;
            8) run_article_menu "Troubleshooting" troubleshooting_labels troubleshooting_ids ;;
            9) menu_extra_notes ;;
            10) toggle_login_tips ;;
            11) break ;;
        esac
    done
}

spawn_terminal() {
    if [[ -x "$DEFAULT_TERMINAL" ]]; then
        exec "$DEFAULT_TERMINAL" --class awtarchy-tips-tui -- "$0" --tui
    fi

    if command -v alacritty >/dev/null 2>&1; then
        exec alacritty --class awtarchy-tips-tui,awtarchy-tips-tui --title awtarchy-tips-tui -e "$0" --tui
    fi

    printf 'awtarchy-tips-tui: no supported terminal launcher found\n' >&2
    exit 1
}

case "${1:-}" in
    --autostart)
        [[ -e "$DISABLE_FILE" ]] && exit 0
        run_tui
        ;;
    --tui)
        run_tui
        ;;
    -h|--help)
        cat <<'HELP'
usage: awtarchy-tips-tui.sh [--tui|--autostart]

Without arguments, opens Awtarchy Tips in the configured Awtarchy terminal.
--tui runs directly in the current terminal.
--autostart exits silently when login tips are disabled.
HELP
        ;;
    "")
        spawn_terminal
        ;;
    *)
        printf 'awtarchy-tips-tui: unknown option: %s\n' "$1" >&2
        exit 2
        ;;
esac