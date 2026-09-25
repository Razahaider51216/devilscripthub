-- VANTA Egg Collector v2
-- Auto collect eggs by the rarities detected in the current map.
-- Flow: find target egg -> teleport to egg -> press Pickup prompt -> return to safe zone.

warn("[VANTA V2] Source loaded")
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local WS = game:GetService("Workspace")
local RS = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local gui = player:WaitForChild("PlayerGui")
local executorEnv = type(getgenv) == "function" and getgenv() or nil
local runtimeEnv = type(executorEnv) == "table" and executorEnv or _G
local previousRuntime = runtimeEnv.VANTA_EggCollectorV2_Runtime
if previousRuntime and type(previousRuntime.stop) == "function" then
    pcall(previousRuntime.stop)
end
local runtime = { active = true, connections = {} }
runtimeEnv.VANTA_EggCollectorV2_Runtime = runtime
warn("[VANTA V2] Starting egg collector...")

local RARITY_OPTIONS = {}
local KNOWN_RARITIES = {}
local TARGET_RARITIES = {}
local RARITY_PRIORITY = {}

local MAP_RARITIES = {
    "Common", "Uncommon", "Rare", "Epic", "Legendary",
    "Mythic", "Cosmic", "Divine", "Secret", "Eternal",
}

local BASE_RARITY_PRIORITY = {
    Eternal = 10,
    Secret = 9,
    Divine = 8,
    Cosmic = 7,
    Mythic = 6,
    Legendary = 5,
    Epic = 4,
    Rare = 3,
    Uncommon = 2,
    Common = 1,
}

local HIGH_RARITY_NAMES = {
    Mythic = true,
    Cosmic = true,
    Secret = true,
    Divine = true,
    Eternal = true,
}

local RARITY_COLOR = {
    Common = Color3.fromRGB(210, 220, 230),
    Uncommon = Color3.fromRGB(80, 220, 140),
    Rare = Color3.fromRGB(80, 150, 255),
    Epic = Color3.fromRGB(170, 95, 255),
    Legendary = Color3.fromRGB(255, 145, 70),
    Mythic = Color3.fromRGB(255, 80, 220),
    Cosmic = Color3.fromRGB(90, 230, 255),
    Divine = Color3.fromRGB(255, 225, 85),
    Secret = Color3.fromRGB(255, 125, 155),
    Eternal = Color3.fromRGB(180, 255, 160),
}

local COLLECTED_WORDS = {
    "carried",
    "placed",
    "collected",
    "claimed",
    "picked",
    "owned",
    "inventory",
    "backpack",
    "equipped",
    "storage",
}

local UI = {
    bg = Color3.fromRGB(22, 24, 28),
    side = Color3.fromRGB(29, 32, 37),
    card = Color3.fromRGB(35, 39, 44),
    button = Color3.fromRGB(48, 53, 59),
    cyan = Color3.fromRGB(65, 222, 204),
    magenta = Color3.fromRGB(245, 124, 157),
    amber = Color3.fromRGB(255, 199, 91),
    green = Color3.fromRGB(107, 231, 150),
    red = Color3.fromRGB(255, 112, 122),
    text = Color3.fromRGB(255, 255, 255),
    muted = Color3.fromRGB(193, 201, 207),
}

local autoOn = false
local espOn = false
local longRangeOn = true
local deepScanBusy = false
local lastDeepScan = 0
local deepScanCooldown = 5
local rareFirstOn = true
local trainingX2On = false
local trainingBusy = false
local trainingDelay = 0.25
local trainingSentCount = 0
local trainingFailedCount = 0
local trainingPendingToken = nil
local trainingLastSpawnAt = 0
local trainingAttempts = {}
local trainingSentTokens = {}
local trainingBonusRemote = nil
local trainingBonusConnection = nil
local trainingLoopGeneration = 0
local preTeleportDelay = 3.5
local collectBusy = false
local safeCFrame = nil
local autoDelay = 1.6
local targetCount = 0
local collectedCount = 0
local failedCount = 0
local processed = {}
local espStore = {}

local statusLbl
local safeLbl
local countLbl
local delayValueLbl
local autoBtn
local deepScanBtn
local espBtn
local rarerModeBtn
local trainingBtn
local trainingStatusLbl
local rarityButtons = {}
local selectedSummaryLbl
local rarityListFrame
local rebuildRarityButtons
local mainGui

local function getCharacterRoot()
    local char = player.Character
    if not char then return nil, nil end
    return char, char:FindFirstChild("HumanoidRootPart")
end

local function captureSafeZone()
    local _, hrp = getCharacterRoot()
    if hrp then
        safeCFrame = hrp.CFrame
        return true
    end
    return false
end

captureSafeZone()

local function setStatus(text, color)
    if statusLbl then
        statusLbl.Text = text
        statusLbl.TextColor3 = color or UI.muted
    end
end

