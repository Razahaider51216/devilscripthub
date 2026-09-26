-- VANTA Egg Collector V3: EggWorld field eggs only.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local WS = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local network = RS:WaitForChild("Packages", 10)
network = network and network:WaitForChild("Networking", 10)
if not network then warn("[VANTA V3] EggWorld networking not found"); return end

local fieldSnapshot = network:FindFirstChild("RF/EggWorld/AskFieldEggSnapshot")
local raritySnapshot = network:FindFirstChild("RF/EggWorld/AskFieldEggRarityShows")
local carryRemote = network:FindFirstChild("RF/EggWorld/AskFieldEggCarry")
if not fieldSnapshot or not carryRemote then
    warn("[VANTA V3] Field egg snapshot/carry remote not found")
    return
end

local env = type(getgenv) == "function" and getgenv() or _G
local previous = env.VANTA_EggCollectorV3_Runtime
if previous and type(previous.stop) == "function" then pcall(previous.stop) end
local runtime = { active = true, connections = {} }
env.VANTA_EggCollectorV3_Runtime = runtime

local UI = {
    bg = Color3.fromRGB(22, 24, 28), side = Color3.fromRGB(29, 32, 37),
    card = Color3.fromRGB(35, 39, 44), button = Color3.fromRGB(48, 53, 59),
    cyan = Color3.fromRGB(65, 222, 204), amber = Color3.fromRGB(255, 199, 91),
    green = Color3.fromRGB(107, 231, 150), red = Color3.fromRGB(255, 112, 122),
    text = Color3.fromRGB(255, 255, 255), muted = Color3.fromRGB(193, 201, 207),
}

local records = {}
local rarityByUid = {}
local names, nameSet, selectedNames = {}, {}, {}
local rarities, raritySet, selectedRarities = {}, {}, {}
local currentPeriod
local safeCFrame
local autoOn = false
local busy = false
local flightSpeed = 1500
local carriedUid
local lastVerdict
local pickedCount, failedCount = 0, 0
local attempted = {}
local snapshotBusy = false
local statusLabel, countLabel, safeLabel, autoButton, speedLabel, summaryLabel, listFrame
local panel, iconButton
local filterMode = "Names"
local filterButtons = {}
local rebuildFilters
local filterRebuildQueued = false

local function queueFilterRebuild()
    if filterRebuildQueued or not rebuildFilters then return end
    filterRebuildQueued = true
    task.defer(function()
        filterRebuildQueued = false
        if runtime.active and rebuildFilters then rebuildFilters() end
    end)
end

local function rootAndCharacter()
    local character = player.Character
    return character, character and character:FindFirstChild("HumanoidRootPart")
end

local function captureSafe()
    local _, root = rootAndCharacter()
    if not root then return false end
    safeCFrame = root.CFrame
    if safeLabel then
        local p = safeCFrame.Position
        safeLabel.Text = string.format("Safe Zone: %.0f, %.0f, %.0f", p.X, p.Y, p.Z)
        safeLabel.TextColor3 = UI.green
    end
    return true
end
captureSafe()

local function status(message, color)
    if statusLabel then
        statusLabel.Text = message
        statusLabel.TextColor3 = color or UI.muted
    end
    warn("[VANTA V3] " .. message)
end

local function refreshCounts()
    if countLabel then
        local loaded = 0
        for _, record in pairs(records) do
            if record.State == "Slot" then loaded = loaded + 1 end
        end
        countLabel.Text = string.format("Field eggs: %d  |  Picked: %d  |  Failed: %d", loaded, pickedCount, failedCount)
    end
    if summaryLabel then
        local nameCount, rarityCount = 0, 0
        for _, active in pairs(selectedNames) do if active then nameCount = nameCount + 1 end end
        for _, active in pairs(selectedRarities) do if active then rarityCount = rarityCount + 1 end end
        summaryLabel.Text = string.format("Selected: %d names | %d rarities", nameCount, rarityCount)
        summaryLabel.TextColor3 = (nameCount + rarityCount > 0) and UI.muted or UI.amber
    end
