--  ╔══════════════════════════════════════════════════════════════╗
--  ║  STOA LINUX — Memento Mori desktop widget                      ║
--  ║  "Remember that you will die." — Stoic tradition               ║
--  ╚══════════════════════════════════════════════════════════════╝
--
--  Five bars showing how much of each natural cycle has elapsed — day,
--  week, month, year, life — each with the percentage and the time left,
--  then a rotating Stoic quote. Same layout and colour roles the v4 QML
--  widget used (error / tertiary / primary / secondary / on_surface_variant).
--
--  Written in the Lua 5.4-compatible subset of Luau (no type annotations,
--  no if-expressions) so the CI lua step can parse it, same as stoa-drive
--  and stoa-health.
--
--  Data: ~/.local/bin/stoa-memento-data prints one JSON object:
--      {"name":"…","day_pct":41.2,"day_remaining":"14h 6m",
--       "week_pct":…,"week_remaining":"…", …month…, …year…,
--       "life_pct":…,"life_remaining":"55.1y","quote":"…"}

local DATA_BIN = "$HOME/.local/bin/stoa-memento-data"

local CYCLES = {
    { label = "Day",   pct = "day_pct",   remaining = "day_remaining",   color = "error" },
    { label = "Week",  pct = "week_pct",  remaining = "week_remaining",  color = "tertiary" },
    { label = "Month", pct = "month_pct", remaining = "month_remaining", color = "primary" },
    { label = "Year",  pct = "year_pct",  remaining = "year_remaining",  color = "secondary" },
    { label = "Life",  pct = "life_pct",  remaining = "life_remaining",  color = "on_surface_variant" },
}

local memento = nil

local function pollSeconds()
    local configured = noctalia.getConfig("poll_seconds")
    if type(configured) == "number" and configured >= 15 then
        return configured
    end
    return 60
end

local function showQuote()
    local configured = noctalia.getConfig("show_quote")
    if type(configured) == "boolean" then
        return configured
    end
    return true
end

local function clamp01(value)
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function cycleRow(cycle)
    local detail = "—"
    local progress = 0
    if memento ~= nil then
        local pct = tonumber(memento[cycle.pct]) or 0
        local left = memento[cycle.remaining] or ""
        detail = string.format("%d%%  ·  %s left", math.floor(pct + 0.5), left)
        progress = clamp01(pct / 100)
    end

    return ui.column({ key = cycle.label, gap = 3 }, {
        ui.row({ align = "center" }, {
            ui.label({ text = cycle.label, fontSize = 14, fontWeight = "medium", color = "on_surface" }),
            ui.spacer({ flexGrow = 1 }),
            ui.label({ text = detail, fontSize = 12, color = "on_surface_variant" }),
        }),
        ui.progress({ progress = progress, fill = cycle.color, track = "surface_variant", radius = 2, height = 4 }),
    })
end

local function render()
    local children = {
        ui.label({
            text = "MEMENTO MORI",
            fontSize = 22,
            fontWeight = "medium",
            fontFamily = "EB Garamond",
            color = "primary",
            textAlign = "center",
        }),
        ui.label({
            text = "Remember that you will die.",
            fontSize = 12,
            fontFamily = "EB Garamond",
            color = "on_surface_variant",
            textAlign = "center",
        }),
        ui.spacer({ height = 6 }),
    }

    for _, cycle in ipairs(CYCLES) do
        children[#children + 1] = cycleRow(cycle)
    end

    if showQuote() and memento ~= nil and type(memento.quote) == "string" and memento.quote ~= "" then
        children[#children + 1] = ui.spacer({ height = 6 })
        children[#children + 1] = ui.label({
            text = memento.quote,
            fontSize = 12,
            fontFamily = "EB Garamond",
            color = "on_surface",
            textAlign = "center",
            maxWidth = 332,
            maxLines = 4,
            opacity = 0.85,
        })
    end

    desktopWidget.render(ui.column({
        gap = 8,
        padding = 20,
        width = 380,
        fill = "surface/0.85",
        radius = 12,
        border = "outline",
        borderWidth = 1,
    }, children))
end

local function refresh()
    noctalia.runAsync(DATA_BIN, function(result)
        if result.exitCode == 0 and result.stdout ~= "" then
            local ok, parsed = pcall(noctalia.json.decode, result.stdout)
            if ok and type(parsed) == "table" then
                memento = parsed
            end
        end
        render()
    end)
end

-- Draw the frame straight away so the tile has its size before the first
-- stoa-memento-data run answers.
render()

function update()
    noctalia.setUpdateInterval(pollSeconds() * 1000)
    refresh()
end
