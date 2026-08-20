-- ╔══════════════════════════════════════════════════════════════╗
-- ║  STOA LINUX — Hyprland                                       ║
-- ║  "Order is the first law of heaven." — Marcus Aurelius       ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- Hyprland 0.55+ Lua config. hyprlang (hyprland.conf) is deprecated
-- upstream and gets dropped a release or two after 0.55, so this file
-- is the single source of truth for the Stoa Hyprland session.
-- Reference: https://wiki.hypr.land/Configuring/Start/

-- ── Monitor ──
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1,
})

-- ── Environment Variables ──
hl.env("XCURSOR_SIZE", "24")
hl.env("XCURSOR_THEME", "Colloid-cursors")
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("QT_QPA_PLATFORMTHEME", "qt5ct")
hl.env("QT_STYLE_OVERRIDE", "Fusion")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")
hl.env("GTK_THEME", "Adwaita:dark")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

-- ── Input ──
hl.config({
    input = {
        kb_layout          = "br",
        kb_variant         = "abnt2",
        follow_mouse       = 1,
        sensitivity        = 0,
        numlock_by_default = true,

        touchpad = {
            natural_scroll = true,
        },
    },
})

-- ── Stoic Palette ──
-- stoa-settings rewrites the rgb(RRGGBB) literals below when the theme
-- colors change, so keep them spelled out rather than computed.
local colors = {
    bg         = "rgb(211e19)",
    bg_light   = "rgb(2d2921)",
    fg         = "rgb(d4cfc4)",
    fg_dim     = "rgb(a89f91)",
    bronze     = "rgb(c49a5c)",
    gold       = "rgb(d4a84b)",
    olive      = "rgb(8a9a6c)",
    terracotta = "rgb(b36b5a)",
    stone      = "rgb(6e6a62)",
}

-- ── Appearance ──
hl.config({
    general = {
        gaps_in     = 3,
        gaps_out    = 6,
        border_size = 2,

        col = {
            active_border   = colors.bronze,
            inactive_border = colors.bg_light,
        },

        layout = "dwindle",
    },

    decoration = {
        rounding = 4,

        blur = {
            enabled = true,
            size    = 4,
            passes  = 2,
        },

        shadow = {
            enabled      = true,
            range        = 12,
            offset       = { -7, -7 },
            render_power = 3,
            color        = "rgba(0a090880)",
        },

        inactive_opacity = 0.90,
        active_opacity   = 1.0,
    },

    animations = {
        enabled = true,
    },

    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
    },
})

hl.curve("stoa", { type = "bezier", points = { { 0.25, 0.8 }, { 0.25, 1.0 } } })

hl.animation({ leaf = "windows",    enabled = true, speed = 4, bezier = "stoa" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 4, bezier = "stoa", style = "popin 80%" })
hl.animation({ leaf = "border",     enabled = true, speed = 6, bezier = "default" })
hl.animation({ leaf = "fade",       enabled = true, speed = 4, bezier = "default" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 3, bezier = "stoa" })

-- ── Keybinds ──
local mod = "SUPER"

