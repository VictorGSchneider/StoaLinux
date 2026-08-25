--  ╔══════════════════════════════════════════════════════════════╗
--  ║  STOA LINUX — Drive panel                                     ║
--  ║  "The wise man carries his possessions within him." — Bias    ║
--  ╚══════════════════════════════════════════════════════════════╝
--
--  Native replacement for the rofi menu in scripts/stoa-drive.sh. All the
--  business logic (mount/unmount, bisync, rclone account create/delete)
--  still lives in that script — this panel is a thin declarative front
--  end: it reads the same JSON status endpoints the bar widget already
--  polls and dispatches to the script's non-interactive CLI subcommands
--  (add-account/remove-account/add-sync-pair/remove-sync-pair/...).
--
--  The one step that still opens a terminal is creating a new rclone
--  remote — OAuth needs a real browser-driven interactive flow that a
--  layer-shell panel has no way to host, so `stoa-drive add-account`
--  shells out to kitty exactly as the old rofi flow did.
--
--  Written in the Lua 5.4-compatible subset of Luau (no type annotations,
--  no if-expressions) so the CI lua step can actually parse it — luac5.4
--  rejects Luau-only syntax, and CI has no Luau front end.
--
--  Tree-callback contract (verified against src/ui/ui_tree_reconciler.cpp
--  and src/scripting/script_runtime.cpp, not docs): every prop callback
--  (onClick/onChange/onSubmit/...) is dispatched through enqueueCallStrings,
--  which always sends plain Lua strings — a toggle's onChange receives
--  "true"/"false" text, not a real boolean; a select's onChange receives
--  the index as a string plus the option text. Comparisons below are
--  written against strings accordingly, not against Lua's real bool/number
--  types.

local BIN = "$HOME/.local/bin/stoa-drive"
local STATUS_BIN = "$HOME/.local/bin/stoa-drive-status"
local DRIVE_DIR = "$HOME/Drive"

-- Single-quote a value for embedding in a /bin/sh -c string (runAsync's
-- string form shells out — see the drive/health widgets). Only needed for
-- free-typed input (sync paths); drive/account names are already
-- restricted to [a-zA-Z0-9_-] by stoa-drive.sh's own sanitizer.
local function shQuote(value)
    return "'" .. string.gsub(value, "'", "'\\''") .. "'"
end

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
local function tgl(props) return node("toggle", props) end
local function sel(props) return node("select", props) end
local function inp(props) return node("input", props) end
local function prog(props) return node("progress", props) end

-- ── State ──

local state = {
    view = "main", -- "main" | "sync" | "accounts"

    loaded = false,
    available = true,
    total = 0,
    mounted = 0,
    drives = {},

    syncLoaded = false,
    autoSync = false,
    pairs = {},

    newRemotePath = "",
    newLocalPath = "",
    pairFormGen = 0,

    providerIndex = 1,
    newAccountName = "",
    addAccountFormGen = 0,

    pendingRemoveAccount = nil,
}

local PROVIDERS = {
    { label = "Google Drive", type = "drive" },
    { label = "OneDrive", type = "onedrive" },
    { label = "Dropbox", type = "dropbox" },
    { label = "S3 (AWS, Minio, etc)", type = "s3" },
    { label = "Other (manual rclone config)", type = "" },
}

-- ── Data ──

local function refreshStatus()
    noctalia.runAsync(STATUS_BIN, function(result)
        state.loaded = true
        if result.exitCode ~= 0 or result.stdout == "" then
            state.available = false
            state.drives = {}
            render()
            return
        end
        local ok, parsed = pcall(noctalia.json.decode, result.stdout)
        if not ok or type(parsed) ~= "table" then
            state.available = false
            state.drives = {}
            render()
            return
        end
        state.available = parsed.available == true
        state.total = parsed.total or 0
        state.mounted = parsed.mounted or 0
        state.drives = parsed.drives or {}
        render()
    end)
end

local function refreshSync()
    noctalia.runAsync(BIN .. " sync-status-json", function(result)
        state.syncLoaded = true
        if result.exitCode ~= 0 or result.stdout == "" then
            render()
            return
        end
        local ok, parsed = pcall(noctalia.json.decode, result.stdout)
        if not ok or type(parsed) ~= "table" then
            render()
            return
        end
        state.autoSync = parsed.autoSync == true
        state.pairs = parsed.pairs or {}
        render()
    end)
