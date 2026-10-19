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
--  update-aur/locksmith). System (Btrfs) snapshots go through
--  scripts/stoa-snapshot.sh the same way (status/create/setup/restore/list).
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
local SNAP_BIN    = "$HOME/.local/bin/stoa-snapshot"
local BROWSER_BIN = "$HOME/.local/bin/stoa-snapshots"
local STATUS_BIN  = "$HOME/.local/bin/stoa-vitals-status"
local DOCTOR_LOG  = "$HOME/.config/stoa/doctor.log"

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

    -- System (Btrfs) snapshots, from `stoa-snapshot status`. Fetched only
    -- while the Snapshots view is open: snapper is too slow for the bar's
    -- 30 s poll and the main view does not show it.
    sysLoaded = false,
    sysAvailable = false,
    sysReason = "",
    sysConfigured = false,
    sysBootMenu = false,
    sysReadable = false,
    sysCount = -1,
    sysLatest = "",

    -- Package snapshots and config backups, from `stoa-snapshots summary`
    -- (same numbers the snapshot browser shows). Also only while open.
    pkgLatest = "",
    pkgChanges = "",
    cfgLatest = "",
    cfgFiles = 0,
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

local function refreshSystemSnapshots()
    noctalia.runAsync(SNAP_BIN .. " status", function(result)
        state.sysLoaded = true
        if result.exitCode == 0 and result.stdout ~= "" then
            local ok, parsed = pcall(noctalia.json.decode, result.stdout)
            if ok and type(parsed) == "table" then
                state.sysAvailable = parsed.available == true
                state.sysReason = parsed.reason or ""
                state.sysConfigured = parsed.configured == true
                state.sysBootMenu = parsed.bootMenu == true
                state.sysReadable = parsed.readable == true
                state.sysCount = parsed.count or -1
                state.sysLatest = parsed.latest or ""
            end
        end
        render()
    end)
end

