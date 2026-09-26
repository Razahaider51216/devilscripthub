-- Focused, one-shot progression diagnostic. No remote hooks or gameplay actions.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local WS = game:GetService("Workspace")
local player = Players.LocalPlayer
if not player then warn("[PvPProgress] LocalPlayer unavailable"); return end

local env = type(getgenv) == "function" and getgenv() or _G
local lines = {}
local started = os.clock()

local function add(value)
    table.insert(lines, "-- " .. tostring(value))
end

local function pathOf(inst)
    return inst and inst:GetFullName() or "missing"
end

local function serialize(value, depth, seen)
    depth, seen = depth or 0, seen or {}
    local kind = typeof(value)
    if kind == "Instance" then return "<" .. pathOf(value) .. ">" end
    if kind == "Vector3" then return string.format("(%.1f, %.1f, %.1f)", value.X, value.Y, value.Z) end
    if kind == "string" then return string.format("%q", value:sub(1, 250)) end
    if kind ~= "table" then return tostring(value) end
    if depth >= 5 or seen[value] then return "{...}" end
    seen[value] = true
    local items, count = {}, 0
    for key, item in pairs(value) do
        count = count + 1
        if count > 100 then table.insert(items, "..."); break end
        table.insert(items, "[" .. serialize(key, depth + 1, seen) .. "]=" .. serialize(item, depth + 1, seen))
    end
    seen[value] = nil
    return "{" .. table.concat(items, ", ") .. "}"
end

local function attrs(inst)
    local ok, result = pcall(function() return inst:GetAttributes() end)
    return ok and serialize(result) or "{}"
end

local function timed(fn, seconds)
    local done, ok, result = false, false, nil
    task.spawn(function()
        ok, result = pcall(fn)
        done = true
    end)
    local deadline = os.clock() + seconds
    while not done and os.clock() < deadline do task.wait(0.1) end
    if not done then return false, "timeout after " .. seconds .. "s" end
    return ok, result
end

local function section(name)
    add("")
    add("[[ " .. name .. " ]]")
end

local function getChild(root, names)
    local current = root
    for _, name in ipairs(names) do
        current = current and current:FindFirstChild(name)
    end
    return current
end

add("PvP Quest and Combat Progression Diagnostic")
add("Captured=" .. os.date("%Y-%m-%d %H:%M:%S") .. " PlaceId=" .. game.PlaceId)
add("No attack, quest acceptance, teleport, or purchase is performed by this diagnostic.")

section("PLAYER")
local level = getChild(player, { "Leaderstats", "Level" }) or getChild(player, { "leaderstats", "Level" })
local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
add("Name=" .. player.Name .. " UserId=" .. player.UserId .. " Level=" .. (level and tostring(level.Value) or "unknown"))
add("Position=" .. (root and serialize(root.Position) or "unknown") .. " attrs=" .. attrs(player))

section("CURRENT QUEST UI")
local playerGui = player:FindFirstChild("PlayerGui")
if playerGui then
    local count = 0
    for i, inst in ipairs(playerGui:GetDescendants()) do
        if inst:IsA("TextLabel") or inst:IsA("TextButton") then
            local text = inst.Text
            local path = pathOf(inst):lower()
            if text ~= "" and (path:find("quest", 1, true) or path:find("trackedquest", 1, true)) then
                count = count + 1
                if count <= 100 then add(pathOf(inst) .. " = " .. serialize(text)) end
            end
        end
        if i % 200 == 0 then task.wait() end
    end
    add("Quest UI entries=" .. count)
end

section("LIVE READ-ONLY SERVICE RESPONSES")
local services = getChild(RS, { "Packages", "Knit", "Services" })
for _, probe in ipairs({
    { "QuestService", "GetQuests" },
    { "ZoneHandler", "GetZones" },
    { "EquipmentService", "GetEquipmentData" },
}) do
    local remote = services and getChild(services, { probe[1], "RF", probe[2] })
    if remote and remote:IsA("RemoteFunction") then
        local ok, result = timed(function() return remote:InvokeServer() end, 8)
        add(probe[1] .. "." .. probe[2] .. " ok=" .. tostring(ok) .. " result=" .. serialize(result):sub(1, 85000))
    else
        add(probe[1] .. "." .. probe[2] .. " missing")
    end
end

section("QUEST AND ZONE DATA TABLES")
local database = RS:FindFirstChild("Database")
for _, names in ipairs({
    { "QuestInfo", "KillQuestRepeatables" },
    { "QuestInfo", "Main_IGNORE" },
    { "Zones" },
}) do
    local module = database and getChild(database, names)
    local name = table.concat(names, ".")
    if module and module:IsA("ModuleScript") then
        local ok, result = timed(function() return require(module) end, 8)
        add(name .. " ok=" .. tostring(ok) .. " data=" .. serialize(result):sub(1, 100000))
    else
        add(name .. " missing")
    end