end

local function addName(name)
    if type(name) ~= "string" or name == "" or nameSet[name] then return false end
    nameSet[name] = true
    selectedNames[name] = false
    table.insert(names, name)
    table.sort(names)
    return true
end

local function addRarity(rarity)
    if type(rarity) ~= "string" or rarity == "" or raritySet[rarity] then return false end
    raritySet[rarity] = true
    selectedRarities[rarity] = false
    table.insert(rarities, rarity)
    table.sort(rarities)
    return true
end

local function validRecord(record)
    if type(record) ~= "table" or type(record.Uid) ~= "string" or type(record.AssetCategory) ~= "string" then return false end
    if record.State ~= "Slot" then return false end
    local position = record.BottomCFrame or record.BoundsCFrame
    return typeof(position) == "CFrame" or typeof(position) == "Vector3"
end

local function positionOf(record)
    local value = record.BottomCFrame or record.BoundsCFrame
    return typeof(value) == "CFrame" and value.Position or value
end

local function applyRarityShows(data)
    if type(data) ~= "table" then return end
    if data.PeriodIndex and data.PeriodIndex ~= currentPeriod then
        currentPeriod = data.PeriodIndex
        table.clear(rarityByUid)
    end
    local changed = false
    for _, item in ipairs(type(data.RareSpawns) == "table" and data.RareSpawns or {}) do
        if type(item) == "table" and type(item.EggUid) == "string" and type(item.RarityId) == "string" then
            rarityByUid[item.EggUid] = item.RarityId
            changed = addRarity(item.RarityId) or changed
        end
    end
    if changed then queueFilterRebuild() end
end

local function applyRecord(record)
    if type(record) ~= "table" or type(record.Uid) ~= "string" then return end
    records[record.Uid] = record
    if addName(record.AssetCategory) then queueFilterRebuild() end
    refreshCounts()
end

local function refreshSnapshot()
    if snapshotBusy or not runtime.active then return end
    snapshotBusy = true
    local ok, result = pcall(function() return fieldSnapshot:InvokeServer() end)
    snapshotBusy = false
    if ok and type(result) == "table" and type(result.Records) == "table" then
        local nextRecords = {}
        local changed = false
        for _, record in pairs(result.Records) do
            if type(record) == "table" and type(record.Uid) == "string" then
                nextRecords[record.Uid] = record
                changed = addName(record.AssetCategory) or changed
            end
        end
        records = nextRecords
        if changed then queueFilterRebuild() end
        refreshCounts()
    elseif not ok then
        status("Field egg snapshot failed", UI.red)
    end
    if raritySnapshot then
        local rarityOk, first, second = pcall(function() return raritySnapshot:InvokeServer() end)
        if rarityOk then applyRarityShows(type(second) == "table" and second or first) end
    end
end

local function hasSelection()
    for _, active in pairs(selectedNames) do if active then return true end end
    for _, active in pairs(selectedRarities) do if active then return true end end
    return false
end

local function categoryMatch(selection, key)
    local any = false
    for _, active in pairs(selection) do if active then any = true break end end
    return not any or selection[key] == true
end

local function targetMatches(record)
    return validRecord(record) and hasSelection()
        and categoryMatch(selectedNames, record.AssetCategory)
        and categoryMatch(selectedRarities, rarityByUid[record.Uid])
end

local function bestTarget()
    local _, root = rootAndCharacter()
    if not root then return nil end
    local best, distance
    for _, record in pairs(records) do
        if targetMatches(record) and (not attempted[record.Uid] or os.clock() - attempted[record.Uid] > 12) then
            local d = (positionOf(record) - root.Position).Magnitude
            if not distance or d < distance then best, distance = record, d end
        end
    end
    return best
end

