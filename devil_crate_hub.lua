-- DEVIL HUB: crate collector for PlaceId 120475074479690.
-- Uses Workspace.Crates prompts. Collection is confirmed only by a world-state change.

if game.PlaceId ~= 120475074479690 then
    warn("[DevilHub] Wrong place: " .. tostring(game.PlaceId))
    return
end

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local cratesFolder = Workspace:WaitForChild("Crates", 12)
if not cratesFolder then
    warn("[DevilHub] Workspace.Crates was not found")
    return
end

local env = type(getgenv) == "function" and getgenv() or _G
if env.DEVIL_CRATE_HUB and type(env.DEVIL_CRATE_HUB.stop) == "function" then
    pcall(env.DEVIL_CRATE_HUB.stop)
end

local state = {
    alive = true, enabled = false, busy = false, rareFirst = true,
    selected = {}, catalog = {}, logs = {}, connections = {}, rowConnections = {},
    lastAttempt = setmetatable({}, { __mode = "k" }),
    retries = setmetatable({}, { __mode = "k" }),
    attempts = 0, confirmed = 0, unconfirmed = 0, live = 0,
    safeCFrame = nil, safeSource = "unset", search = "", dirty = true,
}
env.DEVIL_CRATE_HUB = state

local C = {
    panel = Color3.fromRGB(19, 24, 29),
    surface = Color3.fromRGB(42, 51, 58),
    surfaceOn = Color3.fromRGB(48, 79, 83),
    border = Color3.fromRGB(102, 124, 131),
    white = Color3.fromRGB(246, 250, 250),
    muted = Color3.fromRGB(187, 201, 205),
    accent = Color3.fromRGB(112, 232, 221),
    amber = Color3.fromRGB(255, 205, 113),
}

local rarityOrder = {
    Common = 1, Uncommon = 2, Rare = 3, Epic = 4,
    Legendary = 5, Mythic = 6, Cosmic = 7, Secret = 8,
}

