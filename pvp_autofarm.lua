-- Quest-aware PvE farm for PlaceId 99046552174353. Starts paused.
-- Only targets Workspace.Enemies; never targets player characters or buys unlocks.

if game.PlaceId ~= 99046552174353 then warn("[PvPFarm] Wrong place"); return end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local WS = game:GetService("Workspace")
local UIS = game:GetService("UserInputService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local services = RS:WaitForChild("Packages"):WaitForChild("Knit"):WaitForChild("Services")
local questData = require(RS:WaitForChild("Database"):WaitForChild("QuestInfo"):WaitForChild("KillQuestRepeatables"))
local zoneData = require(RS.Database:WaitForChild("Zones")).ZoneData
local enemies = WS:WaitForChild("Enemies")
local islands = WS:FindFirstChild("_Map") and WS._Map:FindFirstChild("Islands")

local function remote(service, name)
    return services:WaitForChild(service):WaitForChild("RF"):WaitForChild(name)
end

local rf = {
    getQuests = remote("QuestService", "GetQuests"),
    getZones = remote("ZoneHandler", "GetZones"),
    availability = remote("QuestService", "GetQuestAvailability"),
    talk = remote("QuestService", "TalkToNPC"),
    accept = remote("QuestService", "AcceptQuest"),
    complete = remote("QuestService", "CompleteQuest"),
    registerAttack = remote("CombatService", "RegisterAttack"),
    weaponDamage = remote("CombatService", "WeaponDamage"),
}

local env = type(getgenv) == "function" and getgenv() or _G
if env.VANTA_PvPFarm and type(env.VANTA_PvPFarm.stop) == "function" then pcall(env.VANTA_PvPFarm.stop) end
local state = {
    alive = true, combat = false, quests = false, mode = "Direct", selected = nil,
    lastQuestAction = 0, lastZoneMove = 0, travelUntil = 0, lastRefresh = 0, combo = 1, rejectedHits = 0,
    questStates = {}, connections = {}, currentTarget = nil,
    availabilityCache = {}, rejectedQuests = {}, questBlocked = false, zoneProgress = {},
}
env.VANTA_PvPFarm = state

local function invoke(target, ...)
    local ok, result = pcall(function(...) return target:InvokeServer(...) end, ...)
    return ok, result
end

local function level()
    local stats = player:FindFirstChild("Leaderstats") or player:FindFirstChild("leaderstats")
    local value = stats and stats:FindFirstChild("Level")
    return value and tonumber(value.Value) or 0
end

local function root()
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return nil end
    return character:FindFirstChild("HumanoidRootPart")
end

local function modelPosition(model)
    if model:IsA("BasePart") then return model.Position end
    if model:IsA("Attachment") then return model.WorldPosition end
    local part = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
    if part then return part.Position end
    local ok, cf = pcall(function() return model:GetPivot() end)
    return ok and cf.Position or nil
end

local function livingEnemy(model, allowBoss)
    if not model or model.Parent ~= enemies or not model:IsA("Model") then return false end
    if model:GetAttribute("IsBoss") and not allowBoss then return false end
    local humanoid = model:FindFirstChildOfClass("Humanoid")
    return humanoid ~= nil and humanoid.Health > 0
end

local function nearestEnemy(enemyType)
    local characterRoot = root()
    local origin = characterRoot and characterRoot.Position
    local chosen, distance
    for _, model in ipairs(enemies:GetChildren()) do
        if livingEnemy(model, enemyType ~= nil) and (not enemyType or model.Name == enemyType) then
            local mobLevel = tonumber(model:GetAttribute("Level")) or 0
            if mobLevel <= level() + 25 then
                local position = modelPosition(model)
                if position then
                    local d = origin and (position - origin).Magnitude or 0
                    if not chosen or d < distance then chosen, distance = model, d end
                end
            end
        end
    end
    return chosen
end

local function findNpc(id)
    if islands then
        local inst = islands:FindFirstChild(id, true)
        if inst and inst:IsA("Model") then return inst end
    end
    local inst = WS:FindFirstChild(id)
    return inst and inst:IsA("Model") and inst or nil
end

local function islandOf(inst)
    while inst and inst.Parent do
        if inst.Parent == islands then return inst.Name end
        inst = inst.Parent
    end
    return nil
end

local function activeKillQuest()
    for id, info in pairs(state.questStates) do
        local config = questData[id]
        if info.Ongoing and config and config.EnemyType then return id, config, info end
    end
    return nil
end

local function questAvailable(id)
    local cached = state.availabilityCache[id]
    if cached and os.clock() - cached.at < 5 then return cached.available end
    local ok, result = invoke(rf.availability, id)
    local available = ok and type(result) == "table" and result.Available == true
    state.availabilityCache[id] = { at = os.clock(), available = available,
        reason = type(result) == "table" and result.Reason or tostring(result) }
    return available
end

local function questForEnemy(zoneName, enemyType)
    local baseIsland = zoneName:match("^(Island%d+)")
    for id, config in pairs(questData) do
        if type(config) == "table" and config.EnemyType == enemyType then
            local npc = findNpc(id)
            local npcIsland = id:match("^(Island%d+)") or islandOf(npc)
            if npcIsland == baseIsland then
                return { id = id, config = config, npc = npc }
            end
        end
    end
    return nil
end

local function selectFarmPlan()
    local best
    local playerLevel = level()
    for zoneName, zone in pairs(zoneData) do
        if type(zoneName) == "string" and zoneName:match("^Island%d+") and type(zone) == "table"
            and type(zone.CustomEnemiesBySpawnName) == "table"
            and type(zone.CustomLevelBySpawnName) == "table" then
            for spawnName, enemyNames in pairs(zone.CustomEnemiesBySpawnName) do
                local levelData = zone.CustomLevelBySpawnName[spawnName]
                local mobLevel = levelData and tonumber(levelData.Min)
                if mobLevel and mobLevel <= playerLevel + 25 and type(enemyNames) == "table" then
                    for _, enemyType in ipairs(enemyNames) do
                        local quest = questForEnemy(zoneName, enemyType)
                        if not best or mobLevel > best.mobLevel
                            or (mobLevel == best.mobLevel and quest and not best.quest) then
                            best = { zone = zoneName, enemyType = enemyType, mobLevel = mobLevel,
                                quest = quest }
                        end
                    end
                end
            end
        end
    end
    return best
end

local function requiredKills(config)
    local first = config.Quests and config.Quests[1]
    if type(first) ~= "table" or type(first.Requirement) ~= "table" then return nil end
    for _, requirement in pairs(first.Requirement) do
        if type(requirement) == "table" then
            local stat = tostring(requirement.Stat or "")
            local kind = tostring(requirement.Type or "")
            if stat:find(config.EnemyType, 1, true) or kind == "EnemyKill" then
                return tonumber(requirement.Required)
            end
        end
    end
    return nil
end

local function killProgress(info, enemyType)
    local progress = info and info.Progress
    if type(progress) ~= "table" then return 0 end
    return tonumber(progress["EnemyKill_" .. enemyType]) or 0
end

local function moveNear(position, distance)
    local characterRoot = root()
    if not characterRoot or not position then return false end
    if (characterRoot.Position - position).Magnitude <= distance then
        if (characterRoot.Position - position).Magnitude > 0.1 then
            characterRoot.CFrame = CFrame.lookAt(characterRoot.Position, position)
        end
        return true
    end
    local offset = characterRoot.Position - position
    if offset.Magnitude < 0.1 then offset = Vector3.new(0, 0, 1) end
    local destination = position + offset.Unit * math.max(4, distance - 1) + Vector3.new(0, 2, 0)
    characterRoot.CFrame = CFrame.lookAt(destination, position)
    characterRoot.AssemblyLinearVelocity = Vector3.zero
    return (characterRoot.Position - position).Magnitude <= distance + 4
end

local function travelToPlan(plan)
    local baseIsland = plan.zone:match("^(Island%d+)")
    local island = baseIsland and islands and islands:FindFirstChild(baseIsland)
    local waypoint = island and island:FindFirstChild("Waypoint_" .. baseIsland)
    local anchor = waypoint and (waypoint:FindFirstChild("Teleport", true)
        or waypoint:FindFirstChild("TeleporterPurchasePart", true))
    local anchorPosition = anchor and modelPosition(anchor)
    local characterRoot = root()
    if not anchorPosition or not characterRoot
        or (characterRoot.Position - anchorPosition).Magnitude < 400
        or os.clock() - state.lastZoneMove < 8 then return false end
    state.lastZoneMove = os.clock()
    if moveNear(anchorPosition, 8) then
        state.travelUntil = os.clock() + 3
        return true
    end
    return false
end

local gui = Instance.new("ScreenGui")
gui.Name = "ValenHub"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 110
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(548, 344)
panel.BackgroundColor3 = Color3.fromRGB(42, 43, 46)
panel.BorderSizePixel = 0
panel.Parent = gui
local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 8)
panelCorner.Parent = panel
local border = Instance.new("UIStroke")
border.Color = Color3.fromRGB(104, 130, 127)
border.Thickness = 1
border.Parent = panel
local scale = Instance.new("UIScale")
scale.Parent = panel
local function fitPanel()
    local camera = WS.CurrentCamera
    if camera then
        local size = camera.ViewportSize
        scale.Scale = math.clamp(math.min((size.X - 24) / 548, (size.Y - 24) / 344), 0.35, 1)
    end