end

section("LIVE ENEMIES BY TYPE AND LEVEL")
local groups = {}
local enemyFolder = WS:FindFirstChild("Enemies")
if enemyFolder then
    for _, inst in ipairs(enemyFolder:GetChildren()) do
        if inst:IsA("Model") then
            local mobLevel = inst:GetAttribute("Level")
            local key = inst.Name .. " Lv." .. tostring(mobLevel or "?")
            local entry = groups[key]
            if not entry then
                entry = { count = 0, exp = inst:GetAttribute("Exp"), damage = inst:GetAttribute("Damage"), positions = {} }
                groups[key] = entry
            end
            entry.count = entry.count + 1
            if #entry.positions < 3 then
                local ok, pivot = pcall(function() return inst:GetPivot() end)
                if ok then table.insert(entry.positions, serialize(pivot.Position)) end
            end
        end
    end
end
for key, entry in pairs(groups) do
    add(key .. " count=" .. entry.count .. " exp=" .. tostring(entry.exp) .. " damage=" .. tostring(entry.damage)
        .. " positions=" .. table.concat(entry.positions, " | "))
end

section("ZONES AND WAYPOINTS")
local islands = getChild(WS, { "_Map", "Islands" })
if islands then
    for _, island in ipairs(islands:GetChildren()) do
        if island:IsA("Model") or island:IsA("Folder") then
            local waypoint = island:FindFirstChild("Waypoint_" .. island.Name)
            add(island.Name .. " attrs=" .. attrs(island) .. " waypoint=" .. pathOf(waypoint))
        end
    end
end

section("CLIENT CALL SITES")
local controllers = RS:FindFirstChild("ClientControllers")
local patterns = {
    "RegisterAttack", "EnemyDamage", "WeaponDamage", "ExecuteSkill", "SkillDamage",
    "AcceptQuest", "CompleteQuest", "GetQuests", "GetQuestAvailability", "TalkToNPC",
    "GetZones", "SetSpawnPoint", "AttemptDiscoverZone", "TeleportToWorld",
}
local targets = {
    { "CharacterController" }, { "EnemyController" }, { "SkillController" },
    { "UIController", "Quests" }, { "DialogueController" }, { "ZoneController" },
}
if type(decompile) ~= "function" then
    add("Executor has no decompile() API; signatures cannot be inferred from names alone.")
else
    for _, names in ipairs(targets) do
        local module = controllers and getChild(controllers, names)
        local name = table.concat(names, ".")
        if module and module:IsA("ModuleScript") then
            print("[PvPProgress] Inspecting " .. name)
            local ok, source = timed(function() return decompile(module) end, 12)
            if not ok or type(source) ~= "string" then
                add(name .. " decompile=" .. tostring(source))
            else
                local sourceLines = string.split(source, "\n")
                local chosen, keep = {}, {}
                for i, line in ipairs(sourceLines) do
                    for _, pattern in ipairs(patterns) do
                        if line:find(pattern, 1, true) then
                            for j = math.max(1, i - 4), math.min(#sourceLines, i + 5) do keep[j] = true end
                            break
                        end
                    end
                end
                for i, line in ipairs(sourceLines) do
                    if keep[i] then
                        table.insert(chosen, string.format("%d: %s", i, line))
                        if #chosen >= 350 then break end
                    end
                end
                add(name .. " sourceLines=" .. #sourceLines .. " matchedLines=" .. #chosen)
                if #chosen == 0 then add("  no matching call sites in this module") end
                for _, line in ipairs(chosen) do add("  " .. line:sub(1, 300)) end
            end
        else
            add(name .. " missing")
        end
        task.wait()
    end
end

add("")
add("Elapsed=" .. string.format("%.1fs", os.clock() - started))
local dump = table.concat(lines, "\n")
env.VANTA_PvPProgressDump = dump
local clipboard = setclipboard or toclipboard or set_clipboard
if type(clipboard) == "function" then
    local ok, err = pcall(clipboard, dump)
    if ok then
        print("[PvPProgress] Copied " .. #dump .. " bytes. Send the pasted text.")
    else
        warn("[PvPProgress] Clipboard failed: " .. tostring(err))
    end
else
    warn("[PvPProgress] Clipboard unavailable; dump stored in getgenv().VANTA_PvPProgressDump")
end