local function flySegment(destination, uid)
    while runtime.active do
        local character, root = rootAndCharacter()
        if not character or not root then return false end
        if uid and not targetMatches(records[uid]) then return false end
        local displacement = destination - root.Position
        local distance = displacement.Magnitude
        if distance < 2 then return true end
        local dt = math.min(RunService.Heartbeat:Wait(), 0.1)
        local step = math.min(distance, flightSpeed * dt)
        local nextPosition = root.Position + displacement.Unit * step
        character:PivotTo(CFrame.new(nextPosition) * root.CFrame.Rotation)
        root.AssemblyLinearVelocity = Vector3.zero
    end
    return false
end

local function flyTo(destination, uid)
    local _, root = rootAndCharacter()
    if not root then return false end
    local altitude = math.max(root.Position.Y, destination.Y) + 35
    if not flySegment(Vector3.new(root.Position.X, altitude, root.Position.Z), uid) then return false end
    if not flySegment(Vector3.new(destination.X, altitude, destination.Z), uid) then return false end
    return flySegment(destination, uid)
end

local function returnSafe()
    if not safeCFrame then return false end
    local ok = flyTo(safeCFrame.Position, nil)
    if ok then
        local character = player.Character
        if character then character:PivotTo(safeCFrame) end
    end
    return ok
end

local function collect(record)
    if busy or not runtime.active or not targetMatches(record) then return false end
    if carriedUid then status("Already carrying an egg", UI.amber); return false end
    if not safeCFrame and not captureSafe() then status("Set Safe Zone first", UI.red); return false end
    busy = true
    local uid, name = record.Uid, record.AssetCategory
    attempted[uid] = os.clock()
    status("Flying to " .. name, UI.cyan)
    local reached = flyTo(positionOf(record) + Vector3.new(0, 3, 0), uid)
    if not reached or not targetMatches(records[uid]) then
        status("Egg moved or was taken: " .. name, UI.amber)
        returnSafe()
        busy = false
        return false
    end

    task.wait(0.15)
    if not runtime.active or not targetMatches(records[uid]) then
        returnSafe()
        busy = false
        return false
    end
    status("Picking up " .. name, UI.cyan)
    lastVerdict = nil
    local ok, accepted = pcall(function() return carryRemote:InvokeServer({ Uid = uid }) end)
    local deadline = os.clock() + 1.5
    while runtime.active and carriedUid ~= uid and os.clock() < deadline do task.wait(0.05) end
    local picked = ok and accepted == true and carriedUid == uid
    if picked then
        status("Carrying " .. name .. "; returning safe", UI.green)
    else
        failedCount = failedCount + 1
        status("Pickup not confirmed: " .. name, UI.red)
        warn("[VANTA V3] Carry result:", ok, accepted, uid)
    end
    refreshCounts()
    local returned = returnSafe()
    if picked then
        local verdictDeadline = os.clock() + 2
        while runtime.active and carriedUid == uid and os.clock() < verdictDeadline do task.wait(0.1) end
        if type(lastVerdict) == "table" and returned then
            pickedCount = pickedCount + 1
            status("Redeemed: " .. tostring(lastVerdict.Rarity or "") .. " " .. tostring(lastVerdict.DisplayName or name), UI.green)
        elseif carriedUid == uid then
            status(returned and "At Safe Zone; egg still carried" or "Return flight stopped; egg still carried", UI.amber)
        else
            failedCount = failedCount + 1
            status("Carry ended without redemption confirmation", UI.red)
        end
    end
    refreshCounts()
    busy = false
    return picked
end

local function connectEvent(name, handler)
    local remote = network:FindFirstChild(name)
    if remote and remote:IsA("RemoteEvent") then
        table.insert(runtime.connections, remote.OnClientEvent:Connect(handler))
    end
end

