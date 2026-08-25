--  ╔══════════════════════════════════════════════════════════════╗
--  ║  STOA LINUX — Health pill                                     ║
--  ║  "First, do not lose your own peace." — Marcus Aurelius        ║
--  ╚══════════════════════════════════════════════════════════════╝
--
--  Aggregate system health: doctor log, failed systemd units, CPU/GPU
--  temperature, memory, disk and pending updates — one icon, coloured by
--  worst offender, same thresholds the v4 QML widget used:
--
--      error    doctor issues, failed units, or any sensor >= 90%/90C
--      warn     doctor warnings, or a sensor in the 80-90 band, or
--               >=50 pending updates
--      ok       none of the above
--      unknown  stoa-vitals-status has not answered yet
--
--  Left click opens the full menu (scripts/stoa-health.sh, replaces the v4
--  Panel's three tabs). Right click runs the doctor directly — the single
--  most common action, same shortcut the old right-click context menu led
--  with. Middle click opens the doctor log.
--
--  Written in the Lua 5.4-compatible subset of Luau (no type annotations,
--  no if-expressions) so the CI lua step can actually parse it — luac5.4
--  rejects Luau-only syntax, and CI has no Luau front end.
--
--  Data comes from ~/.local/bin/stoa-vitals-status, unchanged from v4 —
--  it already emits JSON:
--      {"doctor":{"issues":N,"warnings":N,"log":"..."},
--       "cpu":{"tempC":0.0,"loadPct":0.0},"gpu":{"tempC":0.0},
--       "memory":{"usedPct":0.0,...},"disk":{"usedPct":N,...},
--       "failedUnits":N,"updates":N,"uptime":"...",
--       "snapshots":N,"backups":N,"scheduled":bool}

local STATUS_BIN = "$HOME/.local/bin/stoa-vitals-status"
local HEALTH_BIN = "$HOME/.local/bin/stoa-health"
local DOCTOR_LOG  = "$HOME/.config/stoa/doctor.log"

local state = {
    loaded = false,
    doctorIssues = -1,
    doctorWarnings = 0,
    failedUnits = 0,
    cpuTempC = 0,
    gpuTempC = 0,
    memUsedPct = 0,
    diskUsedPct = 0,
    updates = 0,
}

-- getConfig reads THIS plugin's own [[setting]] entries from plugin.toml
-- (context->settings, keyed by the `key` field) — see the stoa-drive port,
-- where noctalia.getSetting() was tried first and silently returned nil
-- because that call reads the shell's own config.toml, not the plugin's.
local function configIcon()
    local configured = noctalia.getConfig("icon")
    if type(configured) == "string" and configured ~= "" then
        return configured
    end
    return "heart"
end

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

-- Same thresholds as BarWidget.qml's `severity` property.
local function severity()
    if not state.loaded then
        return "unknown"
    end
    if state.doctorIssues > 0 or state.failedUnits > 0 then
        return "error"
    end
    if state.cpuTempC >= 90 or state.gpuTempC >= 90 or state.diskUsedPct >= 95 then
        return "error"
    end
    if state.doctorIssues < 0 then
        return "unknown"
    end
    if state.doctorWarnings > 0 or state.cpuTempC >= 80 or state.gpuTempC >= 80
        or state.diskUsedPct >= 85 or state.memUsedPct >= 90 or state.updates >= 50 then
        return "warn"
    end
    return "ok"
end

local function severityColor()
    local s = severity()
    if s == "error" then return "error" end
    if s == "warn" then return "tertiary" end
    if s == "unknown" then return "on_surface_variant" end
    return "secondary"
end

local function badgeCount()
    local issues = state.doctorIssues
    if issues < 0 then issues = 0 end
    return issues + state.failedUnits
end

local function tooltip()
    local s = severity()
    if s == "unknown" then
        return "Stoa Health — run doctor to populate"
    end

    local parts = {}
    if state.doctorIssues > 0 then
        local label = "issue"
        if state.doctorIssues > 1 then label = "issues" end
        parts[#parts + 1] = string.format("%d %s", state.doctorIssues, label)
    end
    if state.doctorWarnings > 0 then
        local label = "warning"
        if state.doctorWarnings > 1 then label = "warnings" end
        parts[#parts + 1] = string.format("%d %s", state.doctorWarnings, label)
    end
    if state.failedUnits > 0 then
        local label = "failed unit"
        if state.failedUnits > 1 then label = "failed units" end
        parts[#parts + 1] = string.format("%d %s", state.failedUnits, label)
    end
    if state.cpuTempC >= 80 then
        parts[#parts + 1] = string.format("CPU %d°C", math.floor(state.cpuTempC + 0.5))
    end
    if state.gpuTempC >= 80 then
        parts[#parts + 1] = string.format("GPU %d°C", math.floor(state.gpuTempC + 0.5))
    end
    if state.diskUsedPct >= 85 then
        parts[#parts + 1] = string.format("disk %d%%", state.diskUsedPct)
    end

    if #parts == 0 then
        return "Stoa Health — all systems nominal"
    end
    return "Stoa Health — " .. table.concat(parts, "  ·  ")
end

local function paint()
    barWidget.setGlyph(configIcon())
    barWidget.setGlyphColor(severityColor())

    if showBadge() and state.loaded and badgeCount() > 0 then
        barWidget.setText(tostring(badgeCount()))
    else
        barWidget.setText("")
    end

    barWidget.setTooltip(tooltip())
end

local function refresh()
    noctalia.runAsync(STATUS_BIN, function(result)
        state.loaded = true

        if result.exitCode ~= 0 or result.stdout == "" then
            paint()
            return
        end

        local ok, parsed = pcall(noctalia.json.decode, result.stdout)
        if not ok or type(parsed) ~= "table" then
            paint()
            return
        end

        local doctor = parsed.doctor or {}
        local cpu = parsed.cpu or {}
        local gpu = parsed.gpu or {}
        local memory = parsed.memory or {}
        local disk = parsed.disk or {}

        state.doctorIssues = doctor.issues or -1
        state.doctorWarnings = doctor.warnings or 0
        state.failedUnits = parsed.failedUnits or 0
        state.cpuTempC = cpu.tempC or 0
        state.gpuTempC = gpu.tempC or 0
        state.memUsedPct = memory.usedPct or 0
        state.diskUsedPct = disk.usedPct or 0
        state.updates = parsed.updates or 0
        paint()
    end)
end

function update()
    noctalia.setUpdateInterval(pollSeconds() * 1000)
    refresh()
end

-- Per-button click callbacks. PluginWidget::create() (plugin_widget.cpp)
-- dispatches BTN_LEFT/RIGHT/MIDDLE to exactly these three global names for
-- a [[widget]] entry — confirmed directly from source after the stoa-drive
-- port shipped with the wrong name (onActivate, a launcher-provider
-- callback) and the click silently did nothing.
function onClick()
    -- Full menu: Vitals / Snapshots / Maintenance, replacing the v4 Panel.
    noctalia.runAsync(HEALTH_BIN)
end

function onRightClick()
    noctalia.notify("Stoa Health", "Running: Doctor")
    noctalia.runAsync(HEALTH_BIN .. " doctor", function(result)
        if result.exitCode == 0 then
            noctalia.notify("Stoa Health", "Done: Doctor")
            refresh()
        else
            noctalia.notifyError("Stoa Health", "Doctor failed")
        end
    end)
end

function onMiddleClick()
    noctalia.runAsync("xdg-open " .. DOCTOR_LOG)
end
