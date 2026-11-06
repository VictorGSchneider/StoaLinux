--  ╔══════════════════════════════════════════════════════════════╗
--  ║  STOA LINUX — Health panel                                    ║
--  ║  "First, do not lose your own peace." — Marcus Aurelius        ║
--  ╚══════════════════════════════════════════════════════════════╝
--
--  Native replacement for the yad menu in scripts/health/stoa-health.sh (now a
--  CLI fallback for anyone invoking stoa-health bare outside Noctalia).
--  Same split as the stoa-drive port: all business logic — including the
--  pkexec/sudo-n privilege choice for update/schedule actions — stays in
--  the script; this panel is a thin declarative front end that reads the
--  same JSON status endpoint the bar widget already polls and dispatches
--  to the script's non-interactive CLI subcommands (doctor/snapshot/
--  backup/cleanup/cleanup-dry-run/schedule/update-all/update-system/
--  update-aur/locksmith, plus cleanup-user/unschedule). The ones that need
--  root open a terminal for sudo. System (Btrfs) snapshots go through
--  scripts/system/stoa-snapshot.sh the same way (status/create/setup/restore/list).
--
--  Four views: Vitals (main) / Snapshots / Maintenance, plus Hardware —
--  SSD SMART, memory, CPU, GPUs, panel and battery from stoa-hardware, with
--  buttons to run a SMART self-test or open the full smartctl report (both
--  ask for your password through polkit).
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
local HW_BIN      = "$HOME/.local/bin/stoa-hardware"
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
    view = "main", -- "main" | "snapshots" | "maintenance" | "hardware"

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

    -- stoa-hardware's summary (the "hardware" key of the status JSON), or
    -- nil when it could not run.
    hw = nil,

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
        state.hw = nil
        if type(parsed.hardware) == "table" then
            state.hw = parsed.hardware
        end
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

-- Hardware ──

-- Re-read everything now, SMART and kernel log included, instead of the
-- ten-minute cache the 30 s poll uses.
local function rescanHardware()
    noctalia.runAsync(HW_BIN .. " summary --fresh", function(result)
        refreshStatus()
    end)
end

-- Both self-tests go through udisks2/polkit: the password box is the
-- system's, not ours. The short one returns once started and a
-- notification reports the result; the extended one takes much longer.
local function smartTestShort()
    runNotified("SMART self-test", BIN .. " smart-test short", nil)
end

local function smartTestExtended()
    runNotified("SMART extended self-test", BIN .. " smart-test extended", nil)
end

-- Full `smartctl -x`; opens a terminal (pkexec prompt + long output).
local function smartReport()
    noctalia.runAsync(BIN .. " smart-report")
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

-- The snapshot browser (scripts/system/stoa-snapshots): what is in each package
-- snapshot and config backup, diffs against now, single-file restore.
local function openPackageSnapshots()
    noctalia.runAsync(BROWSER_BIN .. " --show packages")
end

local function openConfigBackups()
    noctalia.runAsync(BROWSER_BIN .. " --show configs")
end

-- The three updates need root, and yay escalates by itself half-way
-- through a build. Run in the background there is nothing to answer sudo,
-- every prompt-less sudo is a failed login to pam_faillock, and three lock
-- the account out. They open a terminal (where the output can be read too)
-- and return, so no notify wrapper; the pending count catches up on the
-- panel's next poll.
local function updateAll()
    noctalia.runAsync(BIN .. " update-all")
end

local function updateSystem()
    noctalia.runAsync(BIN .. " update-system")
end

local function updateAUR()
    noctalia.runAsync(BIN .. " update-aur")
end

-- Both open a terminal and return, so no notify wrapper. The cleanup needs
-- one: stoa-maintain --cleanup makes a dozen sudo calls and refuses to start
-- without a terminal to prompt on (prompt-less sudo calls would each count
-- as a failed login to pam_faillock) — run in the background it always
-- ended in "Failed: Cleanup". The preview is output meant to be read.
local function cleanupDryRun()
    noctalia.runAsync(BIN .. " cleanup-dry-run")
end

local function cleanupApply()
    noctalia.runAsync(BIN .. " cleanup")
end

-- Cleanup of your own files only: no sudo, so no terminal needed and the
-- background-with-notification wrapper is safe here.
local function cleanupUser()
    runNotified("Cleanup (my files)", BIN .. " cleanup-user", refreshStatus)
end

-- Schedule / unschedule need root (a systemd timer in /etc), so both open a
-- terminal like the updates. stoa-maintain --schedule only ever adds; the
-- remove path is stoa-health's, which finds the timer or cron line wherever
-- it was installed.
local function scheduleCleanup()
    noctalia.runAsync(BIN .. " schedule")
end

local function unscheduleCleanup()
    noctalia.runAsync(BIN .. " unschedule")
end