connectEvent("RE/EggWorld/FieldEggShifted", applyRecord)
connectEvent("RE/EggWorld/FieldEggBatchShifted", function(batch)
    if type(batch) ~= "table" then return end
    for _, uid in ipairs(type(batch.RemovedUids) == "table" and batch.RemovedUids or {}) do records[uid] = nil end
    for _, record in ipairs(type(batch.UpdatedRecords) == "table" and batch.UpdatedRecords or {}) do applyRecord(record) end
    refreshCounts()
    task.defer(refreshSnapshot)
end)
connectEvent("RE/EggWorld/FieldEggGone", function(uid)
    if type(uid) == "string" then records[uid] = nil; refreshCounts() end
end)
connectEvent("RE/EggWorld/FieldEggRaritiesShown", applyRarityShows)
connectEvent("RE/EggWorld/FieldEggCarry", function(info)
    if type(info) ~= "table" then return end
    carriedUid = info.IsCarrying and info.Uid or nil
end)
connectEvent("RE/EggWorld/FieldEggRedeemVerdict", function(info)
    lastVerdict = info
end)

local oldGui = playerGui:FindFirstChild("VANTA_EggCollectorV3")
if oldGui then oldGui:Destroy() end
local screen = Instance.new("ScreenGui")
screen.Name = "VANTA_EggCollectorV3"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.DisplayOrder = 200
screen.Parent = playerGui

runtime.stop = function()
    if not runtime.active then return end
    runtime.active = false
    autoOn = false
    for _, connection in ipairs(runtime.connections) do connection:Disconnect() end
    if screen.Parent then screen:Destroy() end
end

local function round(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = parent
end

local function button(parent, text, x, y, width, callback)
    local item = Instance.new("TextButton")
    item.Size = UDim2.fromOffset(width, 34)
    item.Position = UDim2.fromOffset(x, y)
    item.BackgroundColor3 = UI.button
    item.BorderSizePixel = 0
    item.Text = text
    item.TextColor3 = UI.text
    item.Font = Enum.Font.GothamBold
    item.TextSize = 11
    item.Parent = parent
    round(item, 6)
    if callback then item.Activated:Connect(callback) end
    return item
end

local function label(parent, text, x, y, width, height, size, color)
    local item = Instance.new("TextLabel")
    item.Size = UDim2.fromOffset(width, height)
    item.Position = UDim2.fromOffset(x, y)
    item.BackgroundTransparency = 1
    item.Text = text
    item.TextColor3 = color or UI.muted
    item.Font = Enum.Font.Gotham
    item.TextSize = size or 12
    item.TextWrapped = true
    item.TextXAlignment = Enum.TextXAlignment.Left
    item.TextYAlignment = Enum.TextYAlignment.Top
    item.Parent = parent
    return item
end

panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(560, 410)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.BackgroundColor3 = UI.bg
panel.BorderSizePixel = 0
panel.Active = true
panel.Parent = screen
round(panel, 8)
local outline = Instance.new("UIStroke")
outline.Color = UI.cyan
outline.Thickness = 1.4
outline.Parent = panel
local scale = Instance.new("UIScale")
scale.Parent = panel
local function fitPanel()
    local camera = WS.CurrentCamera
    if camera then
        local view = camera.ViewportSize
        scale.Scale = math.max(0.1, math.min(1, (view.X - 24) / 560, (view.Y - 24) / 410))
    end
end
local viewConnection
local function watchCamera()
    if viewConnection then viewConnection:Disconnect() end
    local camera = WS.CurrentCamera
    if camera then
        viewConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(fitPanel)
        table.insert(runtime.connections, viewConnection)
    end
    fitPanel()
end
table.insert(runtime.connections, WS:GetPropertyChangedSignal("CurrentCamera"):Connect(watchCamera))
watchCamera()

local top = Instance.new("Frame")
top.Size = UDim2.new(1, 0, 0, 44)
top.BackgroundColor3 = UI.button
top.BorderSizePixel = 0
top.Parent = panel
round(top, 8)
label(top, "VANTA EGG COLLECTOR V3", 14, 12, 420, 22, 13, UI.text).Font = Enum.Font.GothamBlack
button(top, "X", 520, 5, 30, function() panel.Visible = false end)

local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, 142, 1, -58)
sidebar.Position = UDim2.fromOffset(12, 52)
sidebar.BackgroundColor3 = UI.side
sidebar.BorderSizePixel = 0
sidebar.Parent = panel
round(sidebar, 8)
local content = Instance.new("Frame")
content.Size = UDim2.new(1, -172, 1, -58)
content.Position = UDim2.fromOffset(164, 52)
content.BackgroundColor3 = UI.card
content.BorderSizePixel = 0
content.Parent = panel
round(content, 8)

