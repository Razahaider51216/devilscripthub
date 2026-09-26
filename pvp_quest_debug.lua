-- Stationary, one-shot quest diagnostic for PlaceId 99046552174353.
-- Only reads replicated data and invokes read-only service methods.

if game.PlaceId ~= 99046552174353 then warn("[QuestDebug] Wrong place"); return end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local WS = game:GetService("Workspace")
local player = Players.LocalPlayer
if not player then warn("[QuestDebug] LocalPlayer unavailable"); return end

local env = type(getgenv) == "function" and getgenv() or _G
local lines = {}
local started = os.clock()

local function add(value)
    lines[#lines + 1] = "-- " .. tostring(value)
end

local function section(name)
    add("")
    add("[[ " .. name .. " ]]")
end

local function pathOf(inst)
    if not inst then return "missing" end
    local ok, path = pcall(function() return inst:GetFullName() end)
    return ok and path or inst.Name
end

local function repr(value, depth, seen)
    depth, seen = depth or 0, seen or {}
    local kind = typeof(value)
    if kind == "Instance" then return "<" .. pathOf(value) .. ">" end
    if kind == "Vector3" then return string.format("(%.1f, %.1f, %.1f)", value.X, value.Y, value.Z) end
    if kind == "string" then return string.format("%q", value:sub(1, 300)) end
    if kind ~= "table" then return tostring(value) end
    if seen[value] or depth >= 5 then return "{...}" end
    seen[value] = true
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for i, key in ipairs(keys) do
        if i > 60 then parts[#parts + 1] = "..."; break end
        parts[#parts + 1] = "[" .. repr(key, depth + 1, seen) .. "]=" .. repr(value[key], depth + 1, seen)
    end
    seen[value] = nil
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function attrs(inst)
    local ok, value = pcall(function() return inst:GetAttributes() end)
    return ok and repr(value) or "{}"
end

local function child(root, ...)
    local current = root
    for _, name in ipairs({ ... }) do current = current and current:FindFirstChild(name) end
    return current
end

local function position(inst)
    if not inst then return nil end
    if inst:IsA("BasePart") then return inst.Position end
    if inst:IsA("Attachment") then return inst.WorldPosition end
    if inst:IsA("Model") then
        local part = inst:FindFirstChild("HumanoidRootPart") or inst.PrimaryPart
        if part then return part.Position end
        local ok, pivot = pcall(function() return inst:GetPivot() end)
        if ok then return pivot.Position end
    end
    return nil
end

local function timed(fn, seconds)
    local done, ok, result = false, false, nil
    task.spawn(function()
        ok, result = pcall(fn)
        done = true
    end)
    local deadline = os.clock() + seconds
    while not done and os.clock() < deadline do task.wait(0.05) end
    if not done then return false, "timeout after " .. seconds .. "s" end
    return ok, result
end

local function readModule(root, ...)
    local module = child(root, ...)
    if not module or not module:IsA("ModuleScript") then return nil, "module missing" end
    local ok, value = timed(function() return require(module) end, 5)
    if ok then return value, nil end
    return nil, value
end

local services = child(RS, "Packages", "Knit", "Services")
local database = RS:FindFirstChild("Database")
local islands = child(WS, "_Map", "Islands")
local enemies = WS:FindFirstChild("Enemies")
local root = child(player.Character, "HumanoidRootPart")
local origin = root and root.Position
local stats = player:FindFirstChild("Leaderstats") or player:FindFirstChild("leaderstats")
local levelValue = stats and stats:FindFirstChild("Level")
local level = levelValue and tonumber(levelValue.Value) or nil

local function readRemote(service, method, ...)
    local remote = child(services, service, "RF", method)
    if not remote or not remote:IsA("RemoteFunction") then return false, "remote missing" end
    local args = table.pack(...)
    return timed(function() return remote:InvokeServer(table.unpack(args, 1, args.n)) end, 5)
end

add("PvP Quest Acceptance Diagnostic")
add("Captured=" .. os.date("%Y-%m-%d %H:%M:%S") .. " PlaceId=" .. game.PlaceId)
add("Read-only: no teleport, NPC interaction, quest acceptance, attack, purchase, or input.")

section("PLAYER AND CURRENT FARM")
add("Name=" .. player.Name .. " UserId=" .. player.UserId .. " Level=" .. tostring(level)
    .. " Position=" .. repr(origin) .. " attrs=" .. attrs(player))
local farm = env.VANTA_PvPFarm
if type(farm) == "table" then
    add("Farm alive=" .. tostring(farm.alive) .. " quests=" .. tostring(farm.quests)
        .. " combat=" .. tostring(farm.combat) .. " mode=" .. tostring(farm.mode)
        .. " lastQuestAction=" .. tostring(farm.lastQuestAction))
else
    add("Farm state unavailable")
end

section("READ-ONLY SERVER STATE")
local questOk, questStates = readRemote("QuestService", "GetQuests")
add("GetQuests ok=" .. tostring(questOk) .. " result=" .. repr(questStates):sub(1, 50000))
local zoneOk, zones = readRemote("ZoneHandler", "GetZones")
add("GetZones ok=" .. tostring(zoneOk) .. " result=" .. repr(zones):sub(1, 30000))
if not questOk or type(questStates) ~= "table" then questStates = {} end
if not zoneOk or type(zones) ~= "table" then zones = {} end

local questData, questErr = readModule(database, "QuestInfo", "KillQuestRepeatables")
local zoneData, zoneErr = readModule(database, "Zones")
add("Quest module=" .. (questData and "loaded" or tostring(questErr)))
add("Zone module=" .. (zoneData and "loaded" or tostring(zoneErr)))
if type(questData) ~= "table" then questData = {} end
if type(zoneData) ~= "table" then zoneData = {} end

section("LIVE ENEMIES")
local mobs = {}
if enemies then
    for _, inst in ipairs(enemies:GetChildren()) do
        if inst:IsA("Model") then
            local humanoid = inst:FindFirstChildOfClass("Humanoid")
            local mobLevel = tonumber(inst:GetAttribute("Level"))
            if humanoid and humanoid.Health > 0 and not inst:GetAttribute("IsBoss") then
                local entry = mobs[inst.Name]
                if not entry then
                    entry = { count = 0, level = mobLevel or 0, nearest = math.huge,
                        eligibleLevel = nil, nearestEligible = math.huge }
                    mobs[inst.Name] = entry
                end
                entry.count = entry.count + 1
                entry.level = math.max(entry.level, mobLevel or 0)
                local pos = position(inst)
                if pos and origin then entry.nearest = math.min(entry.nearest, (pos - origin).Magnitude) end
                if level and mobLevel and mobLevel <= level + 25 and pos and origin then
                    local distance = (pos - origin).Magnitude
                    if distance < entry.nearestEligible then
                        entry.nearestEligible = distance
                        entry.eligibleLevel = mobLevel
                    end
                end
            end
        end
    end
end
local mobNames = {}
for name in pairs(mobs) do mobNames[#mobNames + 1] = name end
table.sort(mobNames)
for _, name in ipairs(mobNames) do
    local entry = mobs[name]
    add(name .. " count=" .. entry.count .. " maxLevel=" .. entry.level
        .. " nearest=" .. (entry.nearest < math.huge and string.format("%.1f", entry.nearest) or "unknown")
        .. " nearestEligibleLevel=" .. tostring(entry.eligibleLevel))
end

section("ALL LOADED REPEATABLE QUEST NPCS")
local candidates = {}
for id, config in pairs(questData) do
    if type(config) == "table" and type(config.EnemyType) == "string" then
        local npc = islands and islands:FindFirstChild(id, true) or nil
        if npc and npc:IsA("Model") then
            local island = npc
            while island and island.Parent ~= islands do island = island.Parent end
            local islandName = island and island.Name or "unknown"
            local prompt = npc:FindFirstChildWhichIsA("ProximityPrompt", true)
            local pos = position(npc)
            local distance = origin and pos and (pos - origin).Magnitude or math.huge
            local mob = mobs[config.EnemyType]
            local eligibleMob = mob and mob.eligibleLevel ~= nil
            local first = type(config.Quests) == "table" and config.Quests[1] or nil
            candidates[#candidates + 1] = {
                id = id, config = config, npc = npc, island = islandName, prompt = prompt,
                pos = pos, distance = distance, mob = mob, eligibleMob = eligibleMob,
                first = first, state = questStates[id],
            }
        end
    end
end
table.sort(candidates, function(a, b)
    if a.distance ~= b.distance then return a.distance < b.distance end
    return a.id < b.id
end)
add("Loaded repeatable NPCs=" .. #candidates .. " / quest definitions=" .. (function()
    local n = 0
    for _ in pairs(questData) do n = n + 1 end
    return n
end)())
for i, c in ipairs(candidates) do
    local unlocked = type(zones.Unlocked) == "table" and zones.Unlocked[c.island]
    local prompt = c.prompt
    add(string.format("%02d %s island=%s unlocked=%s npc=%s pos=%s distance=%s enemy=%s mobLevel=%s mobCount=%s eligibleMob=%s state=%s",
        i, c.id, c.island, tostring(unlocked), pathOf(c.npc), repr(c.pos),
        c.distance < math.huge and string.format("%.1f", c.distance) or "unknown",
        c.config.EnemyType, tostring(c.mob and c.mob.level), tostring(c.mob and c.mob.count),
        tostring(c.eligibleMob), repr(c.state)))
    add("  recommendedLevel=" .. tostring(c.config.RecommendedLevel)
        .. " repeatable=" .. tostring(c.config.Repeatable)
        .. " abortSimilar=" .. tostring(c.config.AbortSimilarQuestsID)
        .. " requirement=" .. repr(c.first and c.first.Requirement)
        .. " dialogueRequirement=" .. repr(c.first and c.first.DialogueRequirement)
        .. " manualClaim=" .. tostring(c.first and c.first.ManualClaim))
    add("  prompt=" .. pathOf(prompt) .. " action=" .. (prompt and repr(prompt.ActionText) or "nil")
        .. " enabled=" .. tostring(prompt and prompt.Enabled)
        .. " maxDistance=" .. tostring(prompt and prompt.MaxActivationDistance)
        .. " npcAttrs=" .. attrs(c.npc))
    if i % 25 == 0 then task.wait() end
end

section("WHAT THE CURRENT FARM WOULD SELECT")
local best = nil
for _, c in ipairs(candidates) do
    if c.eligibleMob and type(zones.Unlocked) == "table" and zones.Unlocked[c.island] then
        if not best or c.mob.eligibleLevel > best.mob.eligibleLevel then best = c end
    end
end
add("Chosen=" .. (best and best.id or "none") .. " (highest loaded eligible mob level in an unlocked island)")
if best then
    add("Chosen state=" .. repr(best.state) .. " requirement=" .. repr(best.first and best.first.Requirement)
        .. " dialogueRequirement=" .. repr(best.first and best.first.DialogueRequirement))
end

section("GET QUEST AVAILABILITY - READ-ONLY")
local probes, seen = {}, {}
local function enqueue(c)
    if c and not seen[c.id] and #probes < 24 then
        seen[c.id] = true
        probes[#probes + 1] = c
    end
end
enqueue(best)
for _, c in ipairs(candidates) do
    if c.state and c.state.Ongoing then enqueue(c) end
end
for _, c in ipairs(candidates) do
    if c.eligibleMob and type(zones.Unlocked) == "table" and zones.Unlocked[c.island] then enqueue(c) end
end
for _, c in ipairs(candidates) do enqueue(c) end
add("Probing " .. #probes .. " NPC ids, one argument each; no TalkToNPC/AcceptQuest calls.")
for _, c in ipairs(probes) do
    local ok, result = readRemote("QuestService", "GetQuestAvailability", c.id)
    add(c.id .. " ok=" .. tostring(ok) .. " type=" .. typeof(result) .. " result=" .. repr(result))
    task.wait(0.1)
end

section("ZONE REQUIREMENTS")
local data = zoneData.ZoneData
if type(data) == "table" then
    local names = {}
    for name in pairs(data) do names[#names + 1] = name end
    table.sort(names, function(a, b) return tostring(a) < tostring(b) end)
    for _, name in ipairs(names) do
        if islands and islands:FindFirstChild(name) then
            local entry = data[name]
            add(tostring(name) .. " unlocked=" .. tostring(zones.Unlocked and zones.Unlocked[name])
                .. " level=" .. repr(entry.Level) .. " requirements=" .. repr(entry.Requirements)
                .. " areaTeleports=" .. repr(entry.AreaTeleports):sub(1, 2500))
        end
    end
end

section("QUEST UI")
local gui = player:FindFirstChild("PlayerGui")
local count = 0
if gui then
    for i, inst in ipairs(gui:GetDescendants()) do
        if inst:IsA("TextLabel") or inst:IsA("TextButton") then
            local name = pathOf(inst):lower()
            if name:find("quest", 1, true) and inst.Text ~= "" then
                count = count + 1
                if count <= 35 then add(pathOf(inst) .. " visible=" .. tostring(inst.Visible) .. " text=" .. repr(inst.Text)) end
            end
        end
        if i % 250 == 0 then task.wait() end
    end
end
add("Quest UI text entries=" .. count)

add("")
add("Elapsed=" .. string.format("%.1fs", os.clock() - started))
local dump = table.concat(lines, "\n")
env.VANTA_PvPQuestDebugText = dump
local clipboard = setclipboard or toclipboard or set_clipboard
if type(clipboard) == "function" then
    local ok, err = pcall(clipboard, dump)
    if ok then
        print("[QuestDebug] Copied " .. #dump .. " bytes. Paste the text here.")
    else
        warn("[QuestDebug] Clipboard failed: " .. tostring(err))
    end
else
    warn("[QuestDebug] Clipboard unavailable; text is in getgenv().VANTA_PvPQuestDebugText")
end
