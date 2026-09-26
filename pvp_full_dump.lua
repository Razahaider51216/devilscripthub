-- Client-visible place dump and structured PvP manifest. No movement or gameplay inputs.
-- UniversalSynSaveInstance https://discord.gg/wx4ThpAsmw

if game.PlaceId ~= 99046552174353 then
    warn("[PvPFullDump] Wrong place: " .. tostring(game.PlaceId))
    return
end

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local WS = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
local env = type(getgenv) == "function" and getgenv() or _G
local stamp = os.date("%Y%m%d_%H%M%S")
local prefix = "PvP_" .. tostring(game.PlaceId) .. "_" .. stamp
local manifestPath = prefix .. "_manifest.json"
local placePath = prefix .. "_client.rbxlx"

local function child(root, ...)
    local node = root
    for _, name in ipairs({ ... }) do node = node and node:FindFirstChild(name) end
    return node
end

local function pathOf(inst)
    if not inst then return "missing" end
    local ok, value = pcall(function() return inst:GetFullName() end)
    return ok and value or inst.Name
end

local function positionOf(inst)
    if not inst then return nil end
    if inst:IsA("BasePart") then return inst.Position end
    if inst:IsA("Attachment") then return inst.WorldPosition end
    if inst:IsA("Model") then
        local ok, pivot = pcall(function() return inst:GetPivot() end)
        if ok then return pivot.Position end
    end
    return nil
end

local function plain(value, depth, seen)
    depth, seen = depth or 0, seen or {}
    if value == nil then return nil end
    local kind = typeof(value)
    if kind == "Instance" then return pathOf(value) end
    if kind == "Vector3" then return { x = value.X, y = value.Y, z = value.Z } end
    if kind == "CFrame" then return plain(value.Position, depth + 1, seen) end
    if kind == "string" or kind == "number" or kind == "boolean" then return value end
    if kind ~= "table" then return tostring(value) end
    if seen[value] or depth >= 20 then return "<truncated>" end
    seen[value] = true
    local result = {}
    for key, item in pairs(value) do
        result[tostring(key)] = plain(item, depth + 1, seen)
    end
    seen[value] = nil
    return result
end

local function attrs(inst)
    local ok, value = pcall(function() return inst:GetAttributes() end)
    return ok and plain(value) or {}
end

local function timed(fn, timeout)
    local done, ok, result = false, false, nil
    task.spawn(function()
        ok, result = pcall(fn)
        done = true
    end)
    local deadline = os.clock() + timeout
    while not done and os.clock() < deadline do task.wait(0.05) end
    if not done then return false, "timeout" end
    return ok, result
end

local function serviceRead(service, method, ...)
    local remote = child(RS, "Packages", "Knit", "Services", service, "RF", method)
    if not remote or not remote:IsA("RemoteFunction") then return false, "missing" end
    local args = table.pack(...)
    return timed(function() return remote:InvokeServer(table.unpack(args, 1, args.n)) end, 3)
end

local function moduleRead(...)
    local module = child(RS:FindFirstChild("Database"), ...)
    if not module or not module:IsA("ModuleScript") then return false, "missing" end
    return timed(function() return require(module) end, 5)
end