end
fitPanel()
if WS.CurrentCamera then
    table.insert(state.connections, WS.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitPanel))
end

local dock = Instance.new("TextButton")
dock.Name = "OpenHub"
dock.Position = UDim2.fromOffset(16, 140)
dock.Size = UDim2.fromOffset(44, 44)
dock.BackgroundColor3 = Color3.fromRGB(157, 91, 69)
dock.TextColor3 = Color3.fromRGB(255, 255, 255)
dock.Font = Enum.Font.GothamBold
dock.TextSize = 18
dock.Text = "V"
dock.Visible = false
dock.Parent = gui
local dockCorner = Instance.new("UICorner")
dockCorner.CornerRadius = UDim.new(0, 8)
dockCorner.Parent = dock

local function label(parent, name, caption, x, y, width, height, color)
    local item = Instance.new("TextLabel")
    item.Name = name
    item.Position = UDim2.fromOffset(x, y)
    item.Size = UDim2.fromOffset(width, height)
    item.BackgroundTransparency = 1
    item.Font = Enum.Font.GothamMedium
    item.TextSize = 14
    item.TextXAlignment = Enum.TextXAlignment.Left
    item.TextTruncate = Enum.TextTruncate.AtEnd
    item.TextColor3 = color or Color3.fromRGB(237, 243, 243)
    item.Text = caption
    item.Parent = parent
    return item