local function cleanText(value)
    if value == nil then return "" end
    local text = tostring(value)
    text = text:gsub("<.->", "")
    text = text:gsub("[\r\n\t]+", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

local function isHighRarityName(rarity)
    rarity = cleanText(rarity)
    if HIGH_RARITY_NAMES[rarity] then return true end

    local lowered = rarity:lower()
    return lowered:find("myth", 1, true) ~= nil
        or lowered:find("cosmic", 1, true) ~= nil
        or lowered:find("secret", 1, true) ~= nil
        or lowered:find("divine", 1, true) ~= nil
        or lowered:find("eternal", 1, true) ~= nil
end

local function rarityHashColor(rarity)
    local hash = 0
    for i = 1, #rarity do
        hash = (hash * 31 + rarity:byte(i)) % 360
    end
    return Color3.fromHSV(hash / 360, 0.62, 1)
end

local function addRarityOption(rarity, selected)
    rarity = cleanText(rarity)
    if rarity == "" then return nil end

    if not KNOWN_RARITIES[rarity] then
        table.insert(RARITY_OPTIONS, rarity)
        KNOWN_RARITIES[rarity] = true
        RARITY_PRIORITY[rarity] = BASE_RARITY_PRIORITY[rarity] or math.max(1, 100 - #RARITY_OPTIONS)
        if TARGET_RARITIES[rarity] == nil then
            TARGET_RARITIES[rarity] = selected == true
        end
        if not RARITY_COLOR[rarity] then
            RARITY_COLOR[rarity] = rarityHashColor(rarity)
        end
    end

    return rarity
end

for _, rarity in ipairs(MAP_RARITIES) do
    addRarityOption(rarity, false)
end

local function updateSafeLabel()
    if not safeLbl then return end
    if not safeCFrame then
        safeLbl.Text = "Safe Zone: not set"
        safeLbl.TextColor3 = UI.red
        return
    end
    local p = safeCFrame.Position
    safeLbl.Text = string.format("Safe Zone: %.0f, %.0f, %.0f", p.X, p.Y, p.Z)
    safeLbl.TextColor3 = UI.green
end

local function updateCountLabel()
    if countLbl then
        countLbl.Text = string.format("Targets: %d  |  Picked: %d  |  Failed: %d", targetCount, collectedCount, failedCount)
    end
end

local function selectedRarityText()
    local out = {}
    for _, rarity in ipairs(RARITY_OPTIONS) do
        if TARGET_RARITIES[rarity] then
            table.insert(out, rarity)
        end
    end
    if #out == 0 then
        return "Selected: none"
    end
    return "Selected: " .. table.concat(out, ", ")
end

local function hasSelectedRarity()
    for _, rarity in ipairs(RARITY_OPTIONS) do
        if TARGET_RARITIES[rarity] == true then
            return true
        end
    end
    return false
end

local function selectedMinPriority()
    local minPriority = nil
    for _, rarity in ipairs(RARITY_OPTIONS) do
        if TARGET_RARITIES[rarity] then
            local priority = RARITY_PRIORITY[rarity] or 0
            minPriority = minPriority and math.min(minPriority, priority) or priority
        end
    end
    return minPriority
end

local function rarityPassesFilter(rarity)
    return TARGET_RARITIES[rarity] == true
end

local function updateRarityButtons()
    for rarity, btn in pairs(rarityButtons) do
        local active = TARGET_RARITIES[rarity] == true
        btn.Text = (active and "[ON] " or "[OFF] ") .. rarity
        btn.TextColor3 = active and UI.text or UI.muted
        btn.BackgroundColor3 = active and Color3.fromRGB(44, 101, 94) or UI.button
    end
    if selectedSummaryLbl then
        selectedSummaryLbl.Text = selectedRarityText()
        selectedSummaryLbl.TextColor3 = selectedMinPriority() == nil and UI.red or UI.muted
    end
    if rarerModeBtn then
        rarerModeBtn.Text = rareFirstOn and "RARE FIRST ON" or "RARE FIRST OFF"
        rarerModeBtn.TextColor3 = rareFirstOn and UI.green or UI.muted
        rarerModeBtn.BackgroundColor3 = rareFirstOn and Color3.fromRGB(44, 101, 94) or UI.button
    end
end

local function rarityColor(rarity)
    return RARITY_COLOR[rarity] or UI.text
end

local function getAttr(inst, ...)
    for _, key in ipairs({...}) do
        local value = inst:GetAttribute(key)
        if value ~= nil and cleanText(value) ~= "" then
            return cleanText(value)
        end
    end
    return nil
end

local function getRarityAttr(inst)
    for _, key in ipairs({ "Rarity", "EggRarity", "Tier" }) do
        local value = inst:GetAttribute(key)
        local text = cleanText(value)
        if text ~= "" and not tonumber(text) then
            return text
        end
    end

    return nil
end

local function getLabelText(root, labelName)
    for _, d in ipairs(root:GetDescendants()) do
        if d.Name == labelName and (d:IsA("TextLabel") or d:IsA("TextButton")) then
            local text = cleanText(d.Text)
            if text ~= "" then return text end
        end
    end
    return nil
end

local function getTextRarity(inst)
    return getLabelText(inst, "RarityLabel")
end

local function getTextDisplayName(inst)
    return getLabelText(inst, "EggName")
end

local BLACKLIST_NAME = {
    EggVFX = true,
    EggInfo = true,
    EggPlacement = true,
    EggPrompt = true,
    EggKgBillboard = true,
    EggBackWeld = true,
    SkipHatch = true,
    HatchReady = true,
    HatchPrompt = true,
    EggRangeHighl = true,
}

local function nameBlacklisted(name)
    for prefix in pairs(BLACKLIST_NAME) do
        if name:find(prefix, 1, true) then
            return true
        end
    end
    return false
end

local function isEgg(inst)
    if typeof(inst) ~= "Instance" or not inst:IsA("Model") then return false end
    local name = inst.Name
    if nameBlacklisted(name) then return false end
    if inst:GetAttribute("EggType") then return true end
    if inst:GetAttribute("Rarity") or inst:GetAttribute("EggRarity") then return true end
    local lowered = name:lower()
    return lowered:match("egg$") ~= nil or lowered:match("^egg[%s_%-]*%d+$") ~= nil
end

local function isSpawnedEgg(inst)
    local spawnedItems = WS:FindFirstChild("SpawnedItems")
    return typeof(inst) == "Instance"
        and inst:IsA("Model")
        and spawnedItems ~= nil
        and inst.Parent == spawnedItems
        and inst:GetAttribute("EntityId") ~= nil
        and inst:GetAttribute("EggType") ~= nil
end

local function getEggAncestor(inst)
    local node = inst
    while node and node ~= WS do
        if isEgg(node) then
            return node
        end
        node = node.Parent
    end
    return nil
end

local function resolveInfo(inst)
    local rarity = getTextRarity(inst) or getRarityAttr(inst)
    local displayName = getTextDisplayName(inst) or getAttr(inst, "DisplayName", "EggType") or inst.Name
    local kg = getAttr(inst, "Kg", "Weight", "Mass")
    local biome = getAttr(inst, "Biome") or ""

    if rarity then
        for target in pairs(KNOWN_RARITIES) do
            if rarity:lower() == target:lower() then
                rarity = target
                break
            end
        end
    end

    if rarity then
        rarity = addRarityOption(rarity, false)
    else
        rarity = "Unknown"
    end
    return rarity, displayName, kg, biome
end

local function hasTruthyAttr(inst, ...)
    for _, key in ipairs({...}) do
        local value = inst:GetAttribute(key)
        if value == true then return true end
        if type(value) == "string" then
            local lowered = value:lower()
            if lowered == "true" or lowered == "yes" or lowered == "collected" or lowered == "claimed" then
                return true
            end
        end
    end
    return false
end

local function pathHasCollectedMarker(inst)
    local node = inst
    while node and node ~= WS do
        local name = node.Name:lower()
        for _, word in ipairs(COLLECTED_WORDS) do
            if name:find(word, 1, true) then
                return true
            end
        end
        node = node.Parent
    end
    return false
end

local function isInsidePlayerCharacter(inst)
    for _, plr in ipairs(Players:GetPlayers()) do
        local char = plr.Character
        if char and inst:IsDescendantOf(char) then
            return true
        end
    end
    return false
end

local function isInPlacedPlot(inst)
    local plots = WS:FindFirstChild("Plots")
    return plots ~= nil and inst:IsDescendantOf(plots)
end

local function isCollectedOrStoredEgg(inst)
    if inst:GetAttribute("CarriedEggProxy") or inst:GetAttribute("PlacedEgg") then return true end
    if inst.Name:find("_Placed_", 1, true) or inst.Name:find("_CarriedEgg", 1, true) then return true end
    if hasTruthyAttr(inst, "Collected", "IsCollected", "Claimed", "PickedUp", "IsPickedUp", "InInventory", "Stored", "Opened") then return true end
    if isInsidePlayerCharacter(inst) then return true end
    if isInPlacedPlot(inst) then return true end
    return pathHasCollectedMarker(inst)
end

local function getAnchor(inst)
    return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
end

local function targetKey(inst)
    local entityId = getAttr(inst, "EntityId")
    if entityId then return entityId end
    local ok, fullName = pcall(function()
        return inst:GetFullName()
    end)
    local anchor = getAnchor(inst)
    local pos = anchor and anchor.Position
    local rarity, name, kg = resolveInfo(inst)
    return table.concat({
        ok and fullName or tostring(inst),
        rarity,
        name,
        tostring(kg or ""),
        pos and string.format("%.1f,%.1f,%.1f", pos.X, pos.Y, pos.Z) or "no-pos",
    }, "|")
end

local function isTargetEgg(inst)
    if not isSpawnedEgg(inst) then return false end
    if isCollectedOrStoredEgg(inst) then return false end
    local rarity = resolveInfo(inst)
    return rarityPassesFilter(rarity)
end

local function formatWeight(kg)
    if not kg or tostring(kg) == "" then return "N/A" end
    local n = tonumber(kg)
    if not n then return tostring(kg) end
    if n >= 1000000 then
        return string.format("%.2fM kg", n / 1000000)
    elseif n >= 1000 then
        return string.format("%.2fK kg", n / 1000)
    end
    return string.format("%.2f kg", n)
end

local findPickupPrompt
local collectEgg

local function getTargets()
    local list = {}
    local _, hrp = getCharacterRoot()
    local origin = hrp and hrp.Position
    local spawnedItems = WS:FindFirstChild("SpawnedItems")

    for _, inst in ipairs(spawnedItems and spawnedItems:GetChildren() or {}) do
        if isTargetEgg(inst) and findPickupPrompt and findPickupPrompt(inst) then
            local anchor = getAnchor(inst)
            if anchor then
                local rarity = resolveInfo(inst)
                local distance = origin and (anchor.Position - origin).Magnitude or 0
                if longRangeOn or not origin or distance <= 250 then
                    table.insert(list, {
                        inst = inst,
                        anchor = anchor,
                        rarity = rarity,
                        priority = RARITY_PRIORITY[rarity] or 0,
                        distance = distance,
                    })
                end
            end
        end
    end

    table.sort(list, function(a, b)
        if rareFirstOn and a.priority ~= b.priority then
            return a.priority > b.priority
        end
        return a.distance < b.distance
    end)

    targetCount = #list
    updateCountLabel()
    return list
end

local function discoverMapRarities()
    local before = #RARITY_OPTIONS
    local spawnedItems = WS:FindFirstChild("SpawnedItems")

    for _, inst in ipairs(spawnedItems and spawnedItems:GetChildren() or {}) do
        if isSpawnedEgg(inst) and not isCollectedOrStoredEgg(inst) then
            resolveInfo(inst)
        end
    end

    if #RARITY_OPTIONS == 0 then
        addRarityOption("Unknown", false)
    end

    if rebuildRarityButtons and #RARITY_OPTIONS ~= before then
        rebuildRarityButtons()
    end
    updateRarityButtons()

    return #RARITY_OPTIONS ~= before
end

local function isPickupPrompt(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then return false end
    if prompt.Enabled == false then return false end
    local text = ((prompt.ActionText or "") .. " " .. (prompt.ObjectText or "") .. " " .. prompt.Name):lower()
    return text:find("pickup", 1, true)
        or text:find("pick up", 1, true)
        or text:find("collect", 1, true)
        or text:find("เก็บ", 1, true)
end

findPickupPrompt = function(egg)
    if not isSpawnedEgg(egg) then return nil end
    for _, d in ipairs(egg:GetDescendants()) do
        if isPickupPrompt(d) and getEggAncestor(d) == egg then
            return d
        end
    end
    return nil
end

local function findTrainingRemote(remoteName, className)
    local direct = RS:FindFirstChild("Packages")
    if direct then
        local ok, found = pcall(function()
            return RS["Packages"]["_Index"]["sleitnick_knit@1.7.0"]["knit"]["Services"]["TrainingService"][className == "RemoteEvent" and "RE" or "RF"][remoteName]
        end)
        if ok and found and found:IsA(className) then
            return found
        end
    end

    for _, d in ipairs(RS:GetDescendants()) do
        if d.Name == remoteName and d:IsA(className) then
            local full = d:GetFullName()
            if full:find("TrainingService", 1, true) then
                return d
            end
        end
    end

    return nil
end

local function trainingStatus(text, color)
    if trainingStatusLbl then
        trainingStatusLbl.Text = text
        trainingStatusLbl.TextColor3 = color or UI.muted
    end
    setStatus(text, color)
end

local function updateTrainingButton()
    if not trainingBtn then return end
    trainingBtn.Text = trainingX2On and "AUTO TRAIN X2: ON" or "AUTO TRAIN X2: OFF"
    trainingBtn.TextColor3 = trainingX2On and UI.text or UI.amber
    trainingBtn.BackgroundColor3 = trainingX2On and Color3.fromRGB(125, 82, 26) or UI.button
end

local function updateTrainingStatus()
    if trainingStatusLbl then
        trainingStatusLbl.Text = string.format("Sent: %d  |  Failed: %d", trainingSentCount, trainingFailedCount)
        trainingStatusLbl.TextColor3 = trainingX2On and UI.green or UI.muted
    end
end

local hookTrainingBonusRemote
local function claimTrainingX2(automatic)
    if automatic and not trainingX2On then return false end
    local token = trainingPendingToken
    if trainingBusy or not runtime.active then return false end
    if type(token) ~= "string" or token == "" then
        trainingStatus("Waiting for the next x2 bonus", UI.muted)
        return false
    end
    if trainingSentTokens[token] then
        trainingPendingToken = nil
        return false
    end
    if os.clock() - trainingLastSpawnAt > 8 then
        trainingPendingToken = nil
        trainingStatus("x2 bonus expired; waiting for the next one", UI.muted)
        return false
    end

    local claim = findTrainingRemote("ClaimBonus", "RemoteFunction")
    if not claim then
        trainingStatus("ClaimBonus remote not found", UI.red)
        return false
    end

    trainingBusy = true
    local ok, result = pcall(function()
        return claim:InvokeServer(token)
    end)
    trainingBusy = false
    if not runtime.active then return false end

    if ok and result ~= false then
        trainingSentTokens[token] = true
        if trainingPendingToken == token then trainingPendingToken = nil end
        trainingSentCount = trainingSentCount + 1
        updateTrainingStatus()
        trainingStatus("Training x2 claim sent", UI.green)
        return true
    end

    trainingAttempts[token] = (trainingAttempts[token] or 0) + 1
    if trainingAttempts[token] >= 3 then
        if trainingPendingToken == token then trainingPendingToken = nil end
        trainingFailedCount = trainingFailedCount + 1
        updateTrainingStatus()
        trainingStatus("Training x2 claim failed", UI.red)
        warn("[VANTA V2] ClaimBonus failed:", result)
    end
    return false
end

local function trainingX2Loop()
    trainingLoopGeneration = trainingLoopGeneration + 1
    local generation = trainingLoopGeneration
    task.spawn(function()
        while runtime.active and trainingX2On and generation == trainingLoopGeneration do
            if not trainingBonusRemote or not trainingBonusRemote.Parent then
                hookTrainingBonusRemote()
            end
            if trainingPendingToken then claimTrainingX2(true) end
            task.wait(trainingDelay)
        end
    end)
end

hookTrainingBonusRemote = function()
    if trainingBonusRemote and trainingBonusRemote.Parent then return true end
    local spawnBonus = findTrainingRemote("SpawnBonus", "RemoteEvent")
    if not spawnBonus then return false end
    if trainingBonusConnection then trainingBonusConnection:Disconnect() end

    trainingBonusRemote = spawnBonus
    trainingBonusConnection = spawnBonus.OnClientEvent:Connect(function(token)
        if not runtime.active or type(token) ~= "string" or token == "" then return end
        if trainingSentTokens[token] then return end
        trainingPendingToken = token
        trainingLastSpawnAt = os.clock()
        if trainingX2On then
            task.defer(function() claimTrainingX2(true) end)
        end
    end)
    table.insert(runtime.connections, trainingBonusConnection)
    return true
end

local function firePrompt(prompt)
    if not prompt then return false end

    pcall(function()
        prompt.Enabled = true
        prompt.MaxActivationDistance = 25
        prompt.HoldDuration = 0
    end)

    if fireproximityprompt then
        local ok = pcall(function()
            fireproximityprompt(prompt)
        end)
        if ok then return true end
    end

    local ok = pcall(function()
        prompt:InputHoldBegin()
        task.wait(0.15)
        prompt:InputHoldEnd()
    end)
    if ok then return true end

    return false
end

local function pivotTo(cf)
    local char, hrp = getCharacterRoot()
    if not char or not hrp then return false end
    pcall(function()
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end)
    char:PivotTo(cf)
    return true
end

local function returnToSafe()
    if not safeCFrame then
        captureSafeZone()
    end
    if safeCFrame then
        return pivotTo(safeCFrame + Vector3.new(0, 3, 0))
    end
    return false
end

local function flatUnit(v, fallback)
    local flat = Vector3.new(v.X, 0, v.Z)
    if flat.Magnitude < 0.05 then
        return fallback
    end
    return flat.Unit
end

local function deepScanPoints()
    local _, hrp = getCharacterRoot()
    local base = safeCFrame or (hrp and hrp.CFrame)
    if not base then
        return {}
    end

    local origin = base.Position
    local forward = flatUnit(base.LookVector, Vector3.new(0, 0, -1))
    local right = flatUnit(base.RightVector, Vector3.new(1, 0, 0))
    local distances = { 180, 360, 600, 900, 1250, 1650, 2100, 2600 }
    local dirs = {
        forward,
        -forward,
        right,
        -right,
        (forward + right).Unit,
        (forward - right).Unit,
        (-forward + right).Unit,
        (-forward - right).Unit,
    }

    local points = {}
    for _, dist in ipairs(distances) do
        for _, dir in ipairs(dirs) do
            table.insert(points, CFrame.new(origin + dir * dist + Vector3.new(0, 7, 0)))
        end
    end

    return points
end

local function deepScanForTarget(force)
    if deepScanBusy then return false end
    if not force and os.clock() - lastDeepScan < deepScanCooldown then return false end

    deepScanBusy = true
    lastDeepScan = os.clock()
    discoverMapRarities()

    local targets = getTargets()
    for _, item in ipairs(targets) do
        local key = targetKey(item.inst)
        if not processed[key] or os.clock() - processed[key] >= 20 then
            deepScanBusy = false
            return collectEgg(item.inst)
        end
    end

    deepScanBusy = false
    setStatus("Long range rescan done: no loaded target", UI.muted)
    return false
end

collectEgg = function(egg)
    if not runtime.active or not hasSelectedRarity() or collectBusy or not egg or not egg.Parent or not isTargetEgg(egg) then return false end
    collectBusy = true

    local rarity, name, kg = resolveInfo(egg)
    local anchor = getAnchor(egg)
    if not anchor then
        failedCount = failedCount + 1
        collectBusy = false
        updateCountLabel()
        return false
    end

    local prompt = findPickupPrompt(egg)
    if not prompt then
        processed[targetKey(egg)] = os.clock()
        collectBusy = false
        setStatus("Skip collected/no pickup prompt: " .. tostring(name), UI.muted)
        return false
    end

    local key = targetKey(egg)
    if processed[key] and os.clock() - processed[key] < 20 then
        collectBusy = false
        return false
    end
    processed[key] = os.clock()

    if not safeCFrame then
        captureSafeZone()
    end

    setStatus("Wait " .. string.format("%.1f", preTeleportDelay) .. "s -> " .. rarity .. " " .. name, rarityColor(rarity))
    task.wait(preTeleportDelay)

    if not runtime.active or not egg.Parent or not isTargetEgg(egg) then
        processed[key] = os.clock()
        collectBusy = false
        setStatus("Skip vanished/changed egg: " .. tostring(name), UI.muted)
        return false
    end

    anchor = getAnchor(egg)
    prompt = findPickupPrompt(egg)
    if not anchor or not prompt then
        processed[key] = os.clock()
        collectBusy = false
        setStatus("Skip no pickup after delay: " .. tostring(name), UI.muted)
        return false
    end

    setStatus("TP -> " .. rarity .. " " .. name .. " (" .. formatWeight(kg) .. ")", rarityColor(rarity))
    warn("[VANTA V2] TP target:", rarity, egg:GetFullName(), "prompt:", prompt:GetFullName())
    pivotTo(CFrame.new(anchor.Position + Vector3.new(0, 4, 0), anchor.Position))
    task.wait(0.35)

    if not runtime.active or not egg.Parent or not isTargetEgg(egg) then
        returnToSafe()
        collectBusy = false
        setStatus("Skip unselected/changed egg: " .. tostring(name), UI.muted)
        return false
    end

    prompt = findPickupPrompt(egg)
    local picked = false
    if prompt then
        setStatus("Pickup: " .. name, rarityColor(rarity))
        picked = firePrompt(prompt)
    else
        setStatus("Pickup prompt not found: " .. name, UI.red)
    end

    task.wait(0.45)
    returnToSafe()

    if picked then
        collectedCount = collectedCount + 1
        setStatus("Picked + returned safe: " .. rarity .. " " .. name, UI.green)
    else
        failedCount = failedCount + 1
        setStatus("Failed + returned safe: " .. rarity .. " " .. name, UI.red)
    end

    updateCountLabel()
    collectBusy = false
    return picked
end

local function collectBest()
    if not runtime.active or not hasSelectedRarity() then
        setStatus("Waiting for a selected rarity", UI.muted)
        return false
    end
    local targets = getTargets()
    for _, item in ipairs(targets) do
        local key = targetKey(item.inst)
        if not processed[key] or os.clock() - processed[key] >= 20 then
            return collectEgg(item.inst)
        end
    end
    setStatus("No fresh selected egg (" .. selectedRarityText() .. ")", UI.muted)
    return false
end

local function autoLoop()
    task.spawn(function()
        while runtime.active and autoOn do
            if not collectBusy then
                collectBest()
            end
            task.wait(autoDelay)
        end
    end)
end

local function clearESP()
    for inst, pack in pairs(espStore) do
        if pack.box then pack.box:Destroy() end
        if pack.bill then pack.bill:Destroy() end
        if pack.conn then pack.conn:Disconnect() end
        espStore[inst] = nil
    end
end

local function attachESP(egg)
    if espStore[egg] or not isTargetEgg(egg) then return end
    local anchor = getAnchor(egg)
    if not anchor then return end
    local rarity, name, kg = resolveInfo(egg)
    local color = rarityColor(rarity)

    local box = Instance.new("SelectionBox")
    box.Adornee = egg
    box.Color3 = color
    box.LineThickness = 0.04
    box.SurfaceTransparency = 0.85
    box.Parent = gui

    local bill = Instance.new("BillboardGui")
    bill.Size = UDim2.new(0, 130, 0, 48)
    bill.StudsOffset = Vector3.new(0, 4, 0)
    bill.MaxDistance = 180
    bill.AlwaysOnTop = true
    bill.Adornee = anchor
    bill.Parent = gui

    local bg = Instance.new("Frame")
    bg.Size = UDim2.new(1, 0, 1, 0)
    bg.BackgroundColor3 = Color3.fromRGB(22, 28, 42)
    bg.BackgroundTransparency = 0.08
    bg.BorderSizePixel = 0
    bg.Parent = bill
    Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 7)
    local stroke = Instance.new("UIStroke", bg)
    stroke.Color = color
    stroke.Thickness = 1.2

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -8, 0, 20)
    title.Position = UDim2.new(0, 4, 0, 3)
    title.BackgroundTransparency = 1
    title.Text = name
    title.TextColor3 = UI.text
    title.Font = Enum.Font.GothamBold
    title.TextScaled = true
    title.Parent = bg

    local meta = Instance.new("TextLabel")
    meta.Size = UDim2.new(1, -8, 0, 18)
    meta.Position = UDim2.new(0, 4, 0, 25)
    meta.BackgroundTransparency = 1
    meta.Text = rarity .. " | " .. formatWeight(kg)
    meta.TextColor3 = color
    meta.Font = Enum.Font.GothamSemibold
    meta.TextScaled = true
    meta.Parent = bg

    local conn = egg.AncestryChanged:Connect(function(_, parent)
        if parent == nil and espStore[egg] then
            if espStore[egg].box then espStore[egg].box:Destroy() end
            if espStore[egg].bill then espStore[egg].bill:Destroy() end
            if espStore[egg].conn then espStore[egg].conn:Disconnect() end
            espStore[egg] = nil
        end
    end)

    espStore[egg] = { box = box, bill = bill, conn = conn }
end

local function scanESP()
    if not espOn then return end
    for _, item in ipairs(getTargets()) do
        attachESP(item.inst)
    end
end

-- GUI
local legacyAutoRunning = false
for _, oldGui in ipairs(gui:GetChildren()) do
    if (oldGui.Name == "VANTA_EggCollectorV2" or oldGui.Name == "VANTA_EggHunter") and oldGui:IsA("ScreenGui") then
        local oldAutoText = oldGui.Name == "VANTA_EggHunter" and "AUTO EGG: ON" or "AUTO COLLECT: ON"
        local autoButton
        for _, child in ipairs(oldGui:GetDescendants()) do
            if child:IsA("TextButton") and child.Text == oldAutoText then
                autoButton = child
                break
            end
        end
        if autoButton then
            if type(getconnections) == "function" then
                pcall(function()
                    for _, connection in ipairs(getconnections(autoButton.MouseButton1Click)) do
                        if autoButton.Text ~= oldAutoText then break end
                        if type(connection.Fire) == "function" then
                            connection:Fire()
                        elseif type(connection.Function) == "function" then
                            connection.Function()
                        end
                    end
                end)
            end
            if autoButton.Text == oldAutoText and type(firesignal) == "function" then
                pcall(function() firesignal(autoButton.MouseButton1Click) end)
            end
        end
        if autoButton and autoButton.Text == oldAutoText then
            legacyAutoRunning = true
        elseif oldGui.Name == "VANTA_EggCollectorV2" then
            oldGui:Destroy()
        end
    end
end

local sg = Instance.new("ScreenGui")
sg.Name = "VANTA_EggCollectorV2"
sg.ResetOnSpawn = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.IgnoreGuiInset = true
sg.DisplayOrder = 1000
sg.Parent = gui
mainGui = sg

runtime.stop = function()
    if not runtime.active then return end
    runtime.active = false
    autoOn = false
    trainingX2On = false
    for _, connection in ipairs(runtime.connections) do
        connection:Disconnect()
    end
    clearESP()
    if mainGui then mainGui:Destroy() end
end

local iconBtn = Instance.new("TextButton")
iconBtn.Size = UDim2.new(0, 52, 0, 52)
iconBtn.Position = UDim2.new(0, 14, 0.5, -26)
iconBtn.BackgroundColor3 = Color3.fromRGB(44, 101, 94)
iconBtn.BorderSizePixel = 0
iconBtn.Text = "EGG"
iconBtn.TextColor3 = UI.cyan
iconBtn.TextSize = 13
iconBtn.Font = Enum.Font.GothamBlack
iconBtn.Parent = sg
Instance.new("UICorner", iconBtn).CornerRadius = UDim.new(1, 0)
local iconStroke = Instance.new("UIStroke", iconBtn)
iconStroke.Color = UI.cyan
iconStroke.Thickness = 1.7

local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 560, 0, 410)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.BackgroundColor3 = UI.bg
panel.BorderSizePixel = 0
panel.Visible = true
panel.Active = true
panel.Parent = sg
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)
local panelStroke = Instance.new("UIStroke", panel)
panelStroke.Color = UI.cyan
panelStroke.Thickness = 1.4