-- stoa-locksmith is the File Locksmith: find and end whatever holds a file
-- or folder open. Its own interactive yad flow (pick a path, see who holds
-- it) — fire-and-forget, no notify wrapper. It is not the firewall (that is
-- Settings → Firewall); the button used to be labelled as if it were.
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

local function goToHardware()
    state.view = "hardware"
    render()
end

-- ── Rendering ──

local function header(title, onBack)
    return rowN({ align = "center", gap = 6 }, {
        btn({ glyph = "chevron-left", variant = "ghost", controlSize = "sm", onClick = onBack }),
        lbl({ text = title, fontWeight = "bold", flexGrow = 1 }),
    })
end

local function hwCounts()
    if state.hw == nil then return 0, 0 end
    return state.hw.issues or 0, state.hw.warnings or 0
end

-- Same wording as _summary_line() in stoa-health.sh.
local function statusLine()
    if not state.loaded then return "…" end
    if state.doctorIssues < 0 then return "doctor not run" end
    local hwIssues, hwWarnings = hwCounts()
    local issues = state.doctorIssues + state.failedUnits + hwIssues
    if issues > 0 then
        local label = "issue"
        if issues > 1 then label = "issues" end
        return string.format("%d %s", issues, label)
    end
    local warnings = state.doctorWarnings + hwWarnings
    if warnings > 0 then
        local label = "warning"
        if warnings > 1 then label = "warnings" end
        return string.format("%d %s", warnings, label)
    end
    return "all systems nominal"
end

local function statusColor()
    if not state.loaded then return "on_surface_variant" end
    if state.doctorIssues < 0 then return "on_surface_variant" end
    local hwIssues, hwWarnings = hwCounts()
    if state.doctorIssues + state.failedUnits + hwIssues > 0 then return "error" end
    if state.doctorWarnings + hwWarnings > 0 then return "tertiary" end
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