hl.bind(mod .. " + Return", hl.dsp.exec_cmd("kitty"))
hl.bind(mod .. " + Space", hl.dsp.exec_cmd("noctalia msg panel-toggle launcher"))
hl.bind(mod .. " + Q", hl.dsp.window.close())
hl.bind(mod .. " + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
hl.bind(mod .. " + SHIFT + Space", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. " + CTRL + E", hl.dsp.exit())
hl.bind(mod .. " + CTRL + R", hl.dsp.exec_cmd("~/.local/bin/stoa-bar-toggle"))

-- Alt+Tab — hyprswitch visual switcher (thumbnails, grouped by workspace).
-- Hold Alt and tap Tab to cycle through every window across all workspaces;
-- release Alt to focus. Alt+Shift+Tab cycles backwards. The daemon is
-- started in the Autostart section below.
hl.bind("ALT + Tab", hl.dsp.exec_cmd(
    "hyprswitch gui --mod-key alt --key tab --max-switch-offset 9 --hide-active-window-border"))
hl.bind("ALT + SHIFT + Tab", hl.dsp.exec_cmd(
    "hyprswitch gui --mod-key alt --key tab --max-switch-offset 9 --hide-active-window-border -r"))

-- ── Apps ──
hl.bind(mod .. " + A", hl.dsp.exec_cmd("~/.local/bin/stoa-store"))
hl.bind(mod .. " + B", hl.dsp.exec_cmd(
    "brave --password-store=basic --enable-features=UseOzonePlatform --ozone-platform=wayland"))
hl.bind(mod .. " + C", hl.dsp.exec_cmd("qalculate-gtk"))
hl.bind(mod .. " + SHIFT + E", hl.dsp.exec_cmd("kitty -e lf"))
hl.bind(mod .. " + E", hl.dsp.exec_cmd("thunar"))
hl.bind(mod .. " + N", hl.dsp.exec_cmd("kitty -e btop"))
hl.bind(mod .. " + O", hl.dsp.exec_cmd("obsidian"))
hl.bind(mod .. " + S", hl.dsp.exec_cmd("~/.local/bin/stoa-settings"))
hl.bind(mod .. " + W", hl.dsp.exec_cmd("~/.local/bin/stoa-winapps"))
hl.bind(mod .. " + G", hl.dsp.exec_cmd("~/.local/bin/dfm"))
hl.bind(mod .. " + slash", hl.dsp.exec_cmd("~/.local/bin/stoa-keybinds-toggle"))

-- ── Lock Screen ──
hl.bind(mod .. " + Escape", hl.dsp.exec_cmd("noctalia msg lock"))

-- ── Navigation (vim) ──
hl.bind(mod .. " + H", hl.dsp.focus({ direction = "l" }))
hl.bind(mod .. " + J", hl.dsp.focus({ direction = "d" }))
hl.bind(mod .. " + K", hl.dsp.focus({ direction = "u" }))
hl.bind(mod .. " + L", hl.dsp.focus({ direction = "r" }))

hl.bind(mod .. " + SHIFT + H", hl.dsp.window.move({ direction = "l" }))
hl.bind(mod .. " + SHIFT + J", hl.dsp.window.move({ direction = "d" }))
hl.bind(mod .. " + SHIFT + K", hl.dsp.window.move({ direction = "u" }))
hl.bind(mod .. " + SHIFT + L", hl.dsp.window.move({ direction = "r" }))

-- ── Resize ──
hl.bind(mod .. " + R", hl.dsp.submap("resize"))

hl.define_submap("resize", function()
    hl.bind("H", hl.dsp.window.resize({ x = -20, y = 0, relative = true }), { repeating = true })
    hl.bind("J", hl.dsp.window.resize({ x = 0, y = 20, relative = true }), { repeating = true })
    hl.bind("K", hl.dsp.window.resize({ x = 0, y = -20, relative = true }), { repeating = true })
    hl.bind("L", hl.dsp.window.resize({ x = 20, y = 0, relative = true }), { repeating = true })

    hl.bind("Return", hl.dsp.submap("reset"))
    hl.bind("Escape", hl.dsp.submap("reset"))
end)

-- ── Workspaces (I to X) ──
for i = 1, 10 do
    local key = i % 10 -- workspace 10 sits on the `0` key
    hl.bind(mod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind(mod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- ── Mouse ──
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- ── Volume ──
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("noctalia msg volume-up"), { repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("noctalia msg volume-down"), { repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("noctalia msg volume-mute"))

-- ── Brightness ──
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("noctalia msg brightness-up"), { repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("noctalia msg brightness-down"), { repeating = true })

-- ── Display toggle (laptop / extend / mirror) ──
-- XF86Display = Fn+F7 on most Acer/ASUS laptops (when the EC routes it
-- through the i8042 keyboard). Super+P is the Win+P-style fallback
-- for laptops whose Fn key is dead in Linux.
hl.bind("XF86Display", hl.dsp.exec_cmd("~/.local/bin/stoa-display"))
hl.bind(mod .. " + P", hl.dsp.exec_cmd("~/.local/bin/stoa-display"))

-- ── CapsLock / NumLock ──
-- Noctalia's LockKeys widget shows current state in the bar and its
-- OSD module fires on lock-state changes — no WM-level binding needed.

-- ── Capture (screenshot + recording) ──
hl.bind("Print", hl.dsp.exec_cmd("~/.local/bin/stoa-capture"))

-- ── Clipboard ──
hl.bind(mod .. " + V", hl.dsp.exec_cmd("noctalia msg panel-toggle clipboard"))
-- Super+Shift+V (pin) is gone: it drove cliphist, which no longer runs.
-- Noctalia v5 pins from inside the clipboard panel (Super+V) and exposes
-- no pin IPC command, so there is nothing to bind here.
hl.bind(mod .. " + SHIFT + B", hl.dsp.exec_cmd("noctalia msg clipboard-clear"))

-- ── Stoatools ──
hl.bind(mod .. " + SHIFT + T", hl.dsp.exec_cmd("~/.local/bin/stoa-ocr"))
hl.bind(mod .. " + SHIFT + P", hl.dsp.exec_cmd("~/.local/bin/stoa-paste"))
hl.bind(mod .. " + SHIFT + S", hl.dsp.exec_cmd("~/.local/bin/stoa-predict toggle"))

-- ── Rules ──
-- Media, browsers and readers keep full opacity so the global
-- inactive_opacity of 0.90 never washes out video, art or text.
local function opaque(app)
    hl.window_rule({
        name    = "opaque-" .. app,
        match   = { class = "^(" .. app .. ")$" },
        opacity = "1.0 override 1.0 override",
    })
end

for _, app in ipairs({
    -- Browsers & media
    "brave-browser",
    "firefox",
    "mpv",
    "imv",
    "zathura",
    "obsidian",
    -- Steam
    "steam",
    -- Calibre (eBooks)
    "calibre",
    "calibre-ebook-viewer",
    -- YACReader (Comics)
    "YACReader",
    "YACReaderLibrary",
}) do
    opaque(app)
end

-- ── Qalculate ──
hl.window_rule({
    name   = "qalculate-float",
    match  = { class = "^(qalculate-gtk)$" },
    float  = true,
    size   = { 420, 540 },
    center = true,
})

-- ── Steam ──
hl.window_rule({
    name  = "steam-friends-float",
    match = { class = "^(steam)$", title = "^(Friends List)$" },
    float = true,
})

hl.window_rule({
    name  = "steam-settings-float",
    match = { class = "^(steam)$", title = "^(Steam Settings)$" },
    float = true,
})

hl.window_rule({
    name      = "steam-main-workspace",
    match     = { class = "^(steam)$", title = "^(Steam)$" },
    workspace = "9 silent",
})

-- ── Autostart ──
hl.on("hyprland.start", function()
    -- Phase 1 — shell + wallpaper + hyprlock fire immediately so the bar
    -- (noctalia) and background paint before anything else hits the GPU.
    -- Hyprlock first — when the session is launched via autologin on tty1
    -- (see setup/enable-stoa-greeter.sh) this turns hyprlock into the boot
    -- login screen. Outside that flow it just locks immediately on session
    -- start, which is harmless.
    hl.exec_cmd("hyprlock") -- stoa-greetd toggles this line
    hl.exec_cmd("~/.local/bin/stoa-bar")
    -- Wallpaper is owned by Noctalia v5 ([wallpaper] in config.toml), which
    -- also gives us rotation and transitions. swaybg is no longer started.
    -- Noctalia likewise owns notifications via org.freedesktop.Notifications.
    -- Scripts call notify-send; toasts land in Noctalia's notification panel.

    -- Phase 2 — data producers consumed by bar widgets (drive mount status).
    -- The old `sleep 3` here was a race against the bar rendering. stoa-doctor
    -- has moved to Noctalia's [hooks] started, which fires when the shell is
    -- actually up — no guessing. stoa-drive keeps a short delay because it
    -- waits on udisks, not on the bar.
    hl.exec_cmd("bash -c 'sleep 3; ~/.local/bin/stoa-drive mount-all'")

    -- Phase 3 — background services not consumed by bar pills.
    -- hyprswitch daemon — backs the Alt+Tab visual window switcher.
    -- --show-title shows window titles; --workspaces-per-row groups the
    -- preview grid by workspace; --size-factor scales the thumbnails.
    hl.exec_cmd("hyprswitch init --show-title --workspaces-per-row 5 --size-factor 5.5")
    -- Noctalia owns notifications via org.freedesktop.Notifications; do NOT
    -- also start dunst — two daemons would fight over the DBus name. The
    -- dunstify binary still works, talking to whichever daemon is on the bus.
    -- hl.exec_cmd("dunst -config ~/.config/dunst/dunstrc")
    -- Clipboard history is owned by Noctalia v5 (shell.clipboard_enabled), so
    -- the three cliphist watchers that used to live here are gone.
    hl.exec_cmd("~/.local/bin/stoa-quotes-sync tick")
end)

-- >>> stoa-gpu-setup: env (auto-managed) >>>
-- Hybrid laptop (amd iGPU + NVIDIA dGPU, muxless HDMI):
-- List BOTH cards — NVIDIA first so the dGPU is the primary KMS
-- device (HDMI on the dGPU port lights up), iGPU second so the
-- laptop's eDP panel (wired to the iGPU) is also enumerated.
hl.env("AQ_DRM_DEVICES", "/dev/dri/nvidia-card:/dev/dri/igpu-card")
hl.env("WLR_DRM_DEVICES", "/dev/dri/nvidia-card:/dev/dri/igpu-card")
hl.env("__NV_PRIME_RENDER_OFFLOAD", "1")
hl.env("__VK_LAYER_NV_optimus", "NVIDIA_only")
hl.env("LIBVA_DRIVER_NAME", "radeonsi")
hl.env("WLR_NO_HARDWARE_CURSORS", "1")
hl.env("__GL_GSYNC_ALLOWED", "1")
hl.env("__GL_VRR_ALLOWED", "1")
-- <<< stoa-gpu-setup: env (auto-managed) <<<
