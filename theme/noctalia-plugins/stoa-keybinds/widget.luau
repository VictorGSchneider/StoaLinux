--  ╔══════════════════════════════════════════════════════════════╗
--  ║  STOA LINUX — Keybinds pill                                   ║
--  ║  "Learn the rules so you know how to break them." — attrib.    ║
--  ╚══════════════════════════════════════════════════════════════╝
--
--  A keyboard icon in the bar. Left click opens the cheatsheet panel
--  (panel.luau, entry id "cheatsheet"); right click shows the same
--  cheatsheet in the yad dialog Super+/ uses; the tooltip lists the
--  sections so the icon says what is inside before it is opened.
--
--  Written in the Lua 5.4-compatible subset of Luau (no type annotations,
--  no if-expressions) so the CI lua step can actually parse it — luac5.4
--  rejects Luau-only syntax, and CI has no Luau front end.
--
--  Data comes from ~/.local/bin/stoa-keybinds-bar:
--      text   the full cheatsheet as plain text (sections start with "▸")
--      bar    {"text": "⏎ Term • ␣ Launcher • ...", "tooltip": ...}
--             or an empty line when STOA_SHOW_KEYBINDS is not "true"

local KEYBINDS_BIN = "$HOME/.local/bin/stoa-keybinds-bar"
local TOGGLE_BIN   = "$HOME/.local/bin/stoa-keybinds-toggle"

local state = {
    sections = {},   -- section titles, in order
    binds = 0,
    apps = "",       -- compact apps line, "" when hidden
}

-- getConfig reads THIS plugin's own [[setting]] entries from plugin.toml
-- (not getSetting, which reads the shell's own config.toml).
local function configIcon()
    local configured = noctalia.getConfig("icon")
    if type(configured) == "string" and configured ~= "" then
        return configured
    end
    return "keyboard"
end

local function showApps()
    local configured = noctalia.getConfig("show_apps")
    if type(configured) == "boolean" then
        return configured
    end
    return false
end

local function tooltip()
    if #state.sections == 0 then
        return "Stoa Keybinds — click to open"
    end
    return string.format("Stoa Keybinds — %d binds\n%s",
        state.binds, table.concat(state.sections, " · "))
end

local function paint()
    barWidget.setGlyph(configIcon())
    barWidget.setGlyphColor("on_surface_variant")
    if showApps() and state.apps ~= "" then
        barWidget.setText(state.apps)
    else
        barWidget.setText("")
    end
    barWidget.setTooltip(tooltip())
end

-- Section titles and bind count from the plain-text cheatsheet. A bind
-- line is indented and has its key and description split by 2+ spaces.
local function parseText(text)
    local sections, binds = {}, 0
    for line in string.gmatch(text, "[^\n]+") do
        local title = string.match(line, "^▸%s*(.+)$")
        if title then
            sections[#sections + 1] = title
        elseif string.match(line, "^%s+%S.-%s%s+%S") then
            binds = binds + 1
        end
    end
    state.sections = sections
    state.binds = binds
end

local function refresh()
    noctalia.runAsync(KEYBINDS_BIN .. " text", function(result)
        if result.exitCode == 0 and result.stdout ~= "" then
            parseText(result.stdout)
        end
        paint()
    end)

    if not showApps() then
        state.apps = ""
        return
    end
    noctalia.runAsync(KEYBINDS_BIN .. " bar", function(result)
        state.apps = ""
        if result.exitCode == 0 and result.stdout ~= "" then
            local ok, parsed = pcall(noctalia.json.decode, result.stdout)
            if ok and type(parsed) == "table" and type(parsed.text) == "string" then
                state.apps = parsed.text
            end
        end
        paint()
    end)
end

function update()
    -- The cheatsheet is static; this only picks up a settings change or an
    -- edit to stoa-keybinds-bar, so a slow poll is plenty.
    noctalia.setUpdateInterval(300 * 1000)
    refresh()
end

-- Per-button click callbacks: PluginWidget dispatches BTN_LEFT/RIGHT to
-- these global names for a [[widget]] entry (see stoa-health).
function onClick()
    noctalia.togglePanel("stoa/keybinds:cheatsheet")
end

function onRightClick()
    noctalia.runAsync(TOGGLE_BIN)
end