end

local function button(parent, name, caption, x, y, width, height)
    local item = Instance.new("TextButton")
    item.Name = name
    item.Position = UDim2.fromOffset(x, y)
    item.Size = UDim2.fromOffset(width, height)
    item.BackgroundColor3 = Color3.fromRGB(60, 72, 80)
    item.BorderSizePixel = 0
    item.Font = Enum.Font.GothamBold
    item.TextSize = 13
    item.TextColor3 = Color3.fromRGB(245, 249, 248)
    item.Text = caption
    item.Parent = parent
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = item
    return item
end

local header = label(panel, "Header", "VALEN HUB", 16, 8, 450, 26)
header.TextSize = 17
header.Font = Enum.Font.GothamBold
header.Active = true
local closeButton = button(panel, "Close", "X", 508, 7, 28, 28)
closeButton.BackgroundColor3 = Color3.fromRGB(128, 70, 68)

local sidebar = Instance.new("Frame")
sidebar.Name = "Navigation"
sidebar.Position = UDim2.fromOffset(0, 42)
sidebar.Size = UDim2.fromOffset(137, 302)
sidebar.BackgroundColor3 = Color3.fromRGB(33, 35, 37)
sidebar.BorderSizePixel = 0
sidebar.Parent = panel
local content = Instance.new("Frame")
content.Name = "Content"
content.Position = UDim2.fromOffset(137, 42)
content.Size = UDim2.fromOffset(411, 302)
content.BackgroundTransparency = 1
content.Parent = panel

local pages, tabs = {}, {}
for index, name in ipairs({ "Farm", "Quests", "Travel", "Live" }) do
    local page = Instance.new("Frame")
    page.Name = name
    page.Size = UDim2.fromScale(1, 1)
    page.BackgroundTransparency = 1
    page.Visible = index == 1
    page.Parent = content
    pages[name] = page
    local tab = button(sidebar, name .. "Tab", name, 10, 12 + (index - 1) * 47, 117, 38)
    tab.TextXAlignment = Enum.TextXAlignment.Left
    tab.TextSize = 14
    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, 12)
    padding.Parent = tab
    tabs[name] = tab
