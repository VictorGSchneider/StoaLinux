--  ╔══════════════════════════════════════════════════════════════╗
--  ║  STOA LINUX — Text prediction service                          ║
--  ╚══════════════════════════════════════════════════════════════╝
--
--  Starts and stops the prediction input method. `stoa-predict run`
--  execs scripts/stoa-predict.py, which registers as the Wayland input
--  method and prints one JSON object per line on stdout:
--      {"ready":true}          the input method is live
--      {"error":"…"}           it could not start (missing package,
--                              another input method running, …)
--  The command line ends with an `{"exited":true}` echo so the service
--  learns when the daemon is gone. Everything the user sees while typing
--  (the popup, the arrow keys) belongs to the daemon.
--
--  IPC (what `stoa-predict toggle|start|stop` sends):
--      noctalia msg plugin stoa/predict:service all toggle
--
--  Written in the Lua 5.4-compatible subset of Luau, like the other Stoa
--  plugins, so the CI lua step can parse it.

local BIN = "$HOME/.local/bin/stoa-predict"

local running = false

local function finished()
    running = false
    noctalia.state.set("predict.running", false)
end

local function onLine(line)
    local ok, parsed = pcall(noctalia.json.decode, line)
    if not ok or type(parsed) ~= "table" then
        return
    end
    if type(parsed.error) == "string" then
        noctalia.notifyError("Text prediction", parsed.error)
    elseif parsed.ready then
        noctalia.notify("Text prediction", "On — ↓ picks a suggestion, Super+Shift+S turns it off")
    elseif parsed.exited then
        finished()
    end
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

noctalia.state.set("predict.running", false)