local panelScale = Instance.new("UIScale", panel)
local function updatePanelScale()
    local camera = WS.CurrentCamera
    if not camera then return end
    local viewport = camera.ViewportSize
    panelScale.Scale = math.max(0.1, math.min(1, (viewport.X - 24) / 560, (viewport.Y - 24) / 410))
end
updatePanelScale()
local viewportConnection
local function watchViewport()
    if viewportConnection then viewportConnection:Disconnect() end
    local camera = WS.CurrentCamera
    if camera then
        viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updatePanelScale)
        table.insert(runtime.connections, viewportConnection)
    end
    updatePanelScale()
end
table.insert(runtime.connections, WS:GetPropertyChangedSignal("CurrentCamera"):Connect(watchViewport))
watchViewport()

local top = Instance.new("Frame")
top.Size = UDim2.new(1, 0, 0, 44)
top.BackgroundColor3 = UI.button
top.BorderSizePixel = 0
top.Parent = panel
Instance.new("UICorner", top).CornerRadius = UDim.new(0, 8)

local topFill = Instance.new("Frame")
topFill.Size = UDim2.new(1, 0, 0.5, 0)
topFill.Position = UDim2.new(0, 0, 0.5, 0)
topFill.BackgroundColor3 = UI.button
topFill.BorderSizePixel = 0
topFill.Parent = top

