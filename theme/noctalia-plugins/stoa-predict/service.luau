--  ╔══════════════════════════════════════════════════════════════╗
--  ║  STOA LINUX — Text prediction service                          ║
--  ╚══════════════════════════════════════════════════════════════╝
--
--  Owns the prediction daemon. `stoa-predict run` checks the input group
--  and python-evdev, then execs scripts/stoa-predict.py, which prints one
--  JSON object per line whenever the suggestions change:
--      {"prefix":"stoi","words":["stoic",...],"emojis":[{"emoji":"…","name":"…"}],
--       "visible":true}
--  or, when a precondition fails, {"error":"…"}. The command line ends with
--  an `{"exited":true}` echo so the service learns when the daemon is gone.
--
--  The latest suggestions go to noctalia.state ("predict.data") for the
--  popup panel, which is opened while `visible` is true and closed
--  otherwise.
--
--  The panel is opened with `noctalia msg panel-open/-close`, not
--  noctalia.togglePanel: a [[service]] runtime is created without the
--  panel-toggle callback (src/scripting/plugin_service_host.cpp builds its
--  ScriptRuntime with none), so togglePanel is a silent no-op here. Both
--  IPC verbs are idempotent for a persistent panel (PersistentPanelHost::
--  open returns early when it is already open), so a lost update cannot
--  leave the popup inverted.
--
--  IPC (what `stoa-predict toggle|start|stop` sends):
--      noctalia msg plugin stoa/predict:service all toggle
--
--  Written in the Lua 5.4-compatible subset of Luau, like the other Stoa
--  plugins, so the CI lua step can parse it.

local BIN = "$HOME/.local/bin/stoa-predict"
local PANEL = "stoa/predict:popup"

local running = false
local announced = false
local panelShown = false

local function emptyData()
    return { prefix = "", words = {}, emojis = {}, visible = false }
end

local function setPanel(open)
    if open == panelShown then
        return
    end
    panelShown = open
    local verb = "panel-close"
    if open then verb = "panel-open" end
    noctalia.runAsync({ "noctalia", "msg", verb, PANEL })
end

local function publish(data)
    noctalia.state.set("predict.data", data)
    setPanel(data.visible == true)
end

local function finished()
    running = false
    announced = false
    noctalia.state.set("predict.running", false)
    publish(emptyData())
end

local function onLine(line)
    local ok, parsed = pcall(noctalia.json.decode, line)
    if not ok or type(parsed) ~= "table" then
        return
    end
    if type(parsed.error) == "string" then
        noctalia.notifyError("Text prediction", parsed.error)
        return
    end
    if parsed.exited then
        finished()
        return
    end

    if not announced then
        announced = true
        noctalia.notify("Text prediction", "On — Super+Shift+S to turn off")
    end

    local words = parsed.words
    if type(words) ~= "table" then words = {} end
    local emojis = parsed.emojis
    if type(emojis) ~= "table" then emojis = {} end
    local prefix = parsed.prefix
    if type(prefix) ~= "string" then prefix = "" end

    publish({
        prefix = prefix,
        words = words,
        emojis = emojis,
        visible = parsed.visible == true and (#words > 0 or #emojis > 0),
    })
end

local function start()
    if running then
        return
    end
    running = true
    noctalia.state.set("predict.running", true)
    local launched = noctalia.runStream(BIN .. " run; echo '{\"exited\":true}'", onLine)
    if not launched then
        noctalia.notifyError("Text prediction", "Could not start stoa-predict")
        finished()
    end
end

local function stop()
    if not running then
        return
    end
    noctalia.runAsync(BIN .. " kill")
    finished()
    noctalia.notify("Text prediction", "Off")
end

function onIpc(event)
    if event == "start" then
        start()
    elseif event == "stop" then
        stop()
    elseif event == "toggle" then
        if running then stop() else start() end
    end
end

-- A reload or shutdown ends the stream, but `stoa-predict run` execs
-- python under a shell, so make sure the daemon itself goes too.
function onExit()
    if running then
        noctalia.runAsync(BIN .. " kill")
    end
end

noctalia.state.set("predict.data", emptyData())
noctalia.state.set("predict.running", false)
