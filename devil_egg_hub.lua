-- DEVIL HUB: field-egg collector for PlaceId 124216119978534.
-- Targets field eggs, preferring Workspace.RenderedEggs over the empty data folder.

if game.PlaceId ~= 124216119978534 then
    warn("[DevilHub] Wrong place: " .. tostring(game.PlaceId))
    return
end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local WS = game:GetService("Workspace")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local eggFolder = WS:WaitForChild("Eggs", 15)
local renderedFolder = WS:FindFirstChild("RenderedEggs")
local gameRemotes = RS:WaitForChild("Remotes", 15)
gameRemotes = gameRemotes and gameRemotes:FindFirstChild("Game")
local pickupRemote = gameRemotes and gameRemotes:FindFirstChild("EggPickup")
if not (eggFolder or renderedFolder) or not pickupRemote or not pickupRemote:IsA("RemoteEvent") then
    warn("[DevilHub] Field eggs or EggPickup remote is unavailable")
    return
end

local env = type(getgenv) == "function" and getgenv() or _G
if env.DEVIL_HUB_EGG and type(env.DEVIL_HUB_EGG.stop) == "function" then
    pcall(env.DEVIL_HUB_EGG.stop)
end
local state = {
    alive = true, enabled = false, busy = false, selected = {}, catalog = {},
    connections = {}, rowConnections = {}, logs = {}, attempts = 0, removed = 0, misses = 0,
    lastAttempt = setmetatable({}, { __mode = "k" }),
    retries = setmetatable({}, { __mode = "k" }),
    uuidWarned = setmetatable({}, { __mode = "k" }),
    search = "", minWeight = 0, dirty = true,
}
env.DEVIL_HUB_EGG = state

local C = {
    black = Color3.fromRGB(16, 16, 17),
    panel = Color3.fromRGB(28, 28, 30),
    surface = Color3.fromRGB(42, 42, 45),
    edge = Color3.fromRGB(76, 76, 80),
    white = Color3.fromRGB(247, 247, 248),
    muted = Color3.fromRGB(176, 176, 181),
    dim = Color3.fromRGB(121, 121, 128),
}