local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -62, 1, 0)
titleLbl.Position = UDim2.new(0, 14, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "VANTA EGG COLLECTOR V2"
titleLbl.TextColor3 = UI.text
titleLbl.Font = Enum.Font.GothamBlack
titleLbl.TextSize = 13
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.Parent = top

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.fromOffset(28, 28)
closeBtn.Position = UDim2.new(1, -36, 0, 8)
closeBtn.BackgroundColor3 = UI.side
closeBtn.BorderSizePixel = 0
closeBtn.Text = "X"
closeBtn.TextColor3 = UI.muted
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 12
closeBtn.Parent = top
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)
closeBtn.MouseButton1Click:Connect(function()
    panel.Visible = false
    iconBtn.BackgroundColor3 = UI.button
end)

do
    local dragging = false
    local dragStart = nil
    local startPos = nil
    top.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = panel.Position
        end
    end)
    top.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            panel.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

do
    local dragging = false
    local dragStart = nil
    local startPos = nil
    iconBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = iconBtn.Position
        end
    end)
    iconBtn.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            iconBtn.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, 142, 1, -58)
sidebar.Position = UDim2.new(0, 12, 0, 52)
sidebar.BackgroundColor3 = UI.side
sidebar.BorderSizePixel = 0
sidebar.Parent = panel
Instance.new("UICorner", sidebar).CornerRadius = UDim.new(0, 8)

