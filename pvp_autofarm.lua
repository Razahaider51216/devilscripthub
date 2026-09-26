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
    availabilityCache = {}, rejectedQuests = {},
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

local function strongestEnemyType()
    local bestType, bestLevel
    for _, model in ipairs(enemies:GetChildren()) do
        if livingEnemy(model) then
            local mobLevel = tonumber(model:GetAttribute("Level")) or 0
            if mobLevel <= level() + 25 and (not bestLevel or mobLevel > bestLevel) then
                bestType, bestLevel = model.Name, mobLevel
            end
        end
    end
    return bestType
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

local function questLevel(config, npc)
    local first = config.Quests and config.Quests[1]
    local dialogue = type(first) == "table" and first.DialogueRequirement
    local dialogueLevel = type(dialogue) == "table" and tonumber(dialogue.Level) or nil
    local recommended = tonumber(config.RecommendedLevel)
    local island = islandOf(npc)
    local zone = island and zoneData[island]
    local zoneMinimum = zone and zone.Level and tonumber(zone.Level.Min)
    local minimum = dialogueLevel or recommended or zoneMinimum
    if not minimum then return nil end
    return math.max(minimum, recommended or 0, zoneMinimum or 0), minimum
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

local function chooseQuest()
    local best
    local playerLevel = level()
    for id, config in pairs(questData) do
        if type(config) == "table" and type(config.EnemyType) == "string" then
            local npc = findNpc(id)
            if npc then
                local rank, minimum = questLevel(config, npc)
                if rank and minimum <= playerLevel and rank <= playerLevel + 25
                    and (not best or rank > best.questLevel
                        or (rank == best.questLevel and id < best.id)) then
                    best = { id = id, config = config, npc = npc, questLevel = rank }
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

local gui = Instance.new("ScreenGui")
gui.Name = "VANTAPvPFarm"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 110
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(320, 206)
panel.Position = UDim2.new(1, -338, 0, 158)
panel.BackgroundColor3 = Color3.fromRGB(25, 31, 37)
panel.BorderSizePixel = 0
panel.Parent = gui
local border = Instance.new("UIStroke")
border.Color = Color3.fromRGB(80, 129, 113)
border.Thickness = 1
border.Parent = panel

local function textLabel(name, caption, y, height, color)
    local label = Instance.new("TextLabel")
    label.Name = name
    label.Position = UDim2.fromOffset(12, y)
    label.Size = UDim2.new(1, -24, 0, height)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextTruncate = Enum.TextTruncate.AtEnd
    label.TextColor3 = color or Color3.fromRGB(227, 235, 233)
    label.Text = caption
    label.Parent = panel
    return label
end

local function button(name, caption, x, y, width)
    local item = Instance.new("TextButton")
    item.Name = name
    item.Position = UDim2.fromOffset(x, y)
    item.Size = UDim2.fromOffset(width, 34)
    item.BackgroundColor3 = Color3.fromRGB(48, 60, 68)
    item.BorderSizePixel = 0
    item.Font = Enum.Font.GothamBold
    item.TextSize = 13
    item.TextColor3 = Color3.fromRGB(237, 244, 240)
    item.Text = caption
    item.Parent = panel
    return item
end

local header = textLabel("Header", "AUTO FARM  /  PVE", 8, 22)
header.TextSize = 16
header.Active = true
header.Size = UDim2.fromOffset(265, 22)
local closeButton = Instance.new("TextButton")
closeButton.Name = "Close"
closeButton.Position = UDim2.fromOffset(283, 7)
closeButton.Size = UDim2.fromOffset(25, 25)
closeButton.BackgroundTransparency = 1
closeButton.Text = "X"
closeButton.TextSize = 16
closeButton.Font = Enum.Font.GothamBold
closeButton.TextColor3 = Color3.fromRGB(173, 190, 185)
closeButton.Parent = panel
local status = textLabel("Status", "Paused", 36, 25, Color3.fromRGB(157, 183, 174))
local questLabel = textLabel("Quest", "Quest: none", 67, 20)
local targetLabel = textLabel("Target", "Target: none", 91, 20)
local combatButton = button("CombatToggle", "COMBAT: OFF", 12, 123, 145)
local questButton = button("QuestToggle", "QUESTS: OFF", 163, 123, 145)
local modeButton = button("Mode", "ATTACK: DIRECT", 12, 163, 296)

local function setStatus(message)
    if state.alive then status.Text = message end
end

local function refreshUi()
    combatButton.Text = state.combat and "COMBAT: ON" or "COMBAT: OFF"
    questButton.Text = state.quests and "QUESTS: ON" or "QUESTS: OFF"
    combatButton.BackgroundColor3 = state.combat and Color3.fromRGB(36, 111, 84) or Color3.fromRGB(48, 60, 68)
    questButton.BackgroundColor3 = state.quests and Color3.fromRGB(36, 111, 84) or Color3.fromRGB(48, 60, 68)
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
table.insert(state.connections, closeButton.Activated:Connect(function() state.stop() end))

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
    local delta = input.Position - dragStart
    panel.Position = UDim2.new(panelStart.X.Scale, panelStart.X.Offset + delta.X,
        panelStart.Y.Scale, panelStart.Y.Offset + delta.Y)
end))

local function refreshGameState()
    local questsOk, quests = invoke(rf.getQuests)
    if questsOk and type(quests) == "table" then state.questStates = quests end
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
    local id, config, info = activeKillQuest()
    local currentMob = config and nearestEnemy(config.EnemyType)
    local preferred = chooseQuest()
    local currentQuestLevel = id and questLevel(config, findNpc(id)) or 0
    if preferred and (not id or preferred.questLevel > (currentQuestLevel or 0)) then
        questLabel.Text = string.format("Quest: %s  Lv.%d", preferred.id, preferred.questLevel)
        if not questAvailable(preferred.id) then
            local cached = state.availabilityCache[preferred.id]
            local reason = cached and cached.reason or "unavailable"
            setStatus("Locked: " .. tostring(reason):sub(1, 90))
            targetLabel.Text = "Target: waiting for quest unlock"
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
            local npcPosition = modelPosition(preferred.npc)
            if not moveNear(npcPosition, 5) then
                state.rejectedQuests[preferred.id] = os.clock() + 30
                setStatus("Cannot reach quest NPC: " .. preferred.id)
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
    elseif not preferred then
        questLabel.Text = "Quest: no matching level quest loaded"
        if id and not currentMob then setStatus("Quest target not loaded") end
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
            if (state.combat or state.quests) and os.clock() >= state.travelUntil then
                if os.clock() - state.lastRefresh >= 3 then refreshGameState() end
                local _id, config
                if state.quests then _id, config = manageQuest() end
                if state.combat then
                    if state.quests and (not _id or not config) then
                        targetLabel.Text = "Target: waiting for accepted quest"
                    else
                        local enemy = config and nearestEnemy(config.EnemyType)
                        if not state.quests and not enemy then enemy = nearestEnemy(strongestEnemyType()) end
                        if enemy then
                            farmEnemy(enemy, state.quests and config ~= nil)
                        else
                            targetLabel.Text = "Target: waiting for eligible enemy"
                            if not state.quests then setStatus("No enemy at a safe level loaded") end
                        end
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
print("[PvPFarm] Ready, paused. Quest mode attacks only accepted quest targets; no PvP targets.")