end

-- ── Actions ──

local function runNotified(label, cmd, onDone)
    noctalia.notify("Stoa Drive", "Running: " .. label)
    noctalia.runAsync(cmd, function(result)
        if result.exitCode == 0 then
            noctalia.notify("Stoa Drive", "Done: " .. label)
        else
            noctalia.notifyError("Stoa Drive", "Failed: " .. label)
        end
        if onDone then onDone() end
    end)
end

local function driveAction(action, name)
    noctalia.runAsync(BIN .. " " .. action .. " " .. name, function(result)
        refreshStatus()
    end)
end

local function openDrivePath(d)
    local path
    if d.mounted then
        path = DRIVE_DIR .. "/" .. d.name
    else
        path = "$HOME/.cache/rclone/vfs/" .. d.name
    end
    noctalia.runAsync("thunar " .. path)
end

local function confirmRemoveAccount(name)
    if state.pendingRemoveAccount == name then
        state.pendingRemoveAccount = nil
        noctalia.runAsync(BIN .. " remove-account " .. name, function(result)
            refreshStatus()
        end)
    else
        state.pendingRemoveAccount = name
    end
    render()
end

local function createAccount()
    if state.newAccountName == "" then
        noctalia.notifyError("Stoa Drive", "Enter an account name first")
        return
    end
    local provider = PROVIDERS[state.providerIndex]
    local providerType = provider.type
    if providerType == "" then providerType = "-" end
    noctalia.runAsync(BIN .. " add-account " .. providerType .. " " .. shQuote(state.newAccountName))
    state.newAccountName = ""
    state.addAccountFormGen = state.addAccountFormGen + 1
    render()
end

local function toggleAutoSync(enabled)
    local cmd = BIN .. " sync-disable"
    if enabled then cmd = BIN .. " sync-enable" end
    noctalia.runAsync(cmd, function(result)
        refreshSync()
    end)
    state.autoSync = enabled
    render()
end

local function addSyncPair()
    if state.newRemotePath == "" or state.newLocalPath == "" then
        noctalia.notifyError("Stoa Drive", "Fill in both fields")
        return
    end
    noctalia.runAsync(
        BIN .. " add-sync-pair " .. shQuote(state.newRemotePath) .. " " .. shQuote(state.newLocalPath),
        function(result) refreshSync() end
    )
    state.newRemotePath = ""
    state.newLocalPath = ""
    state.pairFormGen = state.pairFormGen + 1
    render()
end

local function syncPairNow(p)
    runNotified("Sync", BIN .. " sync " .. shQuote(p.remotePath) .. " " .. shQuote(p.localPath), refreshSync)
end

local function removeSyncPair(p)
    noctalia.runAsync(
        BIN .. " remove-sync-pair " .. shQuote(p.remotePath) .. " " .. shQuote(p.localPath),
        function(result) refreshSync() end
    )
end

-- ── Navigation ──

local function goToMain()
    state.view = "main"
    state.pendingRemoveAccount = nil
    render()
end

local function goToSync()
    state.view = "sync"
    state.pendingRemoveAccount = nil
    refreshSync()
    render()
end

local function goToAccounts()
    state.view = "accounts"
    state.pendingRemoveAccount = nil
    render()
end

-- ── Rendering ──

local function header(title, onBack)
    return rowN({ align = "center", gap = 6 }, {
        btn({ glyph = "chevron-left", variant = "ghost", controlSize = "sm", onClick = onBack }),
        lbl({ text = title, fontWeight = "bold", flexGrow = 1 }),
    })
end

local function statusLine()
    if not state.loaded then return "…" end
    if not state.available then return "rclone not installed" end
    if state.total == 0 then return "no accounts" end
    return string.format("%d/%d mounted", state.mounted, state.total)
end