end
local function showPage(name)
    for key, page in pairs(pages) do
        page.Visible = key == name
        tabs[key].BackgroundColor3 = key == name and Color3.fromRGB(43, 118, 111)
            or Color3.fromRGB(48, 58, 65)
    end
end
for name, tab in pairs(tabs) do
    table.insert(state.connections, tab.Activated:Connect(function() showPage(name) end))
end
showPage("Farm")

local farmPage = pages.Farm
label(farmPage, "FarmTitle", "AUTO FARM", 16, 14, 365, 26).TextSize = 18
local status = label(farmPage, "Status", "Paused", 16, 50, 368, 48, Color3.fromRGB(117, 225, 194))
status.TextWrapped = true
status.TextTruncate = Enum.TextTruncate.None
local questLabel = label(farmPage, "Quest", "Quest: none", 16, 106, 368, 22)
local targetLabel = label(farmPage, "Target", "Target: none", 16, 134, 368, 22)
local combatButton = button(farmPage, "CombatToggle", "COMBAT: OFF", 16, 182, 177, 38)
local questButton = button(farmPage, "QuestToggle", "QUESTS: OFF", 206, 182, 177, 38)
local modeButton = button(farmPage, "Mode", "ATTACK: DIRECT", 16, 230, 367, 38)
modeButton.BackgroundColor3 = Color3.fromRGB(137, 87, 66)

local questPage = pages.Quests
label(questPage, "QuestTitle", "QUESTS", 16, 14, 365, 26).TextSize = 18
local questScroll = Instance.new("ScrollingFrame")
questScroll.Name = "QuestList"
questScroll.Position = UDim2.fromOffset(16, 50)
questScroll.Size = UDim2.fromOffset(374, 238)
questScroll.BackgroundTransparency = 1
questScroll.BorderSizePixel = 0
questScroll.ScrollBarThickness = 4
questScroll.ScrollBarImageColor3 = Color3.fromRGB(97, 170, 162)
questScroll.Parent = questPage
local questText = label(questScroll, "QuestText", "Loading...", 0, 0, 352, 220)
questText.TextWrapped = true
questText.TextTruncate = Enum.TextTruncate.None
questText.TextYAlignment = Enum.TextYAlignment.Top

local travelPage = pages.Travel
label(travelPage, "TravelTitle", "TRAVEL", 16, 14, 265, 26).TextSize = 18
local refreshTravelButton = button(travelPage, "RefreshTravel", "REFRESH", 290, 12, 99, 30)
local travelScroll = Instance.new("ScrollingFrame")
travelScroll.Name = "Waypoints"
travelScroll.Position = UDim2.fromOffset(16, 50)
travelScroll.Size = UDim2.fromOffset(374, 238)
travelScroll.BackgroundTransparency = 1
travelScroll.BorderSizePixel = 0
travelScroll.ScrollBarThickness = 4
travelScroll.ScrollBarImageColor3 = Color3.fromRGB(97, 170, 162)
travelScroll.CanvasSize = UDim2.fromOffset(0, 442)
travelScroll.Parent = travelPage

local livePage = pages.Live
label(livePage, "LiveTitle", "LIVE STATUS", 16, 14, 365, 26).TextSize = 18
local levelLabel = label(livePage, "Level", "Level: ...", 16, 58, 370, 25)
local enemiesLabel = label(livePage, "Enemies", "Loaded enemies: ...", 16, 94, 370, 25)
local waypointLabel = label(livePage, "Waypoints", "Waypoints: ...", 16, 130, 370, 25)
local storyLabel = label(livePage, "Story", "Story quest: ...", 16, 166, 370, 50)
storyLabel.TextWrapped = true
storyLabel.TextTruncate = Enum.TextTruncate.None

local function setStatus(message)
    if state.alive then status.Text = message end
end

local function refreshUi()
    combatButton.Text = state.combat and "COMBAT: ON" or "COMBAT: OFF"
    questButton.Text = state.quests and "QUESTS: ON" or "QUESTS: OFF"
    combatButton.BackgroundColor3 = state.combat and Color3.fromRGB(42, 125, 102) or Color3.fromRGB(60, 72, 80)
    questButton.BackgroundColor3 = state.quests and Color3.fromRGB(42, 125, 102) or Color3.fromRGB(60, 72, 80)
    modeButton.Text = "ATTACK: " .. string.upper(state.mode)