local function norm(value)
    return tostring(value or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
end

local function field(inst, keys)
    if not inst then return nil end
    for _, key in ipairs(keys) do
        local ok, value = pcall(function() return inst:GetAttribute(key) end)
        if ok and value ~= nil and value ~= "" then return value end
        local child = inst:FindFirstChild(key)
        if child and child:IsA("ValueBase") then
            local readOk, childValue = pcall(function() return child.Value end)
            if readOk and childValue ~= nil and childValue ~= "" then return childValue end
        end
    end
    return nil
end

local function eggData(model)
    return model:FindFirstChild("EggData") or model:FindFirstChild("Data")
end

local function eggName(model)
    local name = field(model, { "EggName", "DisplayName", "EggType" })
    if type(name) == "string" and name ~= "" then return name end
    local label = model:FindFirstChild("EggName", true)
    if label and label:IsA("TextLabel") and label.Text ~= "" then return label.Text end
    return model.Name
end

local ranks = { Common = true, Uncommon = true, Rare = true, Epic = true,
    Legendary = true, Mythic = true, Divine = true, Ethereal = true,
    Volcanic = true, Secret = true }
local function eggRarity(model)
    local value = field(model, { "Rarity", "EggRarity", "Tier", "Rank" })
        or field(eggData(model), { "Rarity", "EggRarity", "Tier", "Rank" })
    if value ~= nil then return tostring(value) end
    local label = model:FindFirstChild("EggName", true)
    if label then
        for _, item in ipairs(label:GetChildren()) do
            if item:IsA("UIGradient") and ranks[item.Name] then return item.Name end
        end
    end
    return "Unknown"
end

local function eggWeight(model)
    local value = field(eggData(model), { "Weight", "Kg", "Mass" })
        or field(model, { "Weight", "Kg", "Mass" })
    return tonumber(value)
end

local function eggUuid(model)
    local keys = { "UUID", "Uuid", "Uid", "UID", "EggUUID", "EggUid", "EggId", "EggID", "EntityId", "Id", "ID", "GUID" }
    local value = field(model, keys) or field(eggData(model), keys)
    if type(value) == "string" and #value >= 12 then return value end
    for _, item in ipairs(model:GetDescendants()) do
        if item:IsA("BasePart") or item:IsA("ProximityPrompt") then
            value = field(item, keys)
            if type(value) == "string" and #value >= 12 then return value end
        end
        if item:IsA("StringValue") and table.find(keys, item.Name) and #item.Value >= 12 then
            return item.Value
        end
    end
    return nil
end

local function pickupPrompt(model)
    local prompt = model:FindFirstChild("Pickup", true)
    if prompt and prompt:IsA("ProximityPrompt") then return prompt end
    return nil
end

local function root()
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return nil end
    return character:FindFirstChild("HumanoidRootPart")
end

local function fieldFolder()
    renderedFolder = WS:FindFirstChild("RenderedEggs") or renderedFolder
    if renderedFolder and #renderedFolder:GetChildren() > 0 then return renderedFolder end
    return eggFolder or renderedFolder
end

local function validFieldEgg(model)
    local folder = fieldFolder()
    return model and folder and model.Parent == folder
        and (model:IsA("Model") or model:IsA("BasePart"))
end

local function addCatalog(name, rarity, weight)
    if type(name) ~= "string" or name == "" or #name > 90 then return end
    local key = norm(name)
    local item = state.catalog[key]
    if not item then
        item = { name = name, rarity = "Unknown", weight = nil, live = 0 }
        state.catalog[key] = item
        state.dirty = true
    end
    if type(rarity) == "string" and rarity ~= "" and rarity ~= "Unknown" and item.rarity ~= rarity then
        item.rarity = rarity
        state.dirty = true
    end
    if weight and item.weight ~= weight then
        item.weight = weight
        state.dirty = true
    end
    return item
end

local function indexEggDatabase()
    local module = RS:FindFirstChild("GameData")
    module = module and module:FindFirstChild("Eggs")
    if not module or not module:IsA("ModuleScript") then return end
    local ok, data = pcall(require, module)
    if not ok or type(data) ~= "table" then return end
    local seen = {}
    local function walk(node, depth, inheritedRank)
        if type(node) ~= "table" or seen[node] or depth > 4 then return end
        seen[node] = true
        for key, value in pairs(node) do
            if type(value) == "table" then
                local rank = value.Rarity or value.Tier or value.Rank or inheritedRank
                if type(key) == "string" and ranks[key] then rank = key end
                local name = value.DisplayName or value.Name or value.EggName
                if type(name) ~= "string" and type(key) == "string"
                    and key:lower():find("egg", 1, true) then name = key end
                if type(name) == "string" and name:lower():find("egg", 1, true) then
                    addCatalog(name, type(rank) == "string" and rank or nil)
                end
                walk(value, depth + 1, rank)
            end
        end
    end
    walk(data, 0, nil)
end

local function indexPlacedNames()
    local plots = WS:FindFirstChild("Plots")
    if not plots then return end
    for _, plot in ipairs(plots:GetChildren()) do
        local eggs = plot:FindFirstChild("Eggs")
        if eggs then
            for _, model in ipairs(eggs:GetChildren()) do
                if model:IsA("Model") then
                    addCatalog(eggName(model), eggRarity(model))
                end
            end
        end
    end
end

local gui = Instance.new("ScreenGui")
gui.Name = "DevilHubEgg"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 120
gui.Parent = playerGui

local function corner(parent, radius)
    local object = Instance.new("UICorner")
    object.CornerRadius = UDim.new(0, radius or 6)
    object.Parent = parent
end
local function makeText(class, parent, name, text, size)
    local item = Instance.new(class)
    item.Name = name
    item.BackgroundTransparency = 1
    item.BorderSizePixel = 0
    item.Font = Enum.Font.GothamMedium
    item.TextSize = size or 14
    item.TextColor3 = C.white
    item.Text = text
    item.Parent = parent
    return item
end
local function button(parent, name, text)
    local item = makeText("TextButton", parent, name, text, 13)
    item.BackgroundTransparency = 0
    item.BackgroundColor3 = C.surface
    item.Font = Enum.Font.GothamBold
    corner(item, 6)
    return item
end

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.BackgroundColor3 = C.panel
panel.BorderSizePixel = 0
panel.Parent = gui
corner(panel, 8)
local stroke = Instance.new("UIStroke")
stroke.Color = C.edge
stroke.Thickness = 1
stroke.Parent = panel
local scale = Instance.new("UIScale")
scale.Parent = panel

local header = makeText("TextLabel", panel, "Header", "DEVIL HUB", 17)
header.Font = Enum.Font.GothamBold
header.TextXAlignment = Enum.TextXAlignment.Left
header.Position = UDim2.fromOffset(18, 6)
header.Size = UDim2.new(1, -72, 0, 34)
header.Active = true
local close = button(panel, "Close", "X")
close.Position = UDim2.new(1, -42, 0, 8)
close.Size = UDim2.fromOffset(30, 30)
local divider = Instance.new("Frame")
divider.Position = UDim2.fromOffset(0, 44)
divider.Size = UDim2.new(1, 0, 0, 1)
divider.BorderSizePixel = 0
divider.BackgroundColor3 = C.edge
divider.Parent = panel

local dock = button(gui, "Open", "D")
dock.Position = UDim2.fromOffset(16, 152)
dock.Size = UDim2.fromOffset(44, 44)
dock.BackgroundColor3 = C.white
dock.TextColor3 = C.black
dock.TextSize = 17
dock.Visible = false

local tabBar = Instance.new("Frame")
tabBar.Position = UDim2.fromOffset(12, 54)
tabBar.Size = UDim2.new(1, -24, 0, 36)
tabBar.BackgroundTransparency = 1
tabBar.Parent = panel
local content = Instance.new("Frame")
content.Position = UDim2.fromOffset(12, 98)
content.Size = UDim2.new(1, -24, 1, -110)
content.BackgroundTransparency = 1
content.Parent = panel

local pages, tabs = {}, {}
for index, name in ipairs({ "AUTO", "EGGS", "LOG" }) do
    local tab = button(tabBar, name .. "Tab", name)
    tab.Position = UDim2.new((index - 1) / 3, 0, 0, 0)
    tab.Size = UDim2.new(1 / 3, -5, 1, 0)
    tabs[name] = tab
    local page = Instance.new("Frame")
    page.Name = name
    page.Size = UDim2.fromScale(1, 1)
    page.BackgroundTransparency = 1
    page.Visible = false
    page.Parent = content
    pages[name] = page
end
local function showPage(name)
    for key, page in pairs(pages) do
        page.Visible = key == name
        tabs[key].BackgroundColor3 = key == name and C.white or C.surface
        tabs[key].TextColor3 = key == name and C.black or C.white
    end
end
for name, tab in pairs(tabs) do
    table.insert(state.connections, tab.Activated:Connect(function() showPage(name) end))
end
showPage("AUTO")

local autoPage = pages.AUTO
local autoScroll = Instance.new("ScrollingFrame")
autoScroll.Name = "Controls"
autoScroll.Size = UDim2.fromScale(1, 1)
autoScroll.BackgroundTransparency = 1
autoScroll.BorderSizePixel = 0
autoScroll.ScrollBarThickness = 3
autoScroll.ScrollBarImageColor3 = C.muted
autoScroll.CanvasSize = UDim2.fromOffset(0, 290)
autoScroll.Parent = autoPage
local function autoLabel(name, text, y, height, color)
    local item = makeText("TextLabel", autoScroll, name, text, 14)
    item.Position = UDim2.fromOffset(4, y)
    item.Size = UDim2.new(1, -12, 0, height)
    item.TextXAlignment = Enum.TextXAlignment.Left
    item.TextYAlignment = Enum.TextYAlignment.Center
    item.TextWrapped = true
    item.TextColor3 = color or C.white
    return item
end
autoLabel("AutoTitle", "AUTO EGG", 4, 30).Font = Enum.Font.GothamBold
local toggle = button(autoScroll, "AutoToggle", "OFF")
toggle.Position = UDim2.new(1, -94, 0, 4)
toggle.Size = UDim2.fromOffset(82, 30)
local selectedLabel = autoLabel("Selected", "Selected: 0", 48, 25, C.muted)
local liveLabel = autoLabel("Live", "World eggs: 0", 79, 25, C.muted)
local statsLabel = autoLabel("Stats", "Attempts: 0  |  Removed: 0  |  Missed: 0", 110, 28, C.muted)
local statusLabel = autoLabel("Status", "Idle", 149, 62)
local minLabel = autoLabel("MinWeightLabel", "MIN WEIGHT (kg)", 223, 24, C.muted)
minLabel.TextSize = 12
local minInput = Instance.new("TextBox")
minInput.Name = "MinWeight"
minInput.Position = UDim2.new(1, -114, 0, 218)
minInput.Size = UDim2.fromOffset(102, 34)
minInput.BackgroundColor3 = C.surface
minInput.BorderSizePixel = 0
minInput.TextColor3 = C.white
minInput.PlaceholderColor3 = C.dim
minInput.PlaceholderText = "0"
minInput.Text = "0"
minInput.ClearTextOnFocus = false
minInput.Font = Enum.Font.GothamMedium
minInput.TextSize = 14
minInput.Parent = autoScroll
corner(minInput, 6)

local eggPage = pages.EGGS
local search = Instance.new("TextBox")
search.Name = "Search"
search.Position = UDim2.fromOffset(0, 0)
search.Size = UDim2.new(1, -148, 0, 34)
search.BackgroundColor3 = C.surface
search.BorderSizePixel = 0
search.TextColor3 = C.white
search.PlaceholderColor3 = C.dim
search.PlaceholderText = "Search eggs"
search.Text = ""
search.ClearTextOnFocus = false
search.Font = Enum.Font.GothamMedium
search.TextSize = 13
search.Parent = eggPage
corner(search, 6)
local allButton = button(eggPage, "All", "ALL")
allButton.Position = UDim2.new(1, -140, 0, 0)
allButton.Size = UDim2.fromOffset(64, 34)
local clearButton = button(eggPage, "Clear", "CLEAR")
clearButton.Position = UDim2.new(1, -70, 0, 0)
clearButton.Size = UDim2.fromOffset(70, 34)
local eggScroll = Instance.new("ScrollingFrame")
eggScroll.Name = "EggList"
eggScroll.Position = UDim2.fromOffset(0, 43)
eggScroll.Size = UDim2.new(1, 0, 1, -43)
eggScroll.BackgroundTransparency = 1
eggScroll.BorderSizePixel = 0
eggScroll.ScrollBarThickness = 4
eggScroll.ScrollBarImageColor3 = C.muted
eggScroll.Parent = eggPage

local logPage = pages.LOG
local copyButton = button(logPage, "Copy", "COPY")
copyButton.Position = UDim2.new(1, -72, 0, 0)
copyButton.Size = UDim2.fromOffset(72, 32)
local logScroll = Instance.new("ScrollingFrame")
logScroll.Name = "LogList"
logScroll.Position = UDim2.fromOffset(0, 40)
logScroll.Size = UDim2.new(1, 0, 1, -40)
logScroll.BackgroundTransparency = 1
logScroll.BorderSizePixel = 0
logScroll.ScrollBarThickness = 4
logScroll.ScrollBarImageColor3 = C.muted
logScroll.Parent = logPage
local logText = makeText("TextLabel", logScroll, "LogText", "", 12)
logText.TextColor3 = C.muted
logText.TextXAlignment = Enum.TextXAlignment.Left
logText.TextYAlignment = Enum.TextYAlignment.Top
logText.TextWrapped = true

local function log(message)
    local line = os.date("%H:%M:%S") .. "  " .. tostring(message)
    state.logs[#state.logs + 1] = line
    if #state.logs > 70 then table.remove(state.logs, 1) end
    statusLabel.Text = tostring(message)
    logText.Text = table.concat(state.logs, "\n")
    local height = math.max(160, #state.logs * 31)
    logText.Size = UDim2.new(1, -8, 0, height)
    logScroll.CanvasSize = UDim2.fromOffset(0, height + 8)
    print("[DevilHub] " .. tostring(message))
end

local function renderEggs()
    if not state.dirty then return end
    state.dirty = false
    for _, connection in ipairs(state.rowConnections) do connection:Disconnect() end
    state.rowConnections = {}
    for _, child in ipairs(eggScroll:GetChildren()) do child:Destroy() end
    local names = {}
    for key, item in pairs(state.catalog) do
        if state.search == "" or key:find(state.search, 1, true)
            or norm(item.rarity):find(state.search, 1, true) then
            names[#names + 1] = key
        end
    end
    table.sort(names)
    local selectedCount = 0
    for _ in pairs(state.selected) do selectedCount = selectedCount + 1 end
    selectedLabel.Text = "Selected: " .. selectedCount .. "  /  Catalog: " .. tostring(#names)
    if #names == 0 then
        local empty = makeText("TextLabel", eggScroll, "Empty", "No eggs found", 14)
        empty.TextColor3 = C.muted
        empty.Size = UDim2.new(1, 0, 0, 48)
    end
    for index, key in ipairs(names) do
        local item = state.catalog[key]
        local row = button(eggScroll, "Egg_" .. index, "")
        row.Position = UDim2.fromOffset(0, (index - 1) * 56)
        row.Size = UDim2.new(1, -8, 0, 50)
        row.BackgroundColor3 = state.selected[key] and Color3.fromRGB(68, 68, 71) or C.surface
        local mark = makeText("TextLabel", row, "Mark", state.selected[key] and "[x]" or "[ ]", 17)
        mark.Position = UDim2.fromOffset(8, 7)
        mark.Size = UDim2.fromOffset(34, 36)
        local title = makeText("TextLabel", row, "Name", item.name, 13)
        title.Position = UDim2.fromOffset(46, 4)
        title.Size = UDim2.new(1, -54, 0, 21)
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.TextTruncate = Enum.TextTruncate.AtEnd
        local details = string.format("%s  |  %s kg  |  live %d", item.rarity,
            item.weight and string.format("%.2f", item.weight) or "?", item.live or 0)
        local meta = makeText("TextLabel", row, "Meta", details, 11)
        meta.TextColor3 = C.muted
        meta.Position = UDim2.fromOffset(46, 25)
        meta.Size = UDim2.new(1, -54, 0, 20)
        meta.TextXAlignment = Enum.TextXAlignment.Left
        meta.TextTruncate = Enum.TextTruncate.AtEnd
        table.insert(state.rowConnections, row.Activated:Connect(function()
            state.selected[key] = not state.selected[key] or nil
            state.dirty = true
            renderEggs()
            log((state.selected[key] and "Selected: " or "Deselected: ") .. item.name)
        end))
    end
    eggScroll.CanvasSize = UDim2.fromOffset(0, math.max(48, #names * 56))
end

local function updateStats()
    statsLabel.Text = string.format("Attempts: %d  |  Removed: %d  |  Missed: %d",
        state.attempts, state.removed, state.misses)
end

local function refreshWorld()
    local previous = {}
    for key, item in pairs(state.catalog) do
        previous[key] = item.live
        item.live = 0
    end
    local count = 0
    local folder = fieldFolder()
    for _, model in ipairs(folder and folder:GetChildren() or {}) do
        if validFieldEgg(model) then
            count = count + 1
            local item = addCatalog(eggName(model), eggRarity(model), eggWeight(model))
            if item then item.live = item.live + 1 end
        end
    end
    for key, item in pairs(state.catalog) do
        if item.live ~= (previous[key] or 0) then state.dirty = true end
    end
    if state.liveCount ~= count then state.dirty = true end
    state.liveCount = count
    liveLabel.Text = "World eggs: " .. count .. "  /  " .. (folder and folder.Name or "none")
end

local function pullLocal(model)
    local characterRoot = root()
    if not characterRoot or not validFieldEgg(model) then return false end
    local ok, original = pcall(function() return model:GetPivot() end)
    if not ok then return false end
    local destination = CFrame.new(characterRoot.Position + characterRoot.CFrame.LookVector * 5
        + Vector3.new(0, 1.5, 0))
    local value = Instance.new("CFrameValue")
    value.Value = original
    local connection = value.Changed:Connect(function(cf)
        if validFieldEgg(model) then pcall(function() model:PivotTo(cf) end) end
    end)
    local tween = TweenService:Create(value, TweenInfo.new(0.55, Enum.EasingStyle.Quart,
        Enum.EasingDirection.Out), { Value = destination })
    tween:Play()
    tween.Completed:Wait()
    connection:Disconnect()
    value:Destroy()
    return true, original
end

local function attemptPickup(model)
    if state.busy or not validFieldEgg(model) then return end
    state.busy = true
    local name = eggName(model)
    local uuid = eggUuid(model)
    local prompt = not uuid and pickupPrompt(model)
    if not uuid and not prompt then
        if not state.noIdWarning then
            local keys = {}
            for key in pairs(model:GetAttributes()) do keys[#keys + 1] = key end
            local data = eggData(model)
            if data then
                for _, child in ipairs(data:GetChildren()) do keys[#keys + 1] = "EggData." .. child.Name end
            end
            table.sort(keys)
            log("Egg UUID missing: " .. name .. " / fields: " .. table.concat(keys, ", "))
        end
        state.noIdWarning = true
        state.lastAttempt[model] = os.clock()
        state.busy = false
        return
    end
    state.noIdWarning = false
    state.lastAttempt[model] = os.clock()
    state.retries[model] = (state.retries[model] or 0) + 1
    state.attempts = state.attempts + 1
    updateStats()
    local moved, original
    if prompt then
        log("Prompt pickup: " .. name)
        moved, original = pullLocal(model)
        if not moved then
            state.misses = state.misses + 1
            updateStats()
            log("Could not move prompt near player: " .. name)
            state.busy = false
            return
        end
        task.wait(0.15)
    else
        log("Pickup request: " .. name)
    end
    local ok, err = pcall(function()
        if prompt then
            if type(fireproximityprompt) == "function" then
                fireproximityprompt(prompt)
            else
                prompt:InputHoldBegin()
                task.wait(prompt.HoldDuration + 0.1)
                prompt:InputHoldEnd()
            end
        else
            pickupRemote:FireServer(uuid)
        end
    end)
    if not ok then
        if moved and validFieldEgg(model) then
            pcall(function() model:PivotTo(original) end)
        end
        state.misses = state.misses + 1
        updateStats()
        log("Pickup error: " .. tostring(err))
        state.busy = false
        return
    end
    task.wait(prompt and 1.1 or 0.65)
    if not prompt and validFieldEgg(model) and state.alive and state.enabled then
        moved, original = pullLocal(model)
        if moved then
            log("Local pull: " .. name .. " / waiting for server")
            if state.alive and state.enabled and validFieldEgg(model) then
                pcall(function() pickupRemote:FireServer(uuid) end)
                task.wait(1.1)
            end
        end
    end
    if moved and validFieldEgg(model) then
        pcall(function() model:PivotTo(original) end)
    end
    if not validFieldEgg(model) then
        state.removed = state.removed + 1
        log("Egg left world: " .. name)
    else
        state.misses = state.misses + 1
        log("Still in world: " .. name .. " / server may reject distance or prompt")
        if state.retries[model] >= 3 then log("Stopped retries for this egg: " .. name) end
    end
    updateStats()
    state.busy = false
end

local function refreshLayout()
    local camera = WS.CurrentCamera
    if not camera then return end
    local viewport = camera.ViewportSize
    local density = UIS.TouchEnabled and math.clamp(math.min(viewport.X / 1000,
        viewport.Y / 650), 1, 1.45) or 1
    scale.Scale = density
    local availableX, availableY = viewport.X / density, viewport.Y / density
    local portrait = availableX < 520
    panel.Size = UDim2.fromOffset(math.max(220, math.min(portrait and 420 or 560, availableX - 20)),
        math.max(180, math.min(portrait and 580 or 430, availableY - 20)))
    if panel.Size.X.Offset < 350 then
        search.Size = UDim2.new(1, 0, 0, 34)
        allButton.Position = UDim2.fromOffset(0, 42)
        clearButton.Position = UDim2.fromOffset(70, 42)
        eggScroll.Position = UDim2.fromOffset(0, 82)
        eggScroll.Size = UDim2.new(1, 0, 1, -82)
        minLabel.Text = "MIN KG"
    else
        search.Size = UDim2.new(1, -148, 0, 34)
        allButton.Position = UDim2.new(1, -140, 0, 0)
        clearButton.Position = UDim2.new(1, -70, 0, 0)
        eggScroll.Position = UDim2.fromOffset(0, 43)
        eggScroll.Size = UDim2.new(1, 0, 1, -43)
        minLabel.Text = "MIN WEIGHT (kg)"
    end
end
refreshLayout()
if WS.CurrentCamera then
    table.insert(state.connections, WS.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(refreshLayout))
end

local dragging, dragStart, startPosition
table.insert(state.connections, header.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
    dragging, dragStart, startPosition = input, input.Position, panel.Position
    table.insert(state.connections, input.Changed:Connect(function()
        if input.UserInputState == Enum.UserInputState.End then dragging = nil end
    end))
end))
table.insert(state.connections, UIS.InputChanged:Connect(function(input)
    if not dragging or (input.UserInputType ~= Enum.UserInputType.MouseMovement and input ~= dragging) then return end
    local camera = WS.CurrentCamera
    if not camera then return end
    local viewport = camera.ViewportSize
    local delta = input.Position - dragStart
    local x = startPosition.X.Scale * viewport.X + startPosition.X.Offset + delta.X
    local y = startPosition.Y.Scale * viewport.Y + startPosition.Y.Offset + delta.Y
    local halfWidth = panel.Size.X.Offset * scale.Scale / 2
    local halfHeight = panel.Size.Y.Offset * scale.Scale / 2
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
    toggle.BackgroundColor3 = state.enabled and C.white or C.surface
    toggle.TextColor3 = state.enabled and C.black or C.white
    local selectedCount = 0
    for _ in pairs(state.selected) do selectedCount = selectedCount + 1 end
    log(state.enabled and ("Auto egg on / selected " .. selectedCount .. " / world "
        .. tostring(state.liveCount or 0)) or "Auto egg off")
end))
table.insert(state.connections, minInput.FocusLost:Connect(function()
    state.minWeight = math.max(0, tonumber(minInput.Text) or 0)
    minInput.Text = tostring(state.minWeight)
end))
table.insert(state.connections, search:GetPropertyChangedSignal("Text"):Connect(function()
    state.search = norm(search.Text)
    state.dirty = true
    renderEggs()
end))
table.insert(state.connections, allButton.Activated:Connect(function()
    for key in pairs(state.catalog) do state.selected[key] = true end
    state.dirty = true
    renderEggs()
    log("Selected all egg types")
end))
table.insert(state.connections, clearButton.Activated:Connect(function()
    state.selected = {}
    state.dirty = true
    renderEggs()
    log("Cleared egg selection")
end))
table.insert(state.connections, copyButton.Activated:Connect(function()
    local copy = setclipboard or toclipboard or set_clipboard
    if type(copy) == "function" then
        local ok = pcall(copy, table.concat(state.logs, "\n"))
        log(ok and "Log copied" or "Clipboard failed")
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

indexEggDatabase()
indexPlacedNames()
refreshWorld()
renderEggs()
log("Ready / " .. tostring(state.liveCount or 0) .. " field eggs / "
    .. (fieldFolder() and fieldFolder().Name or "none"))

task.spawn(function()
    local lastCatalog = 0
    while state.alive do
        local ok, err = pcall(function()
            refreshWorld()
            if os.clock() - lastCatalog > 12 then
                indexPlacedNames()
                lastCatalog = os.clock()
            end
            renderEggs()
            if not state.enabled or state.busy then return end
            local chosen, matched, missingUuid, belowWeight, exhausted = nil, 0, 0, 0, 0
            local folder = fieldFolder()
            for _, model in ipairs(folder and folder:GetChildren() or {}) do
                if validFieldEgg(model) and state.selected[norm(eggName(model))] then
                    matched = matched + 1
                    local weight = eggWeight(model)
                    if state.minWeight > 0 and (not weight or weight < state.minWeight) then
                        belowWeight = belowWeight + 1
                    elseif (state.retries[model] or 0) >= 3 then
                        exhausted = exhausted + 1
                    elseif not eggUuid(model) and not pickupPrompt(model) then
                        missingUuid = missingUuid + 1
                        if not state.uuidWarned[model] then
                            state.uuidWarned[model] = true
                            local fields = {}
                            for key in pairs(model:GetAttributes()) do fields[#fields + 1] = key end
                            for _, child in ipairs(model:GetChildren()) do
                                if child:IsA("ValueBase") or child:IsA("Folder") then
                                    fields[#fields + 1] = child.Name
                                end
                            end
                            table.sort(fields)
                            log("UUID missing: " .. eggName(model) .. " / fields: "
                                .. (#fields > 0 and table.concat(fields, ", ") or "none"))
                        end
                    elseif os.clock() - (state.lastAttempt[model] or -math.huge) >= 5 then
                        chosen = model
                        break
                    end
                end
            end
            if chosen then
                attemptPickup(chosen)
            elseif next(state.selected) == nil then
                state.scanStatus = "Select eggs in EGGS"
            elseif matched == 0 then
                state.scanStatus = "No selected eggs in " .. (folder and folder.Name or "world")
            elseif missingUuid > 0 then
                state.scanStatus = "Matched " .. matched .. ", no UUID or Pickup prompt: " .. missingUuid
            elseif belowWeight > 0 then
                state.scanStatus = "Matched " .. matched .. ", below/unknown weight: " .. belowWeight
            elseif exhausted > 0 then
                state.scanStatus = "Matched " .. matched .. ", retries exhausted: " .. exhausted
            else
                state.scanStatus = "Matched " .. matched .. ", waiting to retry"
            end
            if not chosen and state.scanStatus ~= state.lastScanStatus then
                state.lastScanStatus = state.scanStatus
                log(state.scanStatus)
            end
        end)
        if not ok then
            state.busy = false
            log("Loop error: " .. tostring(err):sub(1, 90))
        end
        task.wait(0.4)
    end
end)