local function driveRow(d)
    local dotColor = "on_surface_variant"
    if d.mounted then dotColor = "secondary" end

    local mountLabel = "Mount"
    local mountVariant = "outline"
    if d.mounted then
        mountLabel = "Unmount"
        mountVariant = "destructive"
    end

    local topChildren = {
        node("box", { width = 8, height = 8, radius = 4, fill = dotColor }),
        col({ flexGrow = 1 }, {
            lbl({ text = d.name, fontWeight = "medium" }),
            lbl({ text = d.type, fontSize = 11, color = "on_surface_variant" }),
        }),
        btn({
            text = mountLabel, variant = mountVariant, controlSize = "sm",
            onClick = function()
                local action = "mount"
                if d.mounted then action = "unmount" end
                driveAction(action, d.name)
            end,
        }),
    }

    if d.mounted or (d.cache_bytes or 0) > 0 then
        local openLabel = "Cache"
        if d.mounted then openLabel = "Open" end
        topChildren[#topChildren + 1] = btn({
            text = openLabel, variant = "ghost", controlSize = "sm",
            onClick = function() openDrivePath(d) end,
        })
    end

    local cachePct = d.cache_pct or 0
    local cacheInfo = string.format("%d%%", cachePct)
    if (d.cache_bytes or 0) > 0 then
        cacheInfo = cacheInfo .. "  ·  " .. (d.cache_human or "0B")
    end

    return col({ gap = 4, key = d.name }, {
        rowN({ align = "center", gap = 8 }, topChildren),
        rowN({ align = "center", gap = 8 }, {
            prog({ progress = cachePct / 100.0, flexGrow = 1, fill = "tertiary", track = "surface_variant" }),
            lbl({ text = cacheInfo, fontSize = 11, color = "on_surface_variant" }),
        }),
    })
end

local function emptyState(text)
    return col({ flexGrow = 1, align = "center", justify = "center" }, {
        lbl({ text = text, color = "on_surface_variant" }),
    })
end