local sections, navButtons = {}, {}
local function section(name)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, -24, 1, -20)
    frame.Position = UDim2.fromOffset(12, 10)
    frame.BackgroundTransparency = 1
    frame.Visible = false
    frame.Parent = content
    sections[name] = frame
    return frame
end
local collector = section("Collector")
local filters = section("Filters")
local safe = section("Safe Zone")
local function showSection(name)
    for key, frame in pairs(sections) do frame.Visible = key == name end
    for key, item in pairs(navButtons) do
        item.BackgroundColor3 = key == name and Color3.fromRGB(44, 101, 94) or UI.card
    end
end
for i, name in ipairs({ "Collector", "Filters", "Safe Zone" }) do
    local tab = button(sidebar, name, 8, 10 + (i - 1) * 42, 126, function() showSection(name) end)
    navButtons[name] = tab
end

label(collector, "Auto Collector", 0, 0, 340, 25, 14, UI.text).Font = Enum.Font.GothamBlack
statusLabel = label(collector, "Loading field eggs...", 0, 35, 338, 50, 11, UI.muted)
countLabel = label(collector, "Field eggs: 0  |  Picked: 0  |  Failed: 0", 0, 89, 338, 22, 11, UI.text)
autoButton = button(collector, "AUTO COLLECT: OFF", 0, 123, 158, function()
    autoOn = not autoOn
    autoButton.Text = autoOn and "AUTO COLLECT: ON" or "AUTO COLLECT: OFF"
    autoButton.BackgroundColor3 = autoOn and Color3.fromRGB(44, 101, 94) or UI.button
    status(autoOn and (hasSelection() and "Auto collector running" or "Select a name or rarity") or "Auto collector stopped", autoOn and UI.green or UI.muted)
end)
button(collector, "COLLECT ONCE", 170, 123, 158, function()
    if busy then return end
    task.spawn(function()
        refreshSnapshot()
        local target = bestTarget()
        if target then collect(target) else status("No fresh matching field egg", UI.amber) end
    end)
end)
label(collector, "Flight Speed", 0, 180, 230, 20, 11, UI.muted)
speedLabel = label(collector, tostring(flightSpeed) .. " studs/s", 240, 180, 88, 20, 11, UI.cyan)
button(collector, "-", 0, 208, 46, function()
    flightSpeed = math.max(600, flightSpeed - 300)
    speedLabel.Text = tostring(flightSpeed) .. " studs/s"
end)
button(collector, "+", 56, 208, 46, function()
    flightSpeed = math.min(3000, flightSpeed + 300)
    speedLabel.Text = tostring(flightSpeed) .. " studs/s"
end)
button(collector, "RESCAN", 170, 208, 158, function()
    task.spawn(refreshSnapshot)
end)

