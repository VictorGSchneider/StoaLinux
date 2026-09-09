--  ╔══════════════════════════════════════════════════════════════╗
--  ║  STOA LINUX — Health panel                                    ║
--  ║  "First, do not lose your own peace." — Marcus Aurelius        ║
--  ╚══════════════════════════════════════════════════════════════╝
--
--  Native replacement for the yad menu in scripts/stoa-health.sh (now a
--  CLI fallback for anyone invoking stoa-health bare outside Noctalia).
--  Same split as the stoa-drive port: all business logic — including the
--  pkexec/sudo-n privilege choice for update/schedule actions — stays in
--  the script; this panel is a thin declarative front end that reads the
--  same JSON status endpoint the bar widget already polls and dispatches
--  to the script's non-interactive CLI subcommands (doctor/snapshot/
--  backup/cleanup/cleanup-dry-run/schedule/update-all/update-system/
--  update-aur/locksmith).
--
--  Three views, same split as the old yad tabs: Vitals (main) / Snapshots
--  / Maintenance.
--
--  Written in the Lua 5.4-compatible subset of Luau (no type annotations,
--  no if-expressions) so the CI lua step can actually parse it — luac5.4
--  rejects Luau-only syntax, and CI has no Luau front end.
--
--  Tree-callback contract (see the stoa-drive port for how this was
--  verified against src/ui/ui_tree_reconciler.cpp and
--  src/scripting/script_runtime.cpp): every prop callback is dispatched
--  through enqueueCallStrings, which always sends plain Lua strings — a
--  toggle's onChange receives "true"/"false" text, not a real boolean.
--  This panel has no toggle (see toggleSchedule below for why), but
--  keeps the same string-safe style as the drive panel throughout.

local BIN         = "$HOME/.local/bin/stoa-health"
local STATUS_BIN  = "$HOME/.local/bin/stoa-vitals-status"
local DOCTOR_LOG  = "$HOME/.config/stoa/doctor.log"
local SNAPSHOT_DIR = "$HOME/.config/stoa/pkg-snapshots"
local BACKUP_DIR  = "$HOME/.local/state/stoa/backups"

-- ── UI tree node builders ──
-- A node is { type=..., props={...}, children={...} }; see luau_ui_render
-- in plugin_bindings.cpp. `props.key` (if set) is read out of props by the
-- host itself, not a real prop — safe to pass alongside real props.
local function node(kind, props, children)
    return { type = kind, props = props or {}, children = children or {} }
end
local function col(props, children) return node("column", props, children) end
local function rowN(props, children) return node("row", props, children) end
local function lbl(props) return node("label", props) end
local function btn(props) return node("button", props) end
local function sep(props) return node("separator", props) end
local function scr(props, children) return node("scroll", props, children) end
local function prog(props) return node("progress", props) end

-- ── State ──

local state = {
    view = "main", -- "main" | "snapshots" | "maintenance"

    loaded = false,
    doctorIssues = -1,
    doctorWarnings = 0,
    failedUnits = 0,
    cpuTempC = 0,
    cpuLoadPct = 0,
    gpuTempC = 0,
    memUsedPct = 0,
    memUsedGiB = 0,
    memTotalGiB = 0,
    diskUsedPct = 0,
    diskFreeGiB = 0,
    updates = 0,
    uptime = "",
    snapshots = 0,
    backups = 0,
    scheduled = false,
}

-- ── Data ──

local function refreshStatus()
    noctalia.runAsync(STATUS_BIN, function(result)
        state.loaded = true
        if result.exitCode ~= 0 or result.stdout == "" then
            render()
            return
        end
        local ok, parsed = pcall(noctalia.json.decode, result.stdout)
        if not ok or type(parsed) ~= "table" then
            render()
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
        state.cpuLoadPct = cpu.loadPct or 0
        state.gpuTempC = gpu.tempC or 0
        state.memUsedPct = memory.usedPct or 0
        state.memUsedGiB = memory.usedGiB or 0
        state.memTotalGiB = memory.totalGiB or 0
        state.diskUsedPct = disk.usedPct or 0
        state.diskFreeGiB = disk.freeGiB or 0
        state.updates = parsed.updates or 0
        state.uptime = parsed.uptime or ""
        state.snapshots = parsed.snapshots or 0
        state.backups = parsed.backups or 0
        state.scheduled = parsed.scheduled == true
        render()
    end)
end

-- ── Actions ──

local function runNotified(label, cmd, onDone)
    noctalia.notify("Stoa Health", "Running: " .. label)
    noctalia.runAsync(cmd, function(result)
        if result.exitCode == 0 then
            noctalia.notify("Stoa Health", "Done: " .. label)
        else
            noctalia.notifyError("Stoa Health", "Failed: " .. label)
        end
        if onDone then onDone() end
    end)