local function renderMain()
    local listArea
    if #state.drives == 0 then
        local text = "…"
        if state.loaded then text = "No cloud drives configured" end
        listArea = emptyState(text)
    else
        local items = {}
        for _, d in ipairs(state.drives) do
            items[#items + 1] = driveRow(d)
            items[#items + 1] = sep({ opacity = 0.3 })
        end
        items[#items] = nil -- drop the trailing separator
        listArea = scr({ flexGrow = 1, gap = 10 }, items)
    end

    return col({ flexGrow = 1, gap = 10, padding = 12 }, {
        rowN({ align = "center" }, {
            lbl({ text = "Cloud Drive", fontWeight = "bold", flexGrow = 1 }),
            lbl({ text = statusLine(), color = "on_surface_variant", fontSize = 12 }),
        }),
        sep({}),
        listArea,
        sep({}),
        rowN({ gap = 6 }, {
            btn({
                text = "Mount All", flexGrow = 1, controlSize = "sm",
                onClick = function() runNotified("Mount all", BIN .. " mount-all", refreshStatus) end,
            }),
            btn({
                text = "Unmount All", flexGrow = 1, controlSize = "sm",
                onClick = function() runNotified("Unmount all", BIN .. " unmount-all", refreshStatus) end,
            }),
        }),
        btn({
            text = "Open ~/Drive", controlSize = "sm",
            onClick = function() noctalia.runAsync("xdg-open " .. DRIVE_DIR) end,
        }),
        rowN({ gap = 6 }, {
            btn({ text = "Folder Sync", flexGrow = 1, controlSize = "sm", variant = "outline", onClick = goToSync }),
            btn({ text = "Accounts", flexGrow = 1, controlSize = "sm", variant = "outline", onClick = goToAccounts }),
        }),
    })
end

local function pairRow(p)
    local stateLabel = "pending --resync"
    if p.state == "ready" then stateLabel = "ready" end

    return col({ gap = 2, key = p.remotePath .. "|" .. p.localPath }, {
        lbl({ text = p.remotePath .. "  ⇄  " .. p.localPath, fontSize = 12 }),
        rowN({ align = "center", gap = 6 }, {
            lbl({ text = stateLabel, fontSize = 11, color = "on_surface_variant", flexGrow = 1 }),
            btn({ text = "Sync", variant = "ghost", controlSize = "sm", onClick = function() syncPairNow(p) end }),
            btn({
                text = "Remove", variant = "ghost", controlSize = "sm",
                onClick = function() removeSyncPair(p) end,
            }),
        }),
    })
end

local function renderSync()
    local listArea
    if not state.syncLoaded then
        listArea = emptyState("…")
    elseif #state.pairs == 0 then
        listArea = emptyState("No sync pairs configured")
    else
        local items = {}
        for _, p in ipairs(state.pairs) do
            items[#items + 1] = pairRow(p)
            items[#items + 1] = sep({ opacity = 0.3 })
        end
        items[#items] = nil
        listArea = scr({ flexGrow = 1, gap = 8 }, items)
    end

    return col({ flexGrow = 1, gap = 10, padding = 12 }, {
        header("Folder Sync", goToMain),
        rowN({ align = "center", gap = 8 }, {
            lbl({ text = "Auto-sync", flexGrow = 1 }),
            tgl({
                checked = state.autoSync,
                onChange = function(value) toggleAutoSync(value == "true") end,
            }),
        }),
        sep({}),
        listArea,
        sep({}),
        lbl({ text = "Add pair", fontSize = 11, color = "on_surface_variant" }),
        inp({
            key = "remote-path-" .. state.pairFormGen, value = state.newRemotePath,
            placeholder = "remote:path", fontSize = 12,
            onChange = function(value) state.newRemotePath = value end,
        }),
        inp({
            key = "local-path-" .. state.pairFormGen, value = state.newLocalPath,
            placeholder = "~/local/path", fontSize = 12,
            onChange = function(value) state.newLocalPath = value end,
        }),
        rowN({ gap = 6 }, {
            btn({ text = "Add pair", flexGrow = 1, controlSize = "sm", onClick = addSyncPair }),
            btn({
                text = "Sync all now", flexGrow = 1, controlSize = "sm", variant = "outline",
                onClick = function() runNotified("Sync all", BIN .. " sync-all", refreshSync) end,
            }),
        }),
    })
end

local function accountRow(d)
    local removeLabel = "Remove"
    local removeVariant = "ghost"
    if state.pendingRemoveAccount == d.name then
        removeLabel = "Confirm?"
        removeVariant = "destructive"
    end

    return rowN({ align = "center", gap = 8, key = d.name }, {
        col({ flexGrow = 1 }, {
            lbl({ text = d.name, fontWeight = "medium" }),
            lbl({ text = d.type, fontSize = 11, color = "on_surface_variant" }),
        }),
        btn({
            text = removeLabel, variant = removeVariant, controlSize = "sm",
            onClick = function() confirmRemoveAccount(d.name) end,
        }),
    })
end

local function renderAccounts()
    local listArea
    if #state.drives == 0 then
        local text = "…"
        if state.loaded then text = "No accounts configured" end
        listArea = emptyState(text)
    else
        local items = {}
        for _, d in ipairs(state.drives) do
            items[#items + 1] = accountRow(d)
            items[#items + 1] = sep({ opacity = 0.3 })
        end
        items[#items] = nil
        listArea = scr({ flexGrow = 1, gap = 8 }, items)
    end

    local providerOptions = {}
    for _, p in ipairs(PROVIDERS) do
        providerOptions[#providerOptions + 1] = p.label
    end

    return col({ flexGrow = 1, gap = 10, padding = 12 }, {
        header("Accounts", goToMain),
        listArea,
        sep({}),
        lbl({ text = "Add account", fontSize = 11, color = "on_surface_variant" }),
        sel({
            options = providerOptions, selectedIndex = state.providerIndex - 1,
            onChange = function(idxStr) state.providerIndex = tonumber(idxStr) + 1 end,
        }),
        inp({
            key = "account-name-" .. state.addAccountFormGen, value = state.newAccountName,
            placeholder = "Account name (e.g. personal)", fontSize = 12,
            onChange = function(value) state.newAccountName = value end,
        }),
        btn({ text = "Create (opens a terminal)", onClick = createAccount }),
    })
end

function render()
    local tree = renderMain()
    if state.view == "sync" then
        tree = renderSync()
    elseif state.view == "accounts" then
        tree = renderAccounts()
    end
    panel.render(tree)
end

-- ── Lifecycle ──

function onOpen(context)
    state.view = "main"
    state.pendingRemoveAccount = nil
    panel.setWantsSecondTicks(true)
    refreshStatus()
    render()
end

function onClose()
    panel.setWantsSecondTicks(false)
end

function update()
    if state.view == "main" or state.view == "accounts" then
        refreshStatus()
    end
end
