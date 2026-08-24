--  ╔══════════════════════════════════════════════════════════════╗
--  ║  STOA LINUX — Drive pill                                     ║
--  ║  "Nothing belongs to you but your own judgement." — Epictetus ║
--  ╚══════════════════════════════════════════════════════════════╝
--
--  Shows how many rclone remotes are mounted. Colour and glyph follow
--  the same rules the v4 QML widget used:
--
--      all mounted   secondary   cloud-upload
--      some mounted  tertiary    cloud-upload
--      none mounted  error       cloud-off
--
--  Written in the Lua 5.4-compatible subset of Luau (no type annotations,
--  no if-expressions) so the CI lua step can actually parse it — luac5.4
--  rejects Luau-only syntax, and CI has no Luau front end.
--
--  Data comes from ~/.local/bin/stoa-drive-status, unchanged from v4 —
--  it already emits JSON:
--      {"available":bool,"total":N,"mounted":M,"drives":[...]}

local STATUS_BIN = "$HOME/.local/bin/stoa-drive-status"

local state = {
    available = false,
    total = 0,
    mounted = 0,
    drives = {},
    -- Nothing has come back yet; the first paint says so rather than
    -- claiming zero drives, which would read as "all unmounted".
    loaded = false,
}

-- getConfig reads THIS plugin's own [[setting]] entries from plugin.toml
-- (context->settings, keyed by the `key` field). getSetting is a
-- different function entirely: it reads a dotted path out of the shell's
-- own ~/.config/noctalia/config.toml (host->api().configSnapshot()), and
-- "poll_seconds"/"show_badge" are not keys there, so it always returned
-- nil — silently, since a miss only logs a warning, not an error. The
-- plugin still worked (both getters had a same-type fallback), but the
-- two declared settings were dead: nothing the user set in Settings ever
-- reached this script.
local function pollSeconds()
    local configured = noctalia.getConfig("poll_seconds")
    if type(configured) == "number" and configured >= 5 then
        return configured
    end
    return 30
end

local function showBadge()
    local configured = noctalia.getConfig("show_badge")
    if type(configured) == "boolean" then
        return configured
    end
    return true
end

-- Human summary reused by both the label and the tooltip.
local function summary()
    if not state.loaded then
        return "…"
    end
    if not state.available then
        return "rclone not installed"
    end
    if state.total == 0 then
        return "No rclone remotes configured"
    end
    if state.mounted == state.total then
        return string.format("All drives mounted (%d/%d)", state.total, state.total)
    end
    if state.mounted > 0 then
        return string.format("%d / %d drives mounted", state.mounted, state.total)
    end
    return "No drives mounted — click to manage"
end

local function tooltip()
    local lines = { summary() }
    for _, drive in ipairs(state.drives) do
        local mark = "○"
        if drive.mounted then mark = "●" end
        local cache = drive.cache_human or "0B"
        local pct = drive.cache_pct or 0
        lines[#lines + 1] =
            string.format("%s %s (%s) — cache %s / %d%%", mark, drive.name, drive.type, cache, pct)
    end
    return table.concat(lines, "\n")
end

local function paint()
    -- cloud-off only once we know there is something to be off: before the
    -- first result, and when rclone is absent, the neutral glyph is honest.
    if state.loaded and state.available and state.total > 0 and state.mounted == 0 then
        barWidget.setGlyph("cloud-off")
        barWidget.setGlyphColor("error")
    else
        barWidget.setGlyph("cloud-upload")
        if not state.loaded or not state.available then
            barWidget.setGlyphColor("on_surface_variant")
        elseif state.total > 0 and state.mounted == state.total then
            barWidget.setGlyphColor("secondary")
        else
            barWidget.setGlyphColor("tertiary")
        end
    end

    -- The v4 widget carried a "m/t" badge overlay. v5 bar widgets have no
    -- badge primitive, so the same information goes in the label — shown
    -- only while something is unmounted, which is when it matters.
    if showBadge() and state.loaded and state.available
        and state.total > 0 and state.mounted < state.total then
        barWidget.setText(string.format("%d/%d", state.mounted, state.total))
    else
        barWidget.setText("")
    end

    barWidget.setTooltip(tooltip())
end

local function refresh()
    noctalia.runAsync(STATUS_BIN, function(result)
        state.loaded = true

        if result.exitCode ~= 0 or result.stdout == "" then
            state.available = false
            state.total = 0
            state.mounted = 0
            state.drives = {}
            paint()
            return
        end

        local ok, parsed = pcall(noctalia.json.decode, result.stdout)
        if not ok or type(parsed) ~= "table" then
            -- Malformed output: report unknown rather than silently
            -- painting a healthy pill over a broken producer.
            state.available = false
            state.total = 0
            state.mounted = 0
            state.drives = {}
            paint()
            return
        end

        state.available = parsed.available == true
        state.total = parsed.total or 0
        state.mounted = parsed.mounted or 0
        state.drives = parsed.drives or {}
        paint()
    end)
end

function update()
    noctalia.setUpdateInterval(pollSeconds() * 1000)
    refresh()
end

-- Per-button click callbacks. PluginWidget::create() (plugin_widget.cpp)
-- dispatches BTN_LEFT/BTN_RIGHT/BTN_MIDDLE to exactly these three global
-- names — onClick/onRightClick/onMiddleClick — for a [[widget]] (bar
-- widget) entry. `onActivate` is a *different* entry kind's callback
-- (plugin_launcher_provider.cpp, for launcher search results); it is
-- never invoked for a bar widget. That earlier mix-up is why clicking
-- did nothing: the runtime looked for onClick, found no such global, and
-- silently skipped the call — no error, nothing in the log, just no
-- click. Confirmed by reading plugin_widget.cpp's InputArea::setOnClick
-- handler directly rather than trusting the docs a second time.
function onClick()
    -- stoa-drive is the rofi TUI; it owns mount/unmount/open/settings.
    noctalia.runAsync("$HOME/.local/bin/stoa-drive")
end

function onMiddleClick()
    noctalia.runAsync("$HOME/.local/bin/stoa-drive mount-all", function(result)
        if result.exitCode == 0 then
            noctalia.notify("Stoa Drive", "Mounted all remotes")
        else
            noctalia.notifyError("Stoa Drive", "Could not mount all remotes")
        end
        refresh()
    end)
end

function onRightClick()
    noctalia.runAsync("xdg-open $HOME/Drive")
end