end

local function runDoctor()
    runNotified("Doctor", BIN .. " doctor", refreshStatus)
end

local function openLog()
    noctalia.runAsync("xdg-open " .. DOCTOR_LOG)
end

local function snapshotPackages()
    runNotified("Package snapshot", BIN .. " snapshot", refreshStatus)
end

local function backupConfigs()
    runNotified("Backup configs", BIN .. " backup", refreshStatus)
end

local function browseSnapshots()
    noctalia.runAsync("xdg-open " .. SNAPSHOT_DIR)
end

local function browseBackups()
    noctalia.runAsync("xdg-open " .. BACKUP_DIR)
end

local function updateAll()
    runNotified("Update all", BIN .. " update-all", refreshStatus)
end

local function updateSystem()
    runNotified("Update system", BIN .. " update-system", refreshStatus)
end

local function updateAUR()
    runNotified("Update AUR", BIN .. " update-aur", refreshStatus)
end

local function cleanupDryRun()
    runNotified("Cleanup (dry-run)", BIN .. " cleanup-dry-run", refreshStatus)
end

local function cleanupApply()
    runNotified("Cleanup", BIN .. " cleanup", refreshStatus)
end

-- --schedule only ever enables the cleanup timer/cron line — stoa-maintain
-- has no unschedule CLI path (systemd --user timers and crontab entries
-- get removed by hand, per its own --help text). A toggle here would
-- promise a disable this button cannot deliver, so it stays a plain
-- button, same "Toggle boot schedule" wording the yad menu used.
local function scheduleCleanup()
    runNotified("Toggle schedule", BIN .. " schedule", refreshStatus)
end

-- stoa-locksmith is its own interactive yad flow (pick a path, see who
-- holds it) — fire-and-forget, same as the drive panel's "opens a
-- terminal" account-creation button, no notify wrapper around it.
local function openLocksmith()
    noctalia.runAsync(BIN .. " locksmith")
end

-- ── Navigation ──

local function goToMain()
    state.view = "main"
    render()
end

local function goToSnapshots()
    state.view = "snapshots"
    render()
end

local function goToMaintenance()
    state.view = "maintenance"
    render()
end

-- ── Rendering ──

local function header(title, onBack)
    return rowN({ align = "center", gap = 6 }, {
        btn({ glyph = "chevron-left", variant = "ghost", controlSize = "sm", onClick = onBack }),
        lbl({ text = title, fontWeight = "bold", flexGrow = 1 }),
    })
end

-- Same wording as _summary_line() in stoa-health.sh.
local function statusLine()
    if not state.loaded then return "…" end
    if state.doctorIssues < 0 then return "doctor not run" end
    local issues = state.doctorIssues + state.failedUnits
    if issues > 0 then
        local label = "issue"
        if issues > 1 then label = "issues" end
        return string.format("%d %s", issues, label)
    end
    if state.doctorWarnings > 0 then
        local label = "warning"
        if state.doctorWarnings > 1 then label = "warnings" end
        return string.format("%d %s", state.doctorWarnings, label)
    end
    return "all systems nominal"
end

local function statusColor()
    if not state.loaded then return "on_surface_variant" end
    if state.doctorIssues < 0 then return "on_surface_variant" end
    if state.doctorIssues + state.failedUnits > 0 then return "error" end
    if state.doctorWarnings > 0 then return "tertiary" end
    return "secondary"
end

local function statRow(label, value)
    return rowN({ align = "center", gap = 8 }, {
        lbl({ text = label, color = "on_surface_variant", fontSize = 12, flexGrow = 1 }),
        lbl({ text = value, fontSize = 12 }),
    })
end

local function meterRow(label, pct, valueText)
    local fill = "secondary"
    if pct >= 90 then
        fill = "error"
    elseif pct >= 80 then
        fill = "tertiary"
    end
    return col({ gap = 4 }, {
        rowN({ align = "center", gap = 8 }, {
            lbl({ text = label, color = "on_surface_variant", fontSize = 12, flexGrow = 1 }),
            lbl({ text = valueText, fontSize = 12 }),
        }),
        prog({ progress = pct / 100.0, fill = fill, track = "surface_variant" }),
    })
end

