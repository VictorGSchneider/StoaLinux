--  ╔══════════════════════════════════════════════════════════════╗
--  ║  STOA LINUX — Text prediction popup                            ║
--  ╚══════════════════════════════════════════════════════════════╝
--
--  Up to five words and three emojis in one row at the bottom of the
--  screen, the same strip the eww `predict` window drew. The panel never
--  takes keyboard focus (see plugin.toml), so the window being typed in
--  keeps it and `stoa-predict select N` types the word there with wtype.
--
--  Data comes from the service through noctalia.state ("predict.data").
--  Lua 5.4-compatible subset of Luau, like the other Stoa plugins.

local BIN = noctalia.expandPath("~/.local/bin/stoa-predict")

local isOpen = false
local data = nil

local function current()
    local value = noctalia.state.get("predict.data")
    if type(value) == "table" then
        return value
    end
    return { prefix = "", words = {}, emojis = {}, visible = false }
end

local function select(kind, index)
    noctalia.runAsync({ BIN, kind, tostring(index) })
end

local function render()
    if not isOpen then
        return
    end
    data = data or current()

    local children = {}
    local words = data.words or {}
    local emojis = data.emojis or {}

    for i, word in ipairs(words) do
        if i > 5 then break end
        local variant = "ghost"
        if i == 1 then variant = "primary" end
        children[#children + 1] = ui.button({
            key = "word-" .. i,
            text = word,
            variant = variant,
            controlSize = "sm",
            onClick = function() select("select", i - 1) end,
        })
    end

    if #words > 0 and #emojis > 0 then
        children[#children + 1] = ui.separator({ orientation = "vertical", spacing = 4 })
    end

    for i, item in ipairs(emojis) do
        if i > 3 then break end
        if type(item) == "table" and type(item.emoji) == "string" then
            children[#children + 1] = ui.button({
                key = "emoji-" .. i,
                text = item.emoji,
                tooltip = item.name,
                variant = "ghost",
                controlSize = "sm",
                onClick = function() select("select-emoji", i - 1) end,
            })
        end
    end

    panel.render(ui.row({ gap = 4, align = "center", justify = "center", paddingH = 8 }, children))
end

noctalia.state.watch("predict.data", function(value)
    if type(value) == "table" then
        data = value
    end
    render()
end)

function onOpen()
    isOpen = true
    data = current()
    render()
end

function onClose()
    isOpen = false
end