-- "Hardware   2 warnings" on the main view; the detail is one click away.
local function hwSummaryRow()
    local issues, warnings = hwCounts()
    local text, color = "healthy", nil
    if state.hw == nil then
        text = "not checked"
    elseif issues > 0 then
        text, color = string.format("%.0f issues · %.0f warnings", issues, warnings), "error"
    elseif warnings > 0 then
        text, color = string.format("%.0f warnings", warnings), "tertiary"
    end
    local props = { text = text, fontSize = 12 }
    if color ~= nil then props.color = color end
    return rowN({ align = "center", gap = 8 }, {
        lbl({ text = "Hardware", color = "on_surface_variant", fontSize = 12, flexGrow = 1 }),
        lbl(props),
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
            hwSummaryRow(),
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
            btn({ text = "Hardware", flexGrow = 1, controlSize = "sm", variant = "outline", onClick = goToHardware }),
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

-- ── Hardware view ──

-- Cut on a character boundary: messages carry "°" and "×".
local function clip(s, n)
    local chars = utf8.len(s)
    if chars == nil or chars <= n then return s end
    return string.sub(s, 1, utf8.offset(s, n - 2) - 1) .. "..."
end

local function levelColor(level)
    if level == "fail" then return "error" end
    if level == "warn" then return "tertiary" end
    return nil
end

-- Worst level per area ("storage", "gpu", ...) from the non-passing
-- findings, so a row turns red/amber when anything under it is wrong.
local function hwAreaLevels()
    local levels = {}
    if state.hw ~= nil and type(state.hw.findings) == "table" then
        for _, f in ipairs(state.hw.findings) do
            local area = f.area or "other"
            if f.level == "fail" then
                levels[area] = "fail"
            elseif levels[area] == nil then
                levels[area] = f.level
            end
        end
    end
    return levels
end

local function hwRow(label, value, level)
    local props = { text = value, fontSize = 12 }
    local color = levelColor(level)
    if color ~= nil then props.color = color end
    return rowN({ align = "center", gap = 8 }, {
        lbl({ text = label, color = "on_surface_variant", fontSize = 12 }),
        lbl({ text = clip(value, 34), fontSize = 12, color = props.color, flexGrow = 1 }),
    })
end

local function driveValue(d)
    local parts = {}
    if d.tempC ~= nil then
        parts[#parts + 1] = string.format("%.0f°C", d.tempC)
    end
    if type(d.smart) == "table" then
        if d.smart.percentUsed ~= nil then
            parts[#parts + 1] = string.format("%.0f%% worn", d.smart.percentUsed)
        end
        if d.smart.mediaErrors ~= nil then
            parts[#parts + 1] = string.format("%.0f errors", d.smart.mediaErrors)
        end
    else
        parts[#parts + 1] = "no SMART"
    end
    return table.concat(parts, " · ")
end

local function hwRows()
    local hw = state.hw
    local lv = hwAreaLevels()
    local rows = {}
    local function add(n) rows[#rows + 1] = n end

    local drives = {}
    if type(hw.storage) == "table" and type(hw.storage.drives) == "table" then
        drives = hw.storage.drives
    end
    for _, d in ipairs(drives) do
        add(hwRow(d.name or "disk", driveValue(d), lv.storage))
    end

    local m = hw.memory or {}
    add(hwRow("Memory", string.format("%.1f GiB · swap %.0f%%", m.totalGiB or 0, m.swapUsedPct or 0), lv.memory))

    local c = hw.cpu or {}
    local cpuText = string.format("%.0f threads", c.online or 0)
    if c.tempC ~= nil then cpuText = cpuText .. string.format(" · %.0f°C", c.tempC) end
    add(hwRow("CPU", cpuText, lv.cpu))

    for _, g in ipairs(hw.gpus or {}) do
        local text = "asleep"
        if g.state ~= "asleep" then
            text = ""
            if g.tempC ~= nil then text = string.format("%.0f°C", g.tempC) end
            if g.busyPct ~= nil then text = text .. string.format(" · %.0f%% busy", g.busyPct) end
        end
        add(hwRow(clip(g.name or "GPU", 22), text, lv.gpu))
    end

    local connectors = {}
    if type(hw.display) == "table" and type(hw.display.connectors) == "table" then
        connectors = hw.display.connectors
    end
    for _, x in ipairs(connectors) do
        if x.internal == true then
            local text = x.status or "unknown"
            if x.status == "connected" and x.mode ~= nil then text = x.mode end
            if type(hw.display.backlight) == "table" then
                text = text .. string.format(" · %.0f%%", hw.display.backlight.pct or 0)
            end
            add(hwRow("Panel", text, lv.display))
        end
    end

    if type(hw.battery) == "table" then
        local b = hw.battery
        local text = string.format("%.0f%%", b.capacityPct or 0)
        if b.healthPct ~= nil then text = text .. string.format(" · health %.0f%%", b.healthPct) end
        add(hwRow("Battery", text, lv.battery))
    end
    return rows
end

local function renderHardware()
    local children = {}
    local function add(n) children[#children + 1] = n end

    if state.hw == nil then
        add(lbl({ text = "Hardware checks unavailable — stoa-hardware did not run.",
            color = "on_surface_variant", fontSize = 12 }))
    else
        local findings = state.hw.findings or {}
        if #findings == 0 then
            add(lbl({ text = "No hardware problems found", color = "secondary", fontSize = 12 }))
        else
            for i, f in ipairs(findings) do
                if i > 5 then break end
                add(lbl({ text = clip(f.msg or "", 50), fontSize = 11,
                    color = levelColor(f.level) or "on_surface_variant" }))
            end
            if #findings > 5 then
                add(lbl({ text = string.format("… and %d more — see the full report", #findings - 5),
                    fontSize = 11, color = "on_surface_variant" }))
            end
        end
        add(sep({ opacity = 0.3 }))
        for _, r in ipairs(hwRows()) do add(r) end
    end

    return col({ flexGrow = 1, gap = 10, padding = 12 }, {
        header("Hardware", goToMain),
        scr({ flexGrow = 1, gap = 8 }, children),
        sep({}),
        lbl({ text = "SMART tests ask for your password.", color = "on_surface_variant", fontSize = 11 }),
        rowN({ gap = 6 }, {
            btn({ text = "SMART test", flexGrow = 1, controlSize = "sm", onClick = smartTestShort }),
            btn({ text = "Extended…", flexGrow = 1, controlSize = "sm", variant = "outline", onClick = smartTestExtended }),
        }),
        rowN({ gap = 6 }, {
            btn({ text = "SMART report", flexGrow = 1, controlSize = "sm", variant = "outline", onClick = smartReport }),
            btn({ text = "Re-scan", flexGrow = 1, controlSize = "sm", variant = "outline", onClick = rescanHardware }),
        }),
    })
end

-- One button for the state it can actually act on: schedule when there is
-- none, remove when there is one. The old "Toggle" could only ever add.
local function scheduleButton()
    if state.scheduled then
        return btn({ text = "Remove boot schedule", controlSize = "sm", variant = "outline", onClick = unscheduleCleanup })
    end
    return btn({ text = "Schedule cleanup at boot", controlSize = "sm", variant = "outline", onClick = scheduleCleanup })
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
            btn({ text = "Cleanup (my files, no sudo)", controlSize = "sm", variant = "outline", onClick = cleanupUser }),
            scheduleButton(),
            sep({ opacity = 0.3 }),
            btn({ text = "File locksmith", controlSize = "sm", variant = "ghost", onClick = openLocksmith }),
        }),
    })
end

function render()
    local tree = renderMain()
    if state.view == "snapshots" then
        tree = renderSnapshots()
    elseif state.view == "maintenance" then
        tree = renderMaintenance()
    elseif state.view == "hardware" then
        tree = renderHardware()
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