local function sortedKeys(map)
    local keys = {}
    if type(map) == "table" then
        for key in pairs(map) do keys[#keys + 1] = key end
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

local function run()
    if not player then error("LocalPlayer unavailable") end
    if type(writefile) ~= "function" then
        error("This executor has no writefile() API; a file dump cannot be saved")
    end
    local streamingOk, streamingValue = pcall(function() return WS.StreamingEnabled end)
    local streamingEnabled = streamingOk and streamingValue == true

    local summary = {
        meta = {
            placeId = game.PlaceId,
            captured = os.date("%Y-%m-%d %H:%M:%S"),
            streamingEnabled = streamingEnabled,
            clientOnly = true,
            note = "ServerScriptService and ServerStorage never replicate to clients.",
        },
        streamProbes = {},
        npcs = {},
        enemies = {},
        waypoints = {},
        remotes = {},
        scripts = {},
        availability = {},
    }

    local questsOk, questData = moduleRead("QuestInfo", "KillQuestRepeatables")
    local zonesOk, zoneData = moduleRead("Zones")
    summary.questData = questsOk and plain(questData) or { error = tostring(questData) }
    summary.zoneData = zonesOk and plain(zoneData) or { error = tostring(zoneData) }

    local stateOk, questState = serviceRead("QuestService", "GetQuests")
    summary.questState = stateOk and plain(questState) or { error = tostring(questState) }
    local progressOk, zones = serviceRead("ZoneHandler", "GetZones")
    summary.zoneProgress = progressOk and plain(zones) or { error = tostring(zones) }

    if questsOk and type(questData) == "table" then
        for _, id in ipairs(sortedKeys(questData)) do
            local ok, result = serviceRead("QuestService", "GetQuestAvailability", id)
            summary.availability[tostring(id)] = ok and plain(result) or { error = tostring(result) }
            task.wait(0.04)
        end
    end

    local seenEnemies = {}
    local function recordVisible(zoneName)
        for _, inst in ipairs(WS:GetChildren()) do
            if inst:IsA("Model") and inst:GetAttribute("EnemyType") then
                summary.npcs[pathOf(inst)] = {
                    id = inst:GetAttribute("Id"), enemyType = inst:GetAttribute("EnemyType"),
                    zoneSeen = zoneName, position = plain(positionOf(inst)), attributes = attrs(inst),
                }
            end
        end
        local enemies = WS:FindFirstChild("Enemies")
        if enemies then
            for _, inst in ipairs(enemies:GetChildren()) do
                if inst:IsA("Model") then
                    local key = inst.Name .. "|" .. tostring(inst:GetAttribute("Level"))
                    local entry = summary.enemies[key]
                    if not entry then
                        entry = { count = 0, level = inst:GetAttribute("Level"),
                            exp = inst:GetAttribute("Exp"), positions = {}, zonesSeen = {} }
                        summary.enemies[key] = entry
                    end
                    if not seenEnemies[inst] then
                        seenEnemies[inst] = true
                        entry.count = entry.count + 1
                        if #entry.positions < 5 then
                            entry.positions[#entry.positions + 1] = plain(positionOf(inst))
                        end
                    end
                    entry.zonesSeen[zoneName] = true
                end
            end
        end
    end

    recordVisible("initial")
    local islands = child(WS, "_Map", "Islands")
    if islands then
        for _, island in ipairs(islands:GetChildren()) do
            if island.Name:match("^Island%d+$") then
                local waypoint = island:FindFirstChild("Waypoint_" .. island.Name)
                local anchor = waypoint and (waypoint:FindFirstChild("Teleport", true)
                    or waypoint:FindFirstChild("TeleporterPurchasePart", true))
                local pos = positionOf(anchor)
                if pos then
                    summary.waypoints[island.Name] = { path = pathOf(anchor), position = plain(pos) }
                    if streamingEnabled then
                        local ok, err = timed(function()
                            player:RequestStreamAroundAsync(pos, 2)
                        end, 3)
                        summary.streamProbes[island.Name] = ok and "requested" or tostring(err)
                        task.wait(0.3)
                        recordVisible(island.Name)
                    end
                end
            end
        end
        for _, inst in ipairs(islands:GetDescendants()) do
            if inst:IsA("Model") and inst:GetAttribute("EnemyType") then
                summary.npcs[pathOf(inst)] = {
                    id = inst:GetAttribute("Id"), enemyType = inst:GetAttribute("EnemyType"),
                    position = plain(positionOf(inst)), attributes = attrs(inst),
                }
            end
        end
    end

    local knitServices = child(RS, "Packages", "Knit", "Services")
    if knitServices then
        for _, inst in ipairs(knitServices:GetDescendants()) do
            if inst:IsA("RemoteFunction") or inst:IsA("RemoteEvent")
                or inst:IsA("UnreliableRemoteEvent") then
                summary.remotes[#summary.remotes + 1] = pathOf(inst)
            end
        end
    end
    table.sort(summary.remotes)

    for index, inst in ipairs(RS:GetDescendants()) do
        if inst:IsA("ModuleScript") or inst:IsA("LocalScript") then
            summary.scripts[#summary.scripts + 1] = pathOf(inst)
        end
        if index % 500 == 0 then task.wait() end
    end
    table.sort(summary.scripts)

    local json = HttpService:JSONEncode(summary)
    env.VANTA_PvPFullDumpManifest = json
    writefile(manifestPath, json)
    print("[PvPFullDump] Manifest saved: " .. manifestPath .. " (" .. #json .. " bytes)")

    if type(loadstring) ~= "function" then
        error("loadstring() is unavailable; manifest was saved but full place dump cannot run")
    end
    local sourceUrl = "https://raw.githubusercontent.com/luau/UniversalSynSaveInstance/main/saveinstance.luau"
    print("[PvPFullDump] Loading UniversalSynSaveInstance from its official repository")
    local source = game:HttpGet(sourceUrl, true)
    local factory, compileErr = loadstring(source, "UniversalSynSaveInstance")
    if not factory then error(tostring(compileErr)) end
    local saver = factory()
    if type(saver) ~= "function" then error("SaveInstance loader did not return a function") end

    print("[PvPFullDump] Saving client-visible place to " .. placePath)
    saver({
        mode = "full",
        FilePath = placePath,
        Binary = false,
        Decompile = type(decompile) == "function",
        SaveBytecode = type(getscriptbytecode) == "function",
        DecompileTimeout = 8,
        SafeMode = false,
        KillAllScripts = false,
        BoostFPS = false,
        ShutdownWhenDone = false,
        AntiIdle = false,
        ShowStatus = false,
        SavePlayerCharacters = false,
        CopyToClipboard = false,
    })
    local exists = type(isfile) ~= "function" or isfile(placePath)
    print("[PvPFullDump] " .. (exists and "Finished" or "Save returned but file was not found")
        .. "; files: " .. manifestPath .. " and " .. placePath)
end

task.spawn(function()
    local ok, err = pcall(run)
    if not ok then warn("[PvPFullDump] " .. tostring(err)) end
end)