local content = Instance.new("Frame")
content.Size = UDim2.new(1, -172, 1, -58)
content.Position = UDim2.new(0, 164, 0, 52)
content.BackgroundColor3 = UI.card
content.BorderSizePixel = 0
content.Parent = panel
Instance.new("UICorner", content).CornerRadius = UDim.new(0, 8)

local sections = {}
local navButtons = {}
local navAccents = {}

local function mkSection(name)
    local frame = Instance.new("ScrollingFrame")
    frame.Name = name .. "Section"
    frame.Size = UDim2.new(1, -20, 1, -20)
    frame.Position = UDim2.new(0, 10, 0, 10)
    frame.BackgroundTransparency = 1
    frame.BorderSizePixel = 0
    frame.ScrollBarThickness = 4
    frame.ScrollBarImageColor3 = UI.cyan
    frame.ScrollingDirection = Enum.ScrollingDirection.Y
    frame.CanvasSize = UDim2.new(0, 0, 0, 350)
    frame.Visible = false
    frame.Parent = content
    sections[name] = frame
    return frame
end

local collectorSection = mkSection("Collector")
local raritySection = mkSection("Rarity")
local trainingSection = mkSection("Training")
local safeSection = mkSection("Safe Zone")
local visualSection = mkSection("Visual")

