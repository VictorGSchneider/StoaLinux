--  ╔══════════════════════════════════════════════════════════════╗
--  ║  STOA LINUX — Keybinds panel                                  ║
--  ║  The cheatsheet, laid out.                                    ║
--  ╚══════════════════════════════════════════════════════════════╝
--
--  Renders the output of `stoa-keybinds-bar text` — the same text Super+/
--  shows in the yad dialog — as a scrollable list: one block per "▸"
--  section, each bind as key (left) + description (right). Nothing is
--  hard-coded here, so the panel follows the script, including its niri
--  substitutions.
--
--  Written in the Lua 5.4-compatible subset of Luau (no type annotations,
--  no if-expressions) so the CI lua step can actually parse it.

local KEYBINDS_BIN = "$HOME/.local/bin/stoa-keybinds-bar"
local TOGGLE_BIN   = "$HOME/.local/bin/stoa-keybinds-toggle"

-- ── UI tree node builders (same helpers as the stoa-health panel) ──
local function node(kind, props, children)
    return { type = kind, props = props or {}, children = children or {} }
end
local function col(props, children) return node("column", props, children) end
local function rowN(props, children) return node("row", props, children) end
local function lbl(props) return node("label", props) end
local function btn(props) return node("button", props) end
local function sep(props) return node("separator", props) end
local function scr(props, children) return node("scroll", props, children) end

-- ── State ──

local state = {
    loaded = false,
    failed = false,
    -- { { title = "Window", binds = { { key = "...", desc = "..." }, ... } }, ... }
    sections = {},
    binds = 0,
}

-- ── Data ──

-- "  Super+Return         Terminal (kitty)" → key, desc. Key and
-- description are separated by two or more spaces; the key never contains
-- a space. The box-drawing banner lines and blank lines match neither
-- pattern and are skipped.
local function parseText(text)
    local sections, current, binds = {}, nil, 0
    for line in string.gmatch(text, "[^\n]+") do
        local title = string.match(line, "^▸%s*(.+)$")
        if title then
            current = { title = title, binds = {} }
            sections[#sections + 1] = current
        elseif current then
            local key, desc = string.match(line, "^%s+(%S+)%s%s+(%S.*)$")
            if key then
                current.binds[#current.binds + 1] = { key = key, desc = desc }
                binds = binds + 1
            end
        end
    end
    state.sections = sections
    state.binds = binds
end

local function load()
    noctalia.runAsync(KEYBINDS_BIN .. " text", function(result)
        state.loaded = true
        if result.exitCode == 0 and result.stdout ~= "" then
            state.failed = false
            parseText(result.stdout)
        else
            state.failed = true
        end
        render()
    end)
end

-- ── Rendering ──

local function bindRow(b)
    return rowN({ align = "center", gap = 10 }, {
        lbl({ text = b.key, fontSize = 12, fontWeight = "bold", color = "primary", width = 150 }),
        lbl({ text = b.desc, fontSize = 12, flexGrow = 1 }),
    })
end

local function sectionBlock(section)
    local children = {
        lbl({ text = section.title, fontWeight = "bold", fontSize = 13 }),
    }
    for _, b in ipairs(section.binds) do
        children[#children + 1] = bindRow(b)
    end
    return col({ gap = 4 }, children)
end

local function body()
    if not state.loaded then
        return col({ flexGrow = 1, align = "center", justify = "center" }, {
            lbl({ text = "…", color = "on_surface_variant" }),
        })
    end
    if state.failed or #state.sections == 0 then
        return col({ flexGrow = 1, align = "center", justify = "center", gap = 6 }, {
            lbl({ text = "Could not read the cheatsheet", color = "error" }),
            lbl({ text = "stoa-keybinds-bar text failed", color = "on_surface_variant", fontSize = 12 }),
        })
    end

    local children = {}
    for i, section in ipairs(state.sections) do
        if i > 1 then children[#children + 1] = sep({ opacity = 0.3 }) end
        children[#children + 1] = sectionBlock(section)
    end
    return scr({ flexGrow = 1, gap = 10 }, children)
end

function render()
    local subtitle = ""
    if state.loaded and not state.failed then
        subtitle = string.format("%d binds", state.binds)
    end

    panel.render(col({ flexGrow = 1, gap = 10, padding = 12 }, {
        rowN({ align = "center" }, {
            lbl({ text = "Stoa Keybinds", fontWeight = "bold", flexGrow = 1 }),
            lbl({ text = subtitle, color = "on_surface_variant", fontSize = 12 }),
        }),
        sep({}),
        body(),
        sep({}),
        rowN({ gap = 6 }, {
            btn({ text = "Open as window", flexGrow = 1, controlSize = "sm", variant = "outline",
                  onClick = function() noctalia.runAsync(TOGGLE_BIN) end }),
        }),
    }))
end

-- ── Lifecycle ──

function onOpen(context)
    -- Re-read on every open: cheap, and it picks up a changed script or a
    -- compositor switch without restarting the shell.
    render()
    load()
end