end

table.insert(state.connections, combatButton.Activated:Connect(function()
    state.combat = not state.combat
    state.rejectedHits = 0
    setStatus(state.combat and "Scanning enemies" or "Combat paused")
    refreshUi()
end))
table.insert(state.connections, questButton.Activated:Connect(function()
    state.quests = not state.quests
    setStatus(state.quests and "Scanning repeatable quests" or "Quest automation paused")
    refreshUi()
end))
table.insert(state.connections, modeButton.Activated:Connect(function()
    state.mode = state.mode == "Direct" and "Input" or "Direct"
    state.rejectedHits = 0
    refreshUi()
end))
table.insert(state.connections, closeButton.Activated:Connect(function()
    panel.Visible = false
    dock.Visible = true
end))
table.insert(state.connections, dock.Activated:Connect(function()
    panel.Visible = true
    dock.Visible = false
end))

local dragging, dragStart, panelStart
table.insert(state.connections, header.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
    dragging, dragStart, panelStart = input, input.Position, panel.Position
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
    local x = panelStart.X.Scale * viewport.X + panelStart.X.Offset + delta.X
    local y = panelStart.Y.Scale * viewport.Y + panelStart.Y.Offset + delta.Y
    panel.Position = UDim2.fromOffset(math.clamp(x, 70, viewport.X - 70),
        math.clamp(y, 24, viewport.Y - 24))
end))

local travelRows = {}
for index = 1, 11 do
    local islandName = "Island" .. index
    local zone = zoneData[islandName]
    local minLevel = zone and zone.Level and zone.Level.Min or "?"
    local rowY = (index - 1) * 38
    label(travelScroll, islandName .. "Label", islandName .. "  /  Lv." .. tostring(minLevel),
        2, rowY + 5, 245, 26)
    local go = button(travelScroll, islandName .. "Go", "LOCKED", 265, rowY, 86, 30)
    travelRows[islandName] = go
    table.insert(state.connections, go.Activated:Connect(function()
        local unlocked = state.zoneProgress.TeleporterUnlocked
        if not unlocked or unlocked["Waypoint_" .. islandName] ~= true then return end
        local island = islands and islands:FindFirstChild(islandName)
        local waypoint = island and island:FindFirstChild("Waypoint_" .. islandName)
        local anchor = waypoint and (waypoint:FindFirstChild("Teleport", true)
            or waypoint:FindFirstChild("TeleporterPurchasePart", true))
        local position = anchor and modelPosition(anchor)
        if not position then
            setStatus("Waypoint not loaded: " .. islandName)
            return
        end
        state.combat, state.quests = false, false
        refreshUi()
        if moveNear(position, 8) then
            state.travelUntil = os.clock() + 2
            setStatus("Travelled to " .. islandName)
        else
            setStatus("Cannot travel to " .. islandName)
        end
    end))
end

local function refreshTravel()
    local ok, zones = invoke(rf.getZones)
    if ok and type(zones) == "table" then
        state.zoneProgress = zones
    else
        setStatus("Zone status unavailable")
    end
    local unlocked = state.zoneProgress.TeleporterUnlocked or {}
    local count = 0
    for islandName, go in pairs(travelRows) do
        local available = unlocked["Waypoint_" .. islandName] == true
        if available then count = count + 1 end
        go.Text = available and "GO" or "LOCKED"
        go.BackgroundColor3 = available and Color3.fromRGB(46, 128, 107)
            or Color3.fromRGB(64, 69, 74)
    end
    waypointLabel.Text = "Waypoints unlocked: " .. count .. "/11"
end