local function showSection(name)
    for key, frame in pairs(sections) do
        frame.Visible = key == name
    end
    for key, btn in pairs(navButtons) do
        local active = key == name
        btn.BackgroundColor3 = active and Color3.fromRGB(44, 101, 94) or UI.card
        btn.TextColor3 = active and UI.text or UI.muted
        navAccents[key].Visible = active
    end
end

local function mkTab(name, y)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -16, 0, 34)
    btn.Position = UDim2.new(0, 8, 0, y)
    btn.BackgroundColor3 = UI.card
    btn.BorderSizePixel = 0
    btn.Text = name
    btn.TextColor3 = UI.muted
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.Parent = sidebar
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 7)
    local accent = Instance.new("Frame")
    accent.Size = UDim2.new(0, 3, 0, 18)
    accent.Position = UDim2.new(0, 0, 0.5, -9)
    accent.BackgroundColor3 = UI.cyan
    accent.BorderSizePixel = 0
    accent.Visible = false
    accent.Parent = btn
    navAccents[name] = accent
    local pad = Instance.new("UIPadding", btn)
    pad.PaddingLeft = UDim.new(0, 10)
    navButtons[name] = btn
    btn.MouseButton1Click:Connect(function()
        showSection(name)
    end)
    return btn
end

mkTab("Collector", 10)
mkTab("Rarity", 50)
mkTab("Training", 90)
mkTab("Safe Zone", 130)
mkTab("Visual", 170)

local function mkHeader(parent, title, subtitle)
    local h = Instance.new("TextLabel")
    h.Size = UDim2.new(1, 0, 0, 24)
    h.Position = UDim2.new(0, 0, 0, 0)
    h.BackgroundTransparency = 1
    h.Text = title
    h.TextColor3 = UI.text
    h.Font = Enum.Font.GothamBlack
    h.TextSize = 14
    h.TextXAlignment = Enum.TextXAlignment.Left
    h.Parent = parent

    local s = Instance.new("TextLabel")
    s.Size = UDim2.new(1, 0, 0, 18)
    s.Position = UDim2.new(0, 0, 0, 22)
    s.BackgroundTransparency = 1
    s.Text = subtitle
    s.TextColor3 = UI.muted
    s.Font = Enum.Font.Gotham
    s.TextSize = 11
    s.TextXAlignment = Enum.TextXAlignment.Left
    s.Parent = parent
end

local function mkBtn(parent, text, color, x, y, w)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, w or 154, 0, 32)
    btn.Position = UDim2.new(0, x, 0, y)
    btn.BackgroundColor3 = UI.button
    btn.BorderSizePixel = 0
    btn.Text = text
    btn.TextColor3 = color
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 11
    btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 7)
    local stroke = Instance.new("UIStroke", btn)
    stroke.Color = Color3.fromRGB(89, 100, 106)
    stroke.Thickness = 1
    return btn
end

mkHeader(collectorSection, "Auto Collector", "Collect selected rarity eggs only")
mkHeader(raritySection, "Rarity Select", "Choose which egg rarities Auto Collector can pick")
mkHeader(trainingSection, "Training x2", "Auto claim the x2 training bonus when it appears")
mkHeader(safeSection, "Safe Zone", "Return point after every pickup")
mkHeader(visualSection, "Visual", "Target ESP and scan tools")

selectedSummaryLbl = Instance.new("TextLabel")
selectedSummaryLbl.Size = UDim2.new(1, 0, 0, 36)
selectedSummaryLbl.Position = UDim2.new(0, 0, 0, 42)
selectedSummaryLbl.BackgroundTransparency = 1
selectedSummaryLbl.Text = selectedRarityText()
selectedSummaryLbl.TextColor3 = UI.muted
selectedSummaryLbl.Font = Enum.Font.Gotham
selectedSummaryLbl.TextSize = 11
selectedSummaryLbl.TextWrapped = true
selectedSummaryLbl.TextXAlignment = Enum.TextXAlignment.Left
selectedSummaryLbl.TextYAlignment = Enum.TextYAlignment.Top
selectedSummaryLbl.Parent = raritySection

rarityListFrame = Instance.new("ScrollingFrame")
rarityListFrame.Size = UDim2.new(1, 0, 0, 194)
rarityListFrame.Position = UDim2.new(0, 0, 0, 82)
rarityListFrame.BackgroundTransparency = 1
rarityListFrame.BorderSizePixel = 0
rarityListFrame.ScrollBarThickness = 3
rarityListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
rarityListFrame.Parent = raritySection

local function mkRarityButton(rarity, index)
    local col = (index - 1) % 2
    local row = math.floor((index - 1) / 2)
    local btn = mkBtn(rarityListFrame, rarity, rarityColor(rarity), col * 166, row * 38, 154)
    rarityButtons[rarity] = btn
    btn.MouseButton1Click:Connect(function()
        TARGET_RARITIES[rarity] = not TARGET_RARITIES[rarity]
        processed = {}
        getTargets()
        if espOn then
            clearESP()
            scanESP()
        end
        updateRarityButtons()
        setStatus("Rarity filter updated", UI.cyan)
    end)
    return btn
end