local function norm(value)
    return tostring(value or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
end

local function crateType(name)
    return (name:gsub("_N%d+$", ""))
end

local function crateInfo(name)
    local kind = crateType(name)
    local family, rarity = kind:match("^Crate_(.+)_([^_]+)$")
    return family or kind, rarity or "Unknown"
end

local function promptFor(model)
    local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
    if prompt and prompt.Enabled then return prompt end
    return nil
end

local function liveCrate(model)
    return model and model.Parent == cratesFolder and model:IsA("Model")
        and promptFor(model) ~= nil
end

local function characterRoot()
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return nil end
    return character:FindFirstChild("HumanoidRootPart")
end

local function safeFromSpawn()
    local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation")
    if spawn then
        state.safeCFrame = spawn.CFrame + Vector3.new(0, 4, 0)
        state.safeSource = "SpawnLocation"
    end
end
safeFromSpawn()

local function teleport(cf)
    local root = characterRoot()
    if not root then return false end
    local character = root.Parent
    character:PivotTo(cf)
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero
    return true
end

local function round(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius or 6)
    corner.Parent = parent
end

local function makeText(class, parent, name, value, size)
    local item = Instance.new(class)
    item.Name = name
    item.BackgroundTransparency = 1
    item.BorderSizePixel = 0
    item.Font = Enum.Font.GothamMedium
    item.Text = value
    item.TextSize = size or 14
    item.TextColor3 = C.white
    item.TextXAlignment = Enum.TextXAlignment.Left
    item.Parent = parent
    return item
end

local function button(parent, name, value)
    local item = makeText("TextButton", parent, name, value, 13)
    item.BackgroundTransparency = 0.12
    item.BackgroundColor3 = C.surface
    item.Font = Enum.Font.GothamBold
    item.TextXAlignment = Enum.TextXAlignment.Center
    round(item)
    return item
end

local gui = Instance.new("ScreenGui")
gui.Name = "DevilCrateHub"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 125
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(590, 430)
panel.BackgroundColor3 = C.panel
panel.BackgroundTransparency = 0.1
panel.BorderSizePixel = 0
panel.Parent = gui
round(panel, 8)
local outline = Instance.new("UIStroke")
outline.Color = C.border
outline.Transparency = 0.25
outline.Thickness = 1
outline.Parent = panel
local scale = Instance.new("UIScale")
scale.Parent = panel

local header = makeText("TextLabel", panel, "Title", "DEVIL HUB", 18)
header.Font = Enum.Font.GothamBold
header.Position = UDim2.fromOffset(18, 6)
header.Size = UDim2.new(1, -74, 0, 36)
header.Active = true
local close = button(panel, "Close", "X")
close.Position = UDim2.new(1, -42, 0, 8)
close.Size = UDim2.fromOffset(30, 30)
local dock = button(gui, "Open", "DEVIL HUB")
dock.Position = UDim2.fromOffset(16, 120)
dock.Size = UDim2.fromOffset(110, 38)
dock.BackgroundColor3 = C.panel
dock.Visible = false

local sub = makeText("TextLabel", panel, "Subtitle", "CRATE COLLECTION  /  LIVE WORLD", 11)
sub.TextColor3 = C.accent
sub.Position = UDim2.fromOffset(18, 37)
sub.Size = UDim2.new(1, -36, 0, 18)

local tabsFrame = Instance.new("Frame")
tabsFrame.BackgroundTransparency = 1
tabsFrame.Position = UDim2.fromOffset(12, 64)
tabsFrame.Size = UDim2.new(1, -24, 0, 34)
tabsFrame.Parent = panel
local body = Instance.new("Frame")
body.BackgroundTransparency = 1
body.Position = UDim2.fromOffset(14, 108)
body.Size = UDim2.new(1, -28, 1, -120)
body.Parent = panel

local pages, tabs = {}, {}
for index, name in ipairs({ "AUTO", "CRATES", "SAFE", "LOG" }) do
    local tab = button(tabsFrame, name .. "Tab", name)
    tab.Position = UDim2.new((index - 1) / 4, 2, 0, 0)
    tab.Size = UDim2.new(1 / 4, -6, 1, 0)
    tabs[name] = tab
    local page = Instance.new("Frame")
    page.Name = name
    page.BackgroundTransparency = 1
    page.Size = UDim2.fromScale(1, 1)
    page.Visible = false
    page.Parent = body
    pages[name] = page
end
local function showPage(name)
    for key, page in pairs(pages) do
        page.Visible = key == name
        tabs[key].BackgroundColor3 = key == name and C.surfaceOn or C.surface
        tabs[key].TextColor3 = key == name and C.accent or C.white
    end
end
for name, tab in pairs(tabs) do
    table.insert(state.connections, tab.Activated:Connect(function() showPage(name) end))
end
showPage("AUTO")

local function label(parent, name, value, y, height, color)
    local item = makeText("TextLabel", parent, name, value, 14)
    item.Position = UDim2.fromOffset(4, y)
    item.Size = UDim2.new(1, -8, 0, height)
    item.TextColor3 = color or C.white
    item.TextWrapped = true
    item.TextYAlignment = Enum.TextYAlignment.Center
    return item
end

local autoScroll = Instance.new("ScrollingFrame")
autoScroll.Name = "AutoControls"
autoScroll.Size = UDim2.fromScale(1, 1)
autoScroll.BackgroundTransparency = 1
autoScroll.BorderSizePixel = 0
autoScroll.ScrollBarThickness = 3
autoScroll.CanvasSize = UDim2.fromOffset(0, 360)
autoScroll.Parent = pages.AUTO
label(autoScroll, "AutoTitle", "AUTO COLLECT", 0, 32).Font = Enum.Font.GothamBold
local toggle = button(autoScroll, "AutoToggle", "OFF")
toggle.Position = UDim2.new(1, -96, 0, 1)
toggle.Size = UDim2.fromOffset(90, 32)
local counts = label(autoScroll, "Counts", "World 0  /  Selected 0", 44, 28, C.muted)
local stats = label(autoScroll, "Stats", "Attempts 0  /  Confirmed 0  /  Unconfirmed 0", 78, 28, C.muted)
local status = label(autoScroll, "Status", "Idle", 118, 58, C.white)
local prioritize = button(autoScroll, "RareFirst", "RARE FIRST: ON")
prioritize.Position = UDim2.fromOffset(4, 190)
prioritize.Size = UDim2.new(1, -8, 0, 36)
local once = button(autoScroll, "CollectOnce", "COLLECT ONCE")
once.Position = UDim2.fromOffset(4, 238)
once.Size = UDim2.new(0.5, -7, 0, 38)
local scanNow = button(autoScroll, "ScanNow", "REFRESH")
scanNow.Position = UDim2.new(0.5, 3, 0, 238)
scanNow.Size = UDim2.new(0.5, -7, 0, 38)
label(autoScroll, "SafeHint", "Return point: SpawnLocation", 293, 34, C.muted)

local search = Instance.new("TextBox")
search.Name = "Search"
search.Position = UDim2.fromOffset(0, 0)
search.Size = UDim2.new(1, -144, 0, 34)
search.BackgroundColor3 = C.surface
search.BackgroundTransparency = 0.12
search.BorderSizePixel = 0
search.TextColor3 = C.white
search.PlaceholderColor3 = C.muted
search.PlaceholderText = "Search crate or rarity"
search.Text = ""
search.ClearTextOnFocus = false
search.Font = Enum.Font.GothamMedium
search.TextSize = 13
search.Parent = pages.CRATES
round(search)
local all = button(pages.CRATES, "All", "ALL")
all.Position = UDim2.new(1, -138, 0, 0)
all.Size = UDim2.fromOffset(64, 34)
local clear = button(pages.CRATES, "Clear", "CLEAR")
clear.Position = UDim2.new(1, -68, 0, 0)
clear.Size = UDim2.fromOffset(68, 34)
local crateList = Instance.new("ScrollingFrame")
crateList.Name = "CrateList"
crateList.Position = UDim2.fromOffset(0, 42)
crateList.Size = UDim2.new(1, 0, 1, -42)
crateList.BackgroundTransparency = 1
crateList.BorderSizePixel = 0
crateList.ScrollBarThickness = 4
crateList.ScrollBarImageColor3 = C.accent
crateList.Parent = pages.CRATES

local safeInfo = label(pages.SAFE, "SafeInfo", "Return point: unset", 4, 62)
local saveSafe = button(pages.SAFE, "SaveSafe", "SET HERE")
saveSafe.Position = UDim2.fromOffset(4, 83)
saveSafe.Size = UDim2.new(0.5, -8, 0, 42)
local resetSafe = button(pages.SAFE, "ResetSafe", "USE SPAWN")
resetSafe.Position = UDim2.new(0.5, 4, 0, 83)
resetSafe.Size = UDim2.new(0.5, -8, 0, 42)
local returnSafe = button(pages.SAFE, "ReturnSafe", "RETURN TO SAFE ZONE")
returnSafe.Position = UDim2.fromOffset(4, 143)
returnSafe.Size = UDim2.new(1, -8, 0, 42)

local copyLog = button(pages.LOG, "CopyLog", "COPY LOG")
copyLog.Position = UDim2.new(1, -96, 0, 0)
copyLog.Size = UDim2.fromOffset(96, 32)
local logScroll = Instance.new("ScrollingFrame")
logScroll.Name = "LogScroll"
logScroll.Position = UDim2.fromOffset(0, 40)
logScroll.Size = UDim2.new(1, 0, 1, -40)
logScroll.BackgroundTransparency = 1
logScroll.BorderSizePixel = 0
logScroll.ScrollBarThickness = 4
logScroll.Parent = pages.LOG
local logText = makeText("TextLabel", logScroll, "LogText", "", 12)
logText.TextColor3 = C.muted
logText.TextWrapped = true
logText.TextYAlignment = Enum.TextYAlignment.Top

local function log(message)
    local line = os.date("%H:%M:%S") .. "  " .. tostring(message)
    state.logs[#state.logs + 1] = line
    if #state.logs > 80 then table.remove(state.logs, 1) end
    status.Text = tostring(message)
    logText.Text = table.concat(state.logs, "\n")
    local height = math.max(160, #state.logs * 24)
    logText.Size = UDim2.new(1, -8, 0, height)
    logScroll.CanvasSize = UDim2.fromOffset(0, height + 8)
    print("[DevilHub] " .. tostring(message))
end

local function updateSafeInfo()
    local cf = state.safeCFrame
    if cf then
        local p = cf.Position
        safeInfo.Text = string.format("Return point: %s\nX %.0f   Y %.0f   Z %.0f",
            state.safeSource, p.X, p.Y, p.Z)
    else
        safeInfo.Text = "Return point: unset"
    end
    local hint = autoScroll:FindFirstChild("SafeHint")
    if hint then hint.Text = "Return point: " .. state.safeSource end
end
updateSafeInfo()

local function updateStats()
    stats.Text = string.format("Attempts %d  /  Confirmed %d  /  Unconfirmed %d",
        state.attempts, state.confirmed, state.unconfirmed)
end

local function renderCrates()
    if not state.dirty then return end
    state.dirty = false
    for _, connection in ipairs(state.rowConnections) do connection:Disconnect() end
    state.rowConnections = {}
    for _, child in ipairs(crateList:GetChildren()) do child:Destroy() end
    local names = {}
    for key, item in pairs(state.catalog) do
        if state.search == "" or key:find(state.search, 1, true)
            or norm(item.rarity):find(state.search, 1, true) then
            names[#names + 1] = key
        end
    end
    table.sort(names)
    if #names == 0 then
        local empty = label(crateList, "Empty", "No crates found", 0, 44, C.muted)
        empty.TextSize = 13
    end
    for index, key in ipairs(names) do
        local item = state.catalog[key]
        local row = button(crateList, "Crate" .. index, "")
        row.Position = UDim2.fromOffset(0, (index - 1) * 56)
        row.Size = UDim2.new(1, -7, 0, 50)
        row.BackgroundColor3 = state.selected[key] and C.surfaceOn or C.surface
        local mark = makeText("TextLabel", row, "Mark", state.selected[key] and "[x]" or "[ ]", 17)
        mark.Position = UDim2.fromOffset(10, 8)
        mark.Size = UDim2.fromOffset(32, 34)
        mark.TextColor3 = C.accent
        local title = makeText("TextLabel", row, "Name", item.family .. "  /  " .. item.rarity, 13)
        title.Position = UDim2.fromOffset(48, 4)
        title.Size = UDim2.new(1, -56, 0, 22)
        title.TextTruncate = Enum.TextTruncate.AtEnd
        local meta = makeText("TextLabel", row, "Meta", "Live " .. item.live .. "   |   " .. item.kind, 11)
        meta.Position = UDim2.fromOffset(48, 25)
        meta.Size = UDim2.new(1, -56, 0, 20)
        meta.TextColor3 = C.muted
        meta.TextTruncate = Enum.TextTruncate.AtEnd
        table.insert(state.rowConnections, row.Activated:Connect(function()
            state.selected[key] = not state.selected[key] or nil
            state.dirty = true
            renderCrates()
            log((state.selected[key] and "Selected " or "Deselected ") .. item.kind)
        end))
    end
    crateList.CanvasSize = UDim2.fromOffset(0, math.max(44, #names * 56))
end

local function scanWorld()
    local previous = {}
    for key, item in pairs(state.catalog) do
        previous[key] = item.live
        item.live = 0
    end
    local count = 0
    for _, model in ipairs(cratesFolder:GetChildren()) do
        if liveCrate(model) then
            count = count + 1
            local kind = crateType(model.Name)
            local key = norm(kind)
            local item = state.catalog[key]
            if not item then
                local family, rarity = crateInfo(model.Name)
                item = { kind = kind, family = family, rarity = rarity, live = 0 }
                state.catalog[key] = item
                state.dirty = true
            end
            item.live = item.live + 1
        end
    end
    for key, item in pairs(state.catalog) do
        if item.live ~= (previous[key] or 0) then state.dirty = true end
    end
    state.live = count
    local selectedCount = 0
    for _ in pairs(state.selected) do selectedCount = selectedCount + 1 end
    counts.Text = string.format("World %d  /  Selected types %d", count, selectedCount)
    renderCrates()
end

local function chooseCrate()
    local options = {}
    for _, model in ipairs(cratesFolder:GetChildren()) do
        if liveCrate(model) and state.selected[norm(crateType(model.Name))]
            and (state.retries[model] or 0) < 2
            and os.clock() - (state.lastAttempt[model] or -math.huge) >= 12 then
            options[#options + 1] = model
        end
    end
    if #options == 0 then return nil end
    local root = characterRoot()
    table.sort(options, function(a, b)
        if state.rareFirst then
            local _, ar = crateInfo(a.Name)
            local _, br = crateInfo(b.Name)
            local ap, bp = rarityOrder[ar] or 0, rarityOrder[br] or 0
            if ap ~= bp then return ap > bp end
        end
        if root then
            local da = (a:GetPivot().Position - root.Position).Magnitude
            local db = (b:GetPivot().Position - root.Position).Magnitude
            if da ~= db then return da < db end
        end
        return a.Name < b.Name
    end)
    return options[1]
end

local function activatePrompt(prompt)
    if type(fireproximityprompt) == "function" then
        fireproximityprompt(prompt)
    else
        prompt:InputHoldBegin()
        task.wait(prompt.HoldDuration + 0.12)
        prompt:InputHoldEnd()
    end
end

local function collect(model)
    if state.busy or not liveCrate(model) then return end
    if not state.safeCFrame then
        log("Set a safe return point first")
        return
    end
    state.busy = true
    state.lastAttempt[model] = os.clock()
    state.retries[model] = (state.retries[model] or 0) + 1
    state.attempts = state.attempts + 1
    updateStats()
    local name = model.Name
    local target = model:GetPivot().Position
    log("Going to " .. name)
    local ok, err = pcall(function()
        local root = characterRoot()
        if not root then error("Character unavailable") end
        local destination = CFrame.lookAt(target + Vector3.new(0, 4, 0), target)
        if not teleport(destination) then error("Teleport failed") end
        task.wait(0.5)
        root = characterRoot()
        if not root or (root.Position - destination.Position).Magnitude > 12 then
            error("Teleport did not stick")
        end
        local prompt = promptFor(model)
        if not prompt then error("Crate prompt disappeared") end
        activatePrompt(prompt)
        task.wait(1.3)
    end)
    local returned = teleport(state.safeCFrame)
    if not returned then log("Return failed: character unavailable") end
    if not ok then
        state.unconfirmed = state.unconfirmed + 1
        log("Interaction error: " .. tostring(err):sub(1, 110))
    elseif not liveCrate(model) then
        state.confirmed = state.confirmed + 1
        log("Confirmed collected: " .. name)
    else
        state.unconfirmed = state.unconfirmed + 1
        log("Still visible after prompt: " .. name)
    end
    updateStats()
    state.busy = false
end

local function refreshLayout()
    local camera = Workspace.CurrentCamera
    if not camera then return end
    local viewport = camera.ViewportSize
    scale.Scale = math.clamp(math.min((viewport.X - 20) / 590,
        (viewport.Y - 20) / 430), 0.32, 1)
    if viewport.X / scale.Scale < 470 then
        search.Size = UDim2.new(1, 0, 0, 34)
        all.Position = UDim2.fromOffset(0, 42)
        clear.Position = UDim2.fromOffset(70, 42)
        crateList.Position = UDim2.fromOffset(0, 82)
        crateList.Size = UDim2.new(1, 0, 1, -82)
    else
        search.Size = UDim2.new(1, -144, 0, 34)
        all.Position = UDim2.new(1, -138, 0, 0)
        clear.Position = UDim2.new(1, -68, 0, 0)
        crateList.Position = UDim2.fromOffset(0, 42)
        crateList.Size = UDim2.new(1, 0, 1, -42)
    end
end
refreshLayout()
if Workspace.CurrentCamera then
    table.insert(state.connections, Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshLayout))
end

local dragging, dragStart, panelStart
table.insert(state.connections, header.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then return end
    dragging, dragStart, panelStart = input, input.Position, panel.Position
    table.insert(state.connections, input.Changed:Connect(function()
        if input.UserInputState == Enum.UserInputState.End then dragging = nil end
    end))
end))
table.insert(state.connections, UserInputService.InputChanged:Connect(function(input)
    if not dragging or (input.UserInputType ~= Enum.UserInputType.MouseMovement
        and input ~= dragging) then return end
    local camera = Workspace.CurrentCamera
    if not camera then return end
    local viewport = camera.ViewportSize
    local delta = input.Position - dragStart
    local x = panelStart.X.Scale * viewport.X + panelStart.X.Offset + delta.X
    local y = panelStart.Y.Scale * viewport.Y + panelStart.Y.Offset + delta.Y
    local halfWidth = 590 * scale.Scale / 2
    local halfHeight = 430 * scale.Scale / 2
    panel.Position = UDim2.fromOffset(math.clamp(x, halfWidth, viewport.X - halfWidth),
        math.clamp(y, halfHeight, viewport.Y - halfHeight))
end))

table.insert(state.connections, close.Activated:Connect(function()
    panel.Visible = false
    dock.Visible = true
end))
table.insert(state.connections, dock.Activated:Connect(function()
    panel.Visible = true
    dock.Visible = false
end))
table.insert(state.connections, toggle.Activated:Connect(function()
    state.enabled = not state.enabled
    toggle.Text = state.enabled and "ON" or "OFF"
    toggle.BackgroundColor3 = state.enabled and C.surfaceOn or C.surface
    toggle.TextColor3 = state.enabled and C.accent or C.white
    log(state.enabled and "Auto collect on" or "Auto collect off")
end))
table.insert(state.connections, prioritize.Activated:Connect(function()
    state.rareFirst = not state.rareFirst
    prioritize.Text = state.rareFirst and "RARE FIRST: ON" or "RARE FIRST: OFF"
end))
table.insert(state.connections, once.Activated:Connect(function()
    scanWorld()
    local model = chooseCrate()
    if model then task.spawn(collect, model) else log("No selected crate available") end
end))
table.insert(state.connections, scanNow.Activated:Connect(function()
    scanWorld()
    log("Scan complete: " .. state.live .. " live crates")
end))
table.insert(state.connections, search:GetPropertyChangedSignal("Text"):Connect(function()
    state.search = norm(search.Text)
    state.dirty = true
    renderCrates()
end))
table.insert(state.connections, all.Activated:Connect(function()
    for key in pairs(state.catalog) do state.selected[key] = true end
    state.dirty = true
    renderCrates()
    log("Selected all crate types")
end))
table.insert(state.connections, clear.Activated:Connect(function()
    state.selected = {}
    state.dirty = true
    renderCrates()
    log("Cleared crate selection")
end))
table.insert(state.connections, saveSafe.Activated:Connect(function()
    local root = characterRoot()
    if not root then
        log("Character unavailable")
        return
    end
    state.safeCFrame = root.CFrame
    state.safeSource = "saved position"
    updateSafeInfo()
    log("Saved current position as safe zone")
end))
table.insert(state.connections, resetSafe.Activated:Connect(function()
    safeFromSpawn()
    updateSafeInfo()
    log(state.safeCFrame and "Safe zone set to spawn" or "SpawnLocation unavailable")
end))
table.insert(state.connections, returnSafe.Activated:Connect(function()
    if state.safeCFrame and teleport(state.safeCFrame) then
        log("Returned to safe zone")
    else
        log("Safe return unavailable")
    end
end))
table.insert(state.connections, copyLog.Activated:Connect(function()
    local copy = setclipboard or toclipboard or set_clipboard
    if type(copy) == "function" and pcall(copy, table.concat(state.logs, "\n")) then
        log("Log copied")
    else
        log("Clipboard unavailable")
    end
end))

state.stop = function()
    if not state.alive then return end
    state.alive = false
    state.enabled = false
    for _, connection in ipairs(state.connections) do connection:Disconnect() end
    for _, connection in ipairs(state.rowConnections) do connection:Disconnect() end
    gui:Destroy()
end

scanWorld()
log("Ready: " .. state.live .. " live crates / " .. state.safeSource)
task.spawn(function()
    while state.alive do
        local ok, err = pcall(function()
            scanWorld()
            if state.enabled and not state.busy then
                if next(state.selected) == nil then
                    if state.lastIdle ~= "selection" then
                        state.lastIdle = "selection"
                        log("Select crate types in CRATES")
                    end
                else
                    local model = chooseCrate()
                    if model then
                        state.lastIdle = nil
                        collect(model)
                    elseif state.lastIdle ~= "waiting" then
                        state.lastIdle = "waiting"
                        log("Waiting for selected crates")
                    end
                end
            end
        end)
        if not ok then
            state.busy = false
            log("Loop error: " .. tostring(err):sub(1, 120))
        end
        task.wait(0.8)
    end
end)