local function refreshQuestView()
    local lines = {}
    for id, info in pairs(state.questStates) do
        if type(info) == "table" and info.Ongoing then
            local config = questData[id]
            local title = config and config.EnemyType or id
            lines[#lines + 1] = title .. "  /  " .. id
        end
    end
    table.sort(lines)
    questText.Text = #lines > 0 and table.concat(lines, "\n\n") or "No active quests"
    local height = math.max(220, #lines * 52)
    questText.Size = UDim2.fromOffset(352, height)
    questScroll.CanvasSize = UDim2.fromOffset(0, height + 8)
    local story
    for id, info in pairs(state.questStates) do
        if type(info) == "table" and info.Ongoing and not questData[id] then
            story = id
            break
        end
    end
    storyLabel.Text = "Story quest: " .. (story or "none")
end

local function refreshLive()
    levelLabel.Text = "Level: " .. tostring(level())
    enemiesLabel.Text = "Loaded enemies: " .. tostring(#enemies:GetChildren())
end

table.insert(state.connections, refreshTravelButton.Activated:Connect(refreshTravel))

local function refreshGameState()
    local questsOk, quests = invoke(rf.getQuests)
    if questsOk and type(quests) == "table" then
        state.questStates = quests
        refreshQuestView()
    end
    refreshLive()
    state.lastRefresh = os.clock()
end

local function waitForQuest(id, checks, delay)
    for _ = 1, checks do
        task.wait(delay)
        local ok, quests = invoke(rf.getQuests)
        if ok and type(quests) == "table" then
            state.questStates = quests
            if quests[id] and quests[id].Ongoing == true then return true end
        end
    end
    return false
end

local function manageQuest()
    state.questBlocked = false
    local id, config, info = activeKillQuest()
    local currentMob = config and nearestEnemy(config.EnemyType)
    local plan = selectFarmPlan()
    state.plan = plan
    local planKey = plan and (plan.zone .. "/" .. plan.enemyType .. "/" .. plan.mobLevel) or "none"
    if planKey ~= state.lastPlanKey then
        state.lastPlanKey = planKey
        print("[PvPFarm] Plan playerLv=" .. level() .. " target=" .. planKey
            .. " quest=" .. (plan and plan.quest and plan.quest.id or "none"))
    end
    if not plan then
        questLabel.Text = "Quest: no eligible zone spawn"
        setStatus("No zone monster at a safe level")
        return nil, nil
    end
    local preferred = plan.quest
    if state.quests and preferred and not questAvailable(preferred.id) then
        local cached = state.availabilityCache[preferred.id]
        local reason = cached and cached.reason or "unavailable"
        state.questBlocked = true
        questLabel.Text = "Quest locked: " .. preferred.id
        targetLabel.Text = "Target: paused"
        setStatus(tostring(reason):sub(1, 90))
        return nil, nil
    end
    if travelToPlan(plan) then
        setStatus("Traveling to " .. plan.zone .. " for " .. plan.enemyType)
        targetLabel.Text = "Target: loading " .. plan.enemyType
        return nil, nil
    end
    if preferred then preferred.npc = findNpc(preferred.id) end
    if not nearestEnemy(plan.enemyType) and preferred and preferred.npc
        and os.clock() - state.lastZoneMove >= 5 then
        local npcPosition = modelPosition(preferred.npc)
        local characterRoot = root()
        if npcPosition and characterRoot and (characterRoot.Position - npcPosition).Magnitude > 100 then
            state.lastZoneMove = os.clock()
            if moveNear(npcPosition, 12) then
                state.travelUntil = os.clock() + 2
                setStatus("Loading " .. plan.enemyType .. " near quest NPC")
                return nil, nil
            end
        end
    end
    if not state.quests then return nil, nil end
    if not preferred then
        questLabel.Text = "Quest: none for " .. plan.enemyType
        setStatus("Farming " .. plan.enemyType .. " without quest")
        return nil, nil
    end
    preferred.questLevel = plan.mobLevel
    if id ~= preferred.id then
        questLabel.Text = string.format("Quest: %s  Lv.%d", preferred.id, preferred.questLevel)
        if not questAvailable(preferred.id) then
            local cached = state.availabilityCache[preferred.id]
            local reason = cached and cached.reason or "unavailable"
            setStatus("Locked: " .. tostring(reason):sub(1, 90))
            return nil, nil
        end
        local retryAt = state.rejectedQuests[preferred.id] or 0
        if os.clock() < retryAt then
            setStatus("Waiting to retry: " .. preferred.id)
            return nil, nil
        end
        if os.clock() - state.lastQuestAction >= 8 then
            state.lastQuestAction = os.clock()
            setStatus("Requesting quest: " .. preferred.id)
            local directOk, directResult = invoke(rf.accept, preferred.id)
            if waitForQuest(preferred.id, 3, 0.3) then
                setStatus("Quest active: " .. preferred.id)
                questLabel.Text = "Quest: " .. preferred.id
                return preferred.id, preferred.config
            end
            warn("[PvPFarm] Remote-only AcceptQuest " .. preferred.id .. " returned callOk="
                .. tostring(directOk) .. " result=" .. tostring(directResult))
            if not state.alive or not state.quests then return nil, nil end
            local completeOk, completeResult = invoke(rf.complete, preferred.id)
            local talkOk, talkResult = invoke(rf.talk, preferred.id)
            if talkOk and talkResult ~= false then
                task.wait(2.5)
                if not state.alive or not state.quests then return nil, nil end
                local acceptOk, acceptResult = invoke(rf.accept, preferred.id)
                if waitForQuest(preferred.id, 5, 0.4) then
                    setStatus("Quest active: " .. preferred.id)
                    questLabel.Text = "Quest: " .. preferred.id
                    return preferred.id, preferred.config
                end
                warn("[PvPFarm] Remote-only dialogue " .. preferred.id .. " complete="
                    .. tostring(completeOk) .. "/" .. tostring(completeResult) .. " talk="
                    .. tostring(talkResult) .. " accept=" .. tostring(acceptOk) .. "/" .. tostring(acceptResult))
            else
                warn("[PvPFarm] Remote-only TalkToNPC " .. preferred.id .. " returned callOk="
                    .. tostring(talkOk) .. " result=" .. tostring(talkResult))
            end
            local npcPosition = preferred.npc and modelPosition(preferred.npc)
            if not moveNear(npcPosition, 5) then
                state.rejectedQuests[preferred.id] = os.clock() + 8
                setStatus("Waiting for quest NPC: " .. preferred.id)
                return nil, nil
            end
            setStatus("Talking to " .. preferred.id)
            task.wait(0.8)
            if not state.alive or not state.quests then return nil, nil end
            invoke(rf.complete, preferred.id)
            local talked, talkResult = invoke(rf.talk, preferred.id)
            if not talked or talkResult == false then
                state.rejectedQuests[preferred.id] = os.clock() + 30
                setStatus("NPC talk failed: " .. preferred.id)
                warn("[PvPFarm] TalkToNPC " .. preferred.id .. " returned callOk="
                    .. tostring(talked) .. " result=" .. tostring(talkResult))
                return nil, nil
            end
            task.wait(2.5)
            if not state.alive or not state.quests then return nil, nil end
            local ok, result = invoke(rf.accept, preferred.id)
            if waitForQuest(preferred.id, 5, 0.4) then
                state.rejectedQuests[preferred.id] = nil
                setStatus("Quest active: " .. preferred.id)
                questLabel.Text = "Quest: " .. preferred.id
                return preferred.id, preferred.config
            end
            warn("[PvPFarm] AcceptQuest " .. preferred.id .. " failed: callOk=" .. tostring(ok)
                .. " result=" .. tostring(result) .. " available="
                .. tostring(questAvailable(preferred.id)))
            setStatus("Quest not accepted: " .. preferred.id)
            state.rejectedQuests[preferred.id] = os.clock() + 30
        end
        return nil, nil
    end

    if id and info then
        local needed = requiredKills(config)
        local progress = killProgress(info, config.EnemyType)
        questLabel.Text = string.format("Quest: %s  %d/%s", id, progress, needed and tostring(needed) or "?")
        if not currentMob then
            local npc = findNpc(id)
            local npcPosition = npc and modelPosition(npc)
            local characterRoot = root()
            if npcPosition and characterRoot and (characterRoot.Position - npcPosition).Magnitude > 100
                and os.clock() - state.lastZoneMove >= 8 then
                state.lastZoneMove = os.clock()
                if moveNear(npcPosition, 12) then
                    state.travelUntil = os.clock() + 2
                    setStatus("Loading quest target: " .. config.EnemyType)
                end
            else
                setStatus("Waiting for quest target: " .. config.EnemyType)
            end
        end
        if needed and progress >= needed and os.clock() - state.lastQuestAction >= 5 then
            local npc = findNpc(id)
            if npc and moveNear(modelPosition(npc), 11) then
                state.lastQuestAction = os.clock()
                local ok, result = invoke(rf.complete, id)
                refreshGameState()
                local current = state.questStates[id]
                local claimed = current and not current.Ongoing
                setStatus(ok and result ~= false and claimed and ("Claimed: " .. id)
                    or ("Claim not ready: " .. id))
            end
        end
    end
    return id, config
end

local attackProfiles = {
    { length = 0.5175983433446375, start = 0.32206119278560846, finish = 0.41407869112971823 },
    { length = 0.7095411057720081, start = 0.3170290150450982, finish = 0.4528985620703026 },
    { length = 0.469672561255771, start = 0.2683843138617466, finish = 0.40257649478804886 },
}

local function directAttack(enemy, allowBoss)
    local profile = attackProfiles[state.combo]
    local packet = {
        AttackStart = WS:GetServerTimeNow(),
        AttackLength = profile.length,
        AttackEndKeyframeTime = profile.finish,
        Combo = state.combo,
        AttackStartKeyframeTime = profile.start,
    }
    local humanoid = enemy:FindFirstChildOfClass("Humanoid")
    local before = humanoid and humanoid.Health or 0
    local registered, registerResult = invoke(rf.registerAttack, packet)
    if not registered or registerResult == false then return false, "Attack registration failed" end
    task.wait(profile.start)
    if not livingEnemy(enemy, allowBoss) then return true end
    local hit, hitResult = invoke(rf.weaponDamage, enemy, nil)
    state.combo = state.combo % #attackProfiles + 1
    if not hit or hitResult == false then return false, "Damage call rejected" end
    task.wait(0.22)
    if enemy.Parent and humanoid and humanoid.Health >= before then
        state.rejectedHits = state.rejectedHits + 1
        if state.rejectedHits >= 8 then return false, "No damage after 8 hits; switch to INPUT" end
    else
        state.rejectedHits = 0
    end
    return true
end

local function inputAttack()
    local camera = WS.CurrentCamera
    local ok, err = pcall(function()
        local vim = game:GetService("VirtualInputManager")
        local point = camera.ViewportSize / 2
        vim:SendMouseButtonEvent(point.X, point.Y, 0, true, game, 0)
        task.wait(0.08)
        vim:SendMouseButtonEvent(point.X, point.Y, 0, false, game, 0)
    end)
    return ok, err
end

local function farmEnemy(enemy, allowBoss)
    if not livingEnemy(enemy, allowBoss) then return end
    local position = modelPosition(enemy)
    if not moveNear(position, 7) then setStatus("Cannot reach target"); return end
    state.currentTarget = enemy
    targetLabel.Text = string.format("Target: %s  Lv.%s", enemy.Name, tostring(enemy:GetAttribute("Level") or "?"))
    local ok, err
    if state.mode == "Direct" then
        ok, err = directAttack(enemy, allowBoss)
    else
        ok, err = inputAttack()
    end
    if not ok then
        state.combat = false
        setStatus(err or "Attack failed")
        refreshUi()
    end
end

state.stop = function()
    if not state.alive then return end
    state.alive = false
    for _, connection in ipairs(state.connections) do connection:Disconnect() end
    gui:Destroy()
end

task.spawn(function()
    while state.alive do
        local ok, err = pcall(function()
            if os.clock() - state.lastRefresh >= 3 then refreshGameState() end
            if (state.combat or state.quests) and os.clock() >= state.travelUntil then
                manageQuest()
                if state.combat and not state.questBlocked and os.clock() >= state.travelUntil then
                    local targetType = state.plan and state.plan.enemyType
                    local enemy = targetType and nearestEnemy(targetType)
                    if enemy then
                        farmEnemy(enemy, false)
                    else
                        targetLabel.Text = targetType and ("Target: waiting for " .. targetType)
                            or "Target: no eligible monster"
                        if not state.quests then setStatus("Waiting for " .. tostring(targetType or "zone monster")) end
                    end
                end
            end
        end)
        if not ok then
            state.combat, state.quests = false, false
            setStatus("Paused: " .. tostring(err):sub(1, 90))
            warn("[PvPFarm] " .. tostring(err))
            refreshUi()
        end
        task.wait(0.35)
    end
end)

refreshUi()
task.spawn(function()
    while state.alive do
        local ok, err = pcall(refreshTravel)
        if not ok then warn("[ValenHub] Travel refresh: " .. tostring(err)) end
        task.wait(15)
    end
end)
print("[ValenHub] Ready. Farm, quests, travel and live status are available.")