rebuildRarityButtons = function()
    for _, btn in pairs(rarityButtons) do
        btn:Destroy()
    end
    rarityButtons = {}

    for i, rarity in ipairs(RARITY_OPTIONS) do
        mkRarityButton(rarity, i)
    end

    if rarityListFrame then
        local rows = math.ceil(#RARITY_OPTIONS / 2)
        rarityListFrame.CanvasSize = UDim2.new(0, 0, 0, math.max(194, rows * 38))
    end

    updateRarityButtons()
end

rebuildRarityButtons()

local selectAllBtn = mkBtn(raritySection, "ALL", UI.green, 0, 286, 78)
local selectRareBtn = mkBtn(raritySection, "HIGH", UI.amber, 84, 286, 78)
rarerModeBtn = mkBtn(raritySection, "RARE FIRST ON", UI.muted, 168, 286, 102)
local clearRarityBtn = mkBtn(raritySection, "CLEAR", UI.red, 276, 286, 78)

selectAllBtn.MouseButton1Click:Connect(function()
    discoverMapRarities()
    for _, rarity in ipairs(RARITY_OPTIONS) do
        TARGET_RARITIES[rarity] = true
    end
    processed = {}
    getTargets()
    if espOn then
        clearESP()
        scanESP()
    end
    updateRarityButtons()
    setStatus("Selected all rarity eggs", UI.green)
end)

selectRareBtn.MouseButton1Click:Connect(function()
    discoverMapRarities()
    local matched = false
    for _, rarity in ipairs(RARITY_OPTIONS) do
        local active = isHighRarityName(rarity) == true
        TARGET_RARITIES[rarity] = active
        matched = matched or active
    end
    processed = {}
    getTargets()
    if espOn then
        clearESP()
        scanESP()
    end
    updateRarityButtons()
    if matched then
        setStatus("Selected high rarity eggs", UI.amber)
    else
        setStatus("No known high names in this map. Select manually.", UI.amber)
    end
end)

rarerModeBtn.MouseButton1Click:Connect(function()
    rareFirstOn = not rareFirstOn
    processed = {}
    getTargets()
    if espOn then
        clearESP()
        scanESP()
    end
    updateRarityButtons()
    setStatus(rareFirstOn and "Selected eggs: rare first" or "Selected eggs: nearest first", rareFirstOn and UI.green or UI.muted)
end)

clearRarityBtn.MouseButton1Click:Connect(function()
    discoverMapRarities()
    for _, rarity in ipairs(RARITY_OPTIONS) do
        TARGET_RARITIES[rarity] = false
    end
    processed = {}
    getTargets()
    if espOn then
        clearESP()
        scanESP()
    end
    updateRarityButtons()
    setStatus("Rarity selection cleared", UI.red)
end)

statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(1, 0, 0, 42)
statusLbl.Position = UDim2.new(0, 0, 0, 46)
statusLbl.BackgroundTransparency = 1
statusLbl.Text = "Ready"
statusLbl.TextColor3 = UI.muted
statusLbl.Font = Enum.Font.Gotham
statusLbl.TextSize = 11
statusLbl.TextWrapped = true
statusLbl.TextYAlignment = Enum.TextYAlignment.Top
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.Parent = collectorSection

countLbl = Instance.new("TextLabel")
countLbl.Size = UDim2.new(1, 0, 0, 22)
countLbl.Position = UDim2.new(0, 0, 0, 92)
countLbl.BackgroundTransparency = 1
countLbl.TextColor3 = UI.text
countLbl.Font = Enum.Font.GothamSemibold
countLbl.TextSize = 11
countLbl.TextXAlignment = Enum.TextXAlignment.Left
countLbl.Parent = collectorSection

autoBtn = mkBtn(collectorSection, "AUTO COLLECT: OFF", UI.amber, 0, 128, 154)
local onceBtn = mkBtn(collectorSection, "COLLECT ONCE", UI.cyan, 166, 128, 154)
deepScanBtn = mkBtn(collectorSection, "LONG RANGE: ON", UI.green, 0, 250, 154)
local deepOnceBtn = mkBtn(collectorSection, "RESCAN FAR", UI.cyan, 166, 250, 154)

local delayFrame = Instance.new("Frame")
delayFrame.Size = UDim2.new(1, 0, 0, 58)
delayFrame.Position = UDim2.new(0, 0, 0, 178)
delayFrame.BackgroundTransparency = 1
delayFrame.Parent = collectorSection

local delayLbl = Instance.new("TextLabel")
delayLbl.Size = UDim2.new(0.6, 0, 0, 18)
delayLbl.BackgroundTransparency = 1
delayLbl.Text = "Loop Delay"
delayLbl.TextColor3 = UI.muted
delayLbl.Font = Enum.Font.Gotham
delayLbl.TextSize = 11
delayLbl.TextXAlignment = Enum.TextXAlignment.Left
delayLbl.Parent = delayFrame

delayValueLbl = Instance.new("TextLabel")
delayValueLbl.Size = UDim2.new(0.4, 0, 0, 18)
delayValueLbl.Position = UDim2.new(0.6, 0, 0, 0)
delayValueLbl.BackgroundTransparency = 1
delayValueLbl.Text = string.format("%.1fs", autoDelay)
delayValueLbl.TextColor3 = UI.cyan
delayValueLbl.Font = Enum.Font.GothamBold
delayValueLbl.TextSize = 11
delayValueLbl.TextXAlignment = Enum.TextXAlignment.Right
delayValueLbl.Parent = delayFrame

local delayTrack = Instance.new("Frame")
delayTrack.Size = UDim2.new(1, 0, 0, 10)
delayTrack.Position = UDim2.new(0, 0, 0, 30)
delayTrack.BackgroundColor3 = UI.button
delayTrack.BorderSizePixel = 0
delayTrack.Parent = delayFrame
Instance.new("UICorner", delayTrack).CornerRadius = UDim.new(1, 0)

local delayFill = Instance.new("Frame")
delayFill.Size = UDim2.new((autoDelay - 0.6) / 4.4, 0, 1, 0)
delayFill.BackgroundColor3 = UI.cyan
delayFill.BorderSizePixel = 0
delayFill.Parent = delayTrack
Instance.new("UICorner", delayFill).CornerRadius = UDim.new(1, 0)

local delayKnob = Instance.new("TextButton")
delayKnob.Size = UDim2.new(0, 18, 0, 18)
delayKnob.Position = UDim2.new((autoDelay - 0.6) / 4.4, -9, 0.5, -9)
delayKnob.BackgroundColor3 = UI.text
delayKnob.BorderSizePixel = 0
delayKnob.Text = ""
delayKnob.Parent = delayTrack
Instance.new("UICorner", delayKnob).CornerRadius = UDim.new(1, 0)

do
    local dragging = false
    local function setDelay(rx)
        local r = math.clamp(rx, 0, 1)
        autoDelay = 0.6 + r * 4.4
        delayFill.Size = UDim2.new(r, 0, 1, 0)
        delayKnob.Position = UDim2.new(r, -9, 0.5, -9)
        delayValueLbl.Text = string.format("%.1fs", autoDelay)
    end
    delayKnob.MouseButton1Down:Connect(function()
        dragging = true
    end)
    UIS.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            setDelay((input.Position.X - delayTrack.AbsolutePosition.X) / delayTrack.AbsoluteSize.X)
        end
    end)
end

trainingStatusLbl = Instance.new("TextLabel")
trainingStatusLbl.Size = UDim2.new(1, 0, 0, 42)
trainingStatusLbl.Position = UDim2.new(0, 0, 0, 48)
trainingStatusLbl.BackgroundTransparency = 1
trainingStatusLbl.TextColor3 = UI.muted
trainingStatusLbl.Font = Enum.Font.Gotham
trainingStatusLbl.TextSize = 11
trainingStatusLbl.TextWrapped = true
trainingStatusLbl.TextXAlignment = Enum.TextXAlignment.Left
trainingStatusLbl.TextYAlignment = Enum.TextYAlignment.Top
trainingStatusLbl.Parent = trainingSection

trainingBtn = mkBtn(trainingSection, "AUTO TRAIN X2: OFF", UI.amber, 0, 104, 154)
local trainingOnceBtn = mkBtn(trainingSection, "CLAIM X2 NOW", UI.cyan, 166, 104, 154)

safeLbl = Instance.new("TextLabel")
safeLbl.Size = UDim2.new(1, 0, 0, 36)
safeLbl.Position = UDim2.new(0, 0, 0, 48)
safeLbl.BackgroundTransparency = 1
safeLbl.TextColor3 = UI.muted
safeLbl.Font = Enum.Font.Gotham
safeLbl.TextSize = 11
safeLbl.TextWrapped = true
safeLbl.TextXAlignment = Enum.TextXAlignment.Left
safeLbl.Parent = safeSection

local setSafeBtn = mkBtn(safeSection, "SET SAFE ZONE", UI.green, 0, 98, 154)
local returnSafeBtn = mkBtn(safeSection, "RETURN SAFE", UI.cyan, 166, 98, 154)