label(filters, "Egg Filters", 0, 0, 340, 25, 14, UI.text).Font = Enum.Font.GothamBlack
label(filters, "Names and rarities must both match when selected", 0, 25, 340, 18, 11, UI.muted)
summaryLabel = label(filters, "Selected: 0 names | 0 rarities", 0, 81, 340, 24, 11, UI.amber)
listFrame = Instance.new("ScrollingFrame")
listFrame.Size = UDim2.fromOffset(338, 163)
listFrame.Position = UDim2.fromOffset(0, 113)
listFrame.BackgroundTransparency = 1
listFrame.BorderSizePixel = 0
listFrame.ScrollBarThickness = 4
listFrame.ScrollingDirection = Enum.ScrollingDirection.Y
listFrame.CanvasSize = UDim2.fromOffset(0, 0)
listFrame.Parent = filters
local itemButtons = {}
rebuildFilters = function()
    for _, item in ipairs(itemButtons) do item:Destroy() end
    table.clear(itemButtons)
    local options = filterMode == "Names" and names or rarities
    local selected = filterMode == "Names" and selectedNames or selectedRarities
    for i, value in ipairs(options) do
        local item = button(listFrame, (selected[value] and "[ON]  " or "[OFF]  ") .. value, 0, (i - 1) * 37, 320, function()
            selected[value] = not selected[value]
            rebuildFilters()
        end)
        item.TextXAlignment = Enum.TextXAlignment.Left
        item.TextTruncate = Enum.TextTruncate.AtEnd
        item.BackgroundColor3 = selected[value] and Color3.fromRGB(44, 101, 94) or UI.button
        table.insert(itemButtons, item)
    end
    listFrame.CanvasSize = UDim2.fromOffset(0, math.max(163, #options * 37))
    for mode, item in pairs(filterButtons) do
        item.BackgroundColor3 = mode == filterMode and Color3.fromRGB(44, 101, 94) or UI.button
    end
    refreshCounts()
end
for i, mode in ipairs({ "Names", "Rarities" }) do
    filterButtons[mode] = button(filters, mode, (i - 1) * 170, 48, 158, function()
        filterMode = mode
        listFrame.CanvasPosition = Vector2.zero
        rebuildFilters()
    end)
end
button(filters, "ALL", 0, 286, 88, function()
    local options = filterMode == "Names" and names or rarities
    local selected = filterMode == "Names" and selectedNames or selectedRarities
    for _, value in ipairs(options) do selected[value] = true end
    rebuildFilters()
end)
button(filters, "CLEAR", 238, 286, 88, function()
    local options = filterMode == "Names" and names or rarities
    local selected = filterMode == "Names" and selectedNames or selectedRarities
    for _, value in ipairs(options) do selected[value] = false end
    rebuildFilters()
end)

label(safe, "Safe Zone", 0, 0, 340, 25, 14, UI.text).Font = Enum.Font.GothamBlack
safeLabel = label(safe, "Safe Zone: not set", 0, 42, 338, 28, 12, UI.red)
button(safe, "SET SAFE HERE", 0, 91, 158, function()
    local saved = captureSafe()
    status(saved and "Safe Zone saved" or "Character not ready", saved and UI.green or UI.red)
end)
button(safe, "RETURN SAFE", 170, 91, 158, function()
    if busy then return end
    task.spawn(function()
        busy = true
        local returned = returnSafe()
        status(returned and "Returned to Safe Zone" or "Return to Safe Zone failed", returned and UI.green or UI.red)
        busy = false
    end)
end)
if safeCFrame then
    local p = safeCFrame.Position
    safeLabel.Text = string.format("Safe Zone: %.0f, %.0f, %.0f", p.X, p.Y, p.Z)
    safeLabel.TextColor3 = UI.green
end

iconButton = button(screen, "V3", 16, 90, 44, function()
    panel.Visible = not panel.Visible
end)
iconButton.BackgroundColor3 = UI.bg

local function draggable(handle, target)
    local dragging, startInput, startPosition = false, nil, nil
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            startInput = input.Position
            startPosition = target.Position
        end
    end)
    handle.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
    table.insert(runtime.connections, UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - startInput
            target.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X,
                startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
        end
    end))
end
draggable(top, panel)
draggable(iconButton, iconButton)

showSection("Collector")
rebuildFilters()
task.spawn(function()
    refreshSnapshot()
    status("Select an egg name or announced rarity", UI.muted)
    local lastRefresh = os.clock()
    while runtime.active do
        if not busy then
            if os.clock() - lastRefresh >= 4 then
                refreshSnapshot()
                lastRefresh = os.clock()
            end
            if autoOn and hasSelection() and not carriedUid then
                local target = bestTarget()
                if target then collect(target) end
            end
        end
        task.wait(0.3)
    end
end)

warn("[VANTA V3] GUI ready. Set Safe Zone at your base, select filters, then enable Auto Collect.")