local function refreshSnapshotSummary()
    noctalia.runAsync(BROWSER_BIN .. " summary", function(result)
        if result.exitCode == 0 and result.stdout ~= "" then
            local ok, parsed = pcall(noctalia.json.decode, result.stdout)
            if ok and type(parsed) == "table" then
                local p = parsed.packages or {}
                local c = parsed.configs or {}
                state.snapshots = p.count or state.snapshots
                state.pkgLatest = p.latest or ""
                state.pkgChanges = p.latestChanges or ""
                state.backups = c.count or state.backups
                state.cfgLatest = c.latest or ""
                state.cfgFiles = c.latestFiles or 0
            end
        end
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
    runNotified("Package snapshot", BIN .. " snapshot", refreshSnapshotSummary)
end

-- System snapshot: no password once setup granted ALLOW_USERS, otherwise
-- stoa-snapshot falls back to the same pkexec prompt as the update buttons.
local function createSystemSnapshot()
    runNotified("System snapshot", SNAP_BIN .. " create stoa: snapshot from panel", refreshSystemSnapshots)
end

-- These three need a terminal (sudo prompt, confirmations, restore's
-- picker), so they open one and return — no notify wrapper.
local function setupSystemSnapshots()
    noctalia.runAsync(SNAP_BIN .. " setup")
end

local function restoreSystemSnapshot()
    noctalia.runAsync(SNAP_BIN .. " restore")
end

local function listSystemSnapshots()
    noctalia.runAsync(SNAP_BIN .. " list")
end

local function backupConfigs()
    runNotified("Backup configs", BIN .. " backup", refreshSnapshotSummary)
end

-- The snapshot browser (scripts/stoa-snapshots): what is in each package
-- snapshot and config backup, diffs against now, single-file restore.
local function openPackageSnapshots()
    noctalia.runAsync(BROWSER_BIN .. " --show packages")
end

local function openConfigBackups()
    noctalia.runAsync(BROWSER_BIN .. " --show configs")
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
    refreshSystemSnapshots()
    refreshSnapshotSummary()
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

-- What the system section says and offers, by how far this machine is
-- along: cannot → not set up → set up (boot menu on or off).
local function systemSnapshotSection()
    local children = {
        lbl({ text = "System (Btrfs)", fontWeight = "bold", fontSize = 12 }),
    }
    local function add(n) children[#children + 1] = n end

    if not state.sysLoaded then
        add(lbl({ text = "…", color = "on_surface_variant", fontSize = 12 }))
    elseif not state.sysAvailable then
        add(lbl({ text = "Unavailable: " .. state.sysReason, color = "on_surface_variant", fontSize = 12 }))
    elseif not state.sysConfigured then
        add(lbl({ text = "Not set up — boot into any snapshot from Limine", color = "on_surface_variant", fontSize = 12 }))
        add(btn({ text = "Enable boot snapshots", controlSize = "sm", onClick = setupSystemSnapshots }))
    else
        local summary
        if state.sysReadable then
            summary = string.format("%d snapshots", state.sysCount)
            if state.sysLatest ~= "" then summary = summary .. " · latest " .. state.sysLatest end
        else
            summary = "Set up (list needs your password)"
        end
        local menuText, menuColor = "boot menu on", "secondary"
        if not state.sysBootMenu then menuText, menuColor = "boot menu off", "tertiary" end
        add(rowN({ align = "center", gap = 8 }, {
            lbl({ text = summary, color = "on_surface_variant", fontSize = 12, flexGrow = 1 }),
            lbl({ text = menuText, color = menuColor, fontSize = 12 }),
        }))
        add(btn({ text = "Create system snapshot", controlSize = "sm", onClick = createSystemSnapshot }))
        add(rowN({ gap = 6 }, {
            btn({ text = "Restore…", flexGrow = 1, controlSize = "sm", variant = "outline", onClick = restoreSystemSnapshot }),
            btn({ text = "List", flexGrow = 1, controlSize = "sm", variant = "outline", onClick = listSystemSnapshots }),
        }))
        if not state.sysBootMenu then
            add(btn({ text = "Enable boot menu", controlSize = "sm", variant = "outline", onClick = setupSystemSnapshots }))
        end
    end
    return col({ gap = 6 }, children)
end

-- "18 snapshots · latest today 14:02 · ↑12 +3" — taken automatically
-- before every pacman transaction, so usually there is one already.
local function packagesLine()
    if state.snapshots <= 0 then return "none yet — taken before every pacman update" end
    local label = "snapshots"
    if state.snapshots == 1 then label = "snapshot" end
    local line = string.format("%d %s", state.snapshots, label)
    if state.pkgLatest ~= "" then line = line .. " · latest " .. state.pkgLatest end
    if state.pkgChanges ~= "" then line = line .. " · " .. state.pkgChanges end
    return line
end

local function configsLine()
    if state.backups <= 0 then return "no backup yet" end
    local label = "backups"
    if state.backups == 1 then label = "backup" end
    local line = string.format("%d %s", state.backups, label)
    if state.cfgLatest ~= "" then line = line .. " · latest " .. state.cfgLatest end
    if state.cfgFiles > 0 then line = line .. string.format(" · %d files", state.cfgFiles) end
    return line
end

-- One block per kind: what is there, take a new one, look inside.
local function snapshotListSection(title, line, takeLabel, onTake, onOpen)
    return col({ gap = 6 }, {
        lbl({ text = title, fontWeight = "bold", fontSize = 12 }),
        lbl({ text = line, color = "on_surface_variant", fontSize = 12 }),
        rowN({ gap = 6 }, {
            btn({ text = takeLabel, flexGrow = 1, controlSize = "sm", variant = "outline", onClick = onTake }),
            btn({ text = "See what's inside", flexGrow = 1, controlSize = "sm", onClick = onOpen }),
        }),
    })
end

local function renderSnapshots()
    return col({ flexGrow = 1, gap = 10, padding = 12 }, {
        header("Snapshots", goToMain),
        systemSnapshotSection(),
        sep({}),
        snapshotListSection("Packages", packagesLine(), "Snapshot now", snapshotPackages, openPackageSnapshots),
        sep({ opacity = 0.3 }),
        snapshotListSection("Configs", configsLine(), "Back up now", backupConfigs, openConfigBackups),
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