local safeHelp = Instance.new("TextLabel")
safeHelp.Size = UDim2.new(1, 0, 0, 62)
safeHelp.Position = UDim2.new(0, 0, 0, 148)
safeHelp.BackgroundTransparency = 1
safeHelp.Text = "Default safe zone is your position when this script starts. Stand in your safe area and press SET SAFE ZONE to update it."
safeHelp.TextColor3 = UI.muted
safeHelp.Font = Enum.Font.Gotham
safeHelp.TextSize = 11
safeHelp.TextWrapped = true
safeHelp.TextYAlignment = Enum.TextYAlignment.Top
safeHelp.TextXAlignment = Enum.TextXAlignment.Left
safeHelp.Parent = safeSection

espBtn = mkBtn(visualSection, "ESP: OFF", UI.cyan, 0, 48, 154)
local rescanBtn = mkBtn(visualSection, "RESCAN", UI.text, 166, 48, 154)

local visualInfo = Instance.new("TextLabel")
visualInfo.Size = UDim2.new(1, 0, 0, 92)
visualInfo.Position = UDim2.new(0, 0, 0, 100)
visualInfo.BackgroundTransparency = 1
visualInfo.Text = "ESP marks only fresh target eggs. Collected, carried, placed, inventory, backpack and character eggs are ignored."
visualInfo.TextColor3 = UI.muted
visualInfo.Font = Enum.Font.Gotham
visualInfo.TextSize = 11
visualInfo.TextWrapped = true
visualInfo.TextYAlignment = Enum.TextYAlignment.Top
visualInfo.TextXAlignment = Enum.TextXAlignment.Left
visualInfo.Parent = visualSection

local function updateAutoButton()
    autoBtn.Text = autoOn and "AUTO COLLECT: ON" or "AUTO COLLECT: OFF"
    autoBtn.TextColor3 = autoOn and UI.text or UI.amber
    autoBtn.BackgroundColor3 = autoOn and Color3.fromRGB(125, 82, 26) or UI.button
end

local function updateDeepScanButton()
    if not deepScanBtn then return end
    deepScanBtn.Text = longRangeOn and "LONG RANGE: ON" or "LONG RANGE: OFF"
    deepScanBtn.TextColor3 = longRangeOn and UI.text or UI.muted
    deepScanBtn.BackgroundColor3 = longRangeOn and Color3.fromRGB(18, 72, 92) or UI.button
end

local function updateESPButton()
    espBtn.Text = espOn and "ESP: ON" or "ESP: OFF"
    espBtn.TextColor3 = espOn and UI.text or UI.cyan
    espBtn.BackgroundColor3 = espOn and Color3.fromRGB(18, 72, 92) or UI.button
end

iconBtn.MouseButton1Click:Connect(function()
    panel.Visible = not panel.Visible
    iconBtn.BackgroundColor3 = panel.Visible and Color3.fromRGB(44, 101, 94) or UI.button
end)

autoBtn.MouseButton1Click:Connect(function()
    autoOn = not autoOn
    updateAutoButton()
    if autoOn then
        setStatus(hasSelectedRarity() and "Auto collector running" or "Waiting for a selected rarity", hasSelectedRarity() and UI.green or UI.amber)
        autoLoop()
    else
        setStatus("Auto collector stopped", UI.muted)
    end
end)

onceBtn.MouseButton1Click:Connect(function()
    if not collectBusy then
        collectBest()
    end
end)

deepScanBtn.MouseButton1Click:Connect(function()
    longRangeOn = not longRangeOn
    updateDeepScanButton()
    setStatus(longRangeOn and "Loaded map scan: all distances" or "Loaded map scan: within 250 studs", longRangeOn and UI.green or UI.muted)
end)

deepOnceBtn.MouseButton1Click:Connect(function()
    if not collectBusy then
        discoverMapRarities()
        getTargets()
        if espOn then
            clearESP()
            scanESP()
        end
        setStatus("Rescanned loaded map with long range", UI.cyan)
    end
end)

trainingBtn.MouseButton1Click:Connect(function()
    trainingX2On = not trainingX2On
    updateTrainingButton()
    updateTrainingStatus()
    if trainingX2On then
        trainingStatus("Waiting for next x2 bonus", UI.green)
        trainingX2Loop()
    else
        trainingLoopGeneration = trainingLoopGeneration + 1
        trainingStatus("Auto training x2 stopped", UI.muted)
    end
end)

trainingOnceBtn.MouseButton1Click:Connect(function()
    claimTrainingX2()
end)

setSafeBtn.MouseButton1Click:Connect(function()
    if captureSafeZone() then
        updateSafeLabel()
        setStatus("Safe zone updated", UI.green)
    else
        setStatus("Cannot set safe zone: character missing", UI.red)
    end
end)

returnSafeBtn.MouseButton1Click:Connect(function()
    if returnToSafe() then
        setStatus("Returned to safe zone", UI.green)
    else
        setStatus("Safe zone not set", UI.red)
    end
end)

espBtn.MouseButton1Click:Connect(function()
    espOn = not espOn
    if espOn then
        scanESP()
    else
        clearESP()
    end
    updateESPButton()
end)

rescanBtn.MouseButton1Click:Connect(function()
    processed = {}
    discoverMapRarities()
    getTargets()
    if espOn then
        clearESP()
        scanESP()
    end
    setStatus("Rescanned targets", UI.cyan)
end)

local descendantConnection = WS.DescendantAdded:Connect(function(inst)
    local spawnedItems = WS:FindFirstChild("SpawnedItems")
    if not spawnedItems or not inst:IsDescendantOf(spawnedItems) then return end
    task.wait(0.1)
    if not runtime.active then return end
    local eggInst = inst
    while eggInst and eggInst.Parent ~= spawnedItems do
        eggInst = eggInst.Parent
    end
    if not eggInst or not isSpawnedEgg(eggInst) then return end

    local previousCount = #RARITY_OPTIONS
    resolveInfo(eggInst)
    if rebuildRarityButtons and #RARITY_OPTIONS ~= previousCount then
        rebuildRarityButtons()
    end
    if espOn and isTargetEgg(eggInst) then
        attachESP(eggInst)
    end
    if autoOn and hasSelectedRarity() and not collectBusy and isTargetEgg(eggInst) then
        collectBest()
    end
end)
table.insert(runtime.connections, descendantConnection)

local characterConnection = player.CharacterAdded:Connect(function()
    task.wait(0.75)
    if not runtime.active then return end
    if not safeCFrame then
        captureSafeZone()
    end
    updateSafeLabel()
end)
table.insert(runtime.connections, characterConnection)

showSection("Collector")
local scanOk, scanErr = pcall(discoverMapRarities)
if not scanOk then
    warn("[VANTA V2] Initial egg scan failed:", scanErr)
    setStatus("Egg scan failed; check executor output", UI.red)
end
updateAutoButton()
updateDeepScanButton()
updateESPButton()
updateTrainingButton()
updateTrainingStatus()
updateRarityButtons()
updateSafeLabel()
updateCountLabel()
local targetsOk, targetsErr = pcall(getTargets)
if not targetsOk then
    warn("[VANTA V2] Initial target scan failed:", targetsErr)
    setStatus("Target scan failed; check executor output", UI.red)
end
hookTrainingBonusRemote()
if legacyAutoRunning then
    setStatus("Another egg auto is still ON. Turn it OFF in its GUI or rejoin.", UI.red)
elseif scanOk and targetsOk then
    setStatus("Waiting for a selected rarity", UI.muted)
end
warn("[VANTA V2] GUI ready in PlayerGui. Select a rarity and enable Auto Collect.")