local function renderMain()
    local body
    if not state.loaded then
        body = col({ flexGrow = 1, align = "center", justify = "center" }, {
            lbl({ text = "…", color = "on_surface_variant" }),
        })
    else
        local doctorText = "not run"
        if state.doctorIssues >= 0 then
            doctorText = string.format("%d issues · %d warnings", state.doctorIssues, state.doctorWarnings)
        end

        body = scr({ flexGrow = 1, gap = 10 }, {
            statRow("Doctor", doctorText),
            statRow("Failed units", tostring(state.failedUnits)),
            sep({ opacity = 0.3 }),
            meterRow("CPU", state.cpuTempC,
                string.format("%.0f°C · %.0f%% load", state.cpuTempC, state.cpuLoadPct)),
            meterRow("GPU", state.gpuTempC, string.format("%.0f°C", state.gpuTempC)),
            meterRow("Memory", state.memUsedPct,
                string.format("%.1f/%.1f GiB (%.0f%%)", state.memUsedGiB, state.memTotalGiB, state.memUsedPct)),
            meterRow("Disk /", state.diskUsedPct,
                string.format("%.0f%% used · %.1f GiB free", state.diskUsedPct, state.diskFreeGiB)),
            sep({ opacity = 0.3 }),
            statRow("Updates pending", tostring(state.updates)),
            statRow("Uptime", state.uptime),
        })
    end

    return col({ flexGrow = 1, gap = 10, padding = 12 }, {
        rowN({ align = "center" }, {
            lbl({ text = "Stoa Health", fontWeight = "bold", flexGrow = 1 }),
            lbl({ text = statusLine(), color = statusColor(), fontSize = 12 }),
        }),
        sep({}),
        body,
        sep({}),
        rowN({ gap = 6 }, {
            btn({ text = "Run Doctor", flexGrow = 1, controlSize = "sm", onClick = runDoctor }),
            btn({ text = "Open Log", flexGrow = 1, controlSize = "sm", variant = "outline", onClick = openLog }),
        }),
        rowN({ gap = 6 }, {
            btn({ text = "Snapshots", flexGrow = 1, controlSize = "sm", variant = "outline", onClick = goToSnapshots }),
            btn({ text = "Maintenance", flexGrow = 1, controlSize = "sm", variant = "outline", onClick = goToMaintenance }),
        }),
    })
end

local function renderSnapshots()
    return col({ flexGrow = 1, gap = 10, padding = 12 }, {
        header("Snapshots", goToMain),
        lbl({
            text = string.format("%d packages · %d configs", state.snapshots, state.backups),
            color = "on_surface_variant", fontSize = 12,
        }),
        sep({}),
        col({ flexGrow = 1, gap = 6 }, {
            btn({ text = "Snapshot packages now", controlSize = "sm", onClick = snapshotPackages }),
            btn({ text = "Backup configs now", controlSize = "sm", onClick = backupConfigs }),
            sep({ opacity = 0.3 }),
            btn({ text = "Browse snapshots", controlSize = "sm", variant = "outline", onClick = browseSnapshots }),
            btn({ text = "Browse backups", controlSize = "sm", variant = "outline", onClick = browseBackups }),
        }),
    })
end

local function renderMaintenance()
    local schedText = "auto-cleanup disabled"
    if state.scheduled then schedText = "auto-cleanup enabled" end

    return col({ flexGrow = 1, gap = 10, padding = 12 }, {
        header("Maintenance", goToMain),
        lbl({
            text = string.format("%d updates pending · %s", state.updates, schedText),
            color = "on_surface_variant", fontSize = 12,
        }),
        sep({}),
        col({ flexGrow = 1, gap = 6 }, {
            btn({ text = "Update all (pacman + AUR)", controlSize = "sm", onClick = updateAll }),
            rowN({ gap = 6 }, {
                btn({ text = "Update system", flexGrow = 1, controlSize = "sm", variant = "outline", onClick = updateSystem }),
                btn({ text = "Update AUR", flexGrow = 1, controlSize = "sm", variant = "outline", onClick = updateAUR }),
            }),
            sep({ opacity = 0.3 }),
            rowN({ gap = 6 }, {
                btn({ text = "Cleanup (dry run)", flexGrow = 1, controlSize = "sm", variant = "outline", onClick = cleanupDryRun }),
                btn({ text = "Cleanup (apply)", flexGrow = 1, controlSize = "sm", variant = "destructive", onClick = cleanupApply }),
            }),
            btn({ text = "Toggle boot schedule", controlSize = "sm", variant = "outline", onClick = scheduleCleanup }),
            sep({ opacity = 0.3 }),
            btn({ text = "Firewall (locksmith)", controlSize = "sm", variant = "ghost", onClick = openLocksmith }),
        }),
    })
end

function render()
    local tree = renderMain()
    if state.view == "snapshots" then
        tree = renderSnapshots()
    elseif state.view == "maintenance" then
        tree = renderMaintenance()
    end
    panel.render(tree)
end

-- ── Lifecycle ──

function onOpen(context)
    state.view = "main"
    panel.setWantsSecondTicks(true)
    refreshStatus()
    render()
end

function onClose()
    panel.setWantsSecondTicks(false)
end

function update()
    refreshStatus()
end
