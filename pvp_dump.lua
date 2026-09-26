-- One-shot, passive snapshot for a PvP/quest/leveling game.
-- Does not hook remotes, press controls, or require unknown game modules.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local player = Players.LocalPlayer
local env = type(getgenv) == "function" and getgenv() or _G
local previous = env.VANTA_PvPDump
if previous then previous.cancelled = true end
local run = { cancelled = false, started = os.clock() }
env.VANTA_PvPDump = run

local MAX_LINES = 5000
local lines = {}
local counts = { remotes = 0, scripts = 0, actors = 0, prompts = 0, ui = 0, world = 0, values = 0 }
local sections = { remotes = {}, scripts = {}, actors = {}, prompts = {}, ui = {}, world = {}, values = {} }
local limits = { remotes = 700, scripts = 750, actors = 300, prompts = 300, ui = 450, world = 550, values = 300 }

local keywords = {
    "pvp", "combat", "attack", "skill", "ability", "quest", "task", "mission",
    "level", "exp", "xp", "enemy", "mob", "boss", "npc", "island", "world",
    "portal", "teleport", "zone", "spawn", "drop", "loot", "weapon", "inventory",
    "stat", "raid", "dungeon", "party", "guild", "arena", "shop", "damage",
    "hit", "health", "rebirth", "training", "mastery", "map", "sea", "boat",
    "currency", "reward", "pet", "fruit", "power", "rank", "kill", "team",
}

local function relevant(value)
    local text = tostring(value or ""):lower()
    for _, word in ipairs(keywords) do
        if text:find(word, 1, true) then return true end
    end
    return false
end

local function safePath(inst)
    local ok, path = pcall(function() return inst:GetFullName() end)
    return ok and path or inst.Name
end

local function compact(value, depth, seen)
    depth = depth or 0
    seen = seen or {}
    local kind = typeof(value)
    if kind == "Instance" then return "<" .. value.ClassName .. " " .. safePath(value) .. ">" end
    if kind == "Vector3" then return string.format("(%.1f, %.1f, %.1f)", value.X, value.Y, value.Z) end
    if kind == "CFrame" then return compact(value.Position) end
    if kind == "string" then return string.format("%q", value:sub(1, 160)) end
    if kind ~= "table" then return tostring(value) end
    if depth >= 2 or seen[value] then return "{...}" end
    seen[value] = true
    local parts, count = {}, 0
    for key, item in pairs(value) do
        count = count + 1
        if count > 18 then table.insert(parts, "..."); break end
        table.insert(parts, compact(key, depth + 1, seen) .. "=" .. compact(item, depth + 1, seen))
    end
    seen[value] = nil
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function attrs(inst)
    local ok, result = pcall(function() return inst:GetAttributes() end)
    return ok and compact(result) or "{}"
end

local function position(inst)
    if inst:IsA("BasePart") then return compact(inst.Position) end
    if inst:IsA("Model") then
        local ok, pivot = pcall(function() return inst:GetPivot() end)
        if ok then return compact(pivot.Position) end
    end
    return "?"
end

local function add(section, value)
    counts[section] = counts[section] + 1
    if #sections[section] < limits[section] then table.insert(sections[section], value) end
end

local function detail(inst)
    return inst.ClassName .. " " .. safePath(inst) .. " attrs=" .. attrs(inst)
end

local function scan(inst)
    if inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") or inst:IsA("UnreliableRemoteEvent")
        or inst:IsA("BindableEvent") or inst:IsA("BindableFunction") then
        add("remotes", detail(inst))
    elseif inst:IsA("Script") or inst:IsA("LocalScript") or inst:IsA("ModuleScript") then
        add("scripts", detail(inst))
    elseif inst:IsA("ProximityPrompt") then
        add("prompts", safePath(inst) .. " action=" .. compact(inst.ActionText)
            .. " object=" .. compact(inst.ObjectText) .. " enabled=" .. tostring(inst.Enabled)
            .. " distance=" .. tostring(inst.MaxActivationDistance))
    elseif inst:IsA("ClickDetector") then
        add("prompts", safePath(inst) .. " ClickDetector distance=" .. tostring(inst.MaxActivationDistance))
    elseif inst:IsA("ScreenGui") then
        add("ui", safePath(inst) .. " ScreenGui enabled=" .. tostring(inst.Enabled))
    elseif inst:IsA("GuiButton") then
        local label = inst:IsA("TextButton") and inst.Text or ""
        if relevant(inst.Name .. " " .. label) then
            add("ui", safePath(inst) .. " button=" .. compact(label) .. " visible=" .. tostring(inst.Visible))
        end
    elseif inst:IsA("TextLabel") then
        if relevant(inst.Name .. " " .. inst.Text) then
            add("ui", safePath(inst) .. " text=" .. compact(inst.Text) .. " visible=" .. tostring(inst.Visible))
        end
    elseif inst:IsA("NumberValue") or inst:IsA("IntValue") or inst:IsA("StringValue")
        or inst:IsA("BoolValue") or inst:IsA("ObjectValue") then
        if relevant(inst.Name) then
            add("values", safePath(inst) .. " = " .. compact(inst.Value))
        end
    end

    if inst:IsDescendantOf(workspace) then
        if inst:IsA("Model") then
            local humanoid = inst:FindFirstChildOfClass("Humanoid")
            if humanoid and not Players:GetPlayerFromCharacter(inst) then
                add("actors", safePath(inst) .. " hp=" .. string.format("%.0f/%.0f", humanoid.Health, humanoid.MaxHealth)
                    .. " pos=" .. position(inst) .. " attrs=" .. attrs(inst))
            elseif relevant(inst.Name) then
                add("world", detail(inst) .. " pos=" .. position(inst))
            end
        elseif (inst:IsA("Folder") or inst:IsA("BasePart")) and relevant(inst.Name) then
            add("world", detail(inst) .. " pos=" .. position(inst))
        end
    end
end

local function push(value)
    if #lines < MAX_LINES then table.insert(lines, value) end
end

local function section(title, entries, count)
    push("")
    push("--[[ " .. title .. " ]] count=" .. count .. " shown=" .. #entries)
    for _, entry in ipairs(entries) do push("-- " .. entry) end
end

local function inventory()
    push("--[[ PLAYER ]] ")
    if not player then push("-- LocalPlayer unavailable"); return end
    push("-- Name=" .. player.Name .. " UserId=" .. player.UserId .. " attrs=" .. attrs(player))
    local character = player.Character
    push("-- Character=" .. (character and safePath(character) or "none"))
    if character then
        local root = character:FindFirstChild("HumanoidRootPart")
        push("-- Position=" .. (root and position(root) or "unknown"))
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then push("-- Health=" .. humanoid.Health .. "/" .. humanoid.MaxHealth .. " LevelAttribute=" .. compact(humanoid:GetAttribute("Level"))) end
    end
    for _, containerName in ipairs({ "leaderstats", "Backpack", "PlayerScripts", "PlayerGui" }) do
        local container = player:FindFirstChild(containerName)
        if container then
            push("-- " .. containerName .. " children=" .. #container:GetChildren() .. " attrs=" .. attrs(container))
            if containerName == "leaderstats" or containerName == "Backpack" then
                for i, child in ipairs(container:GetChildren()) do
                    if i > 80 then break end
                    local value = child:IsA("ValueBase") and compact(child.Value) or "n/a"
                    push("--   " .. child.ClassName .. " " .. child.Name .. " value=" .. value .. " attrs=" .. attrs(child))
                end
            end
        end
    end
end

local function runSnapshot()
    push("-- PvP World One-Shot Snapshot")
    push("-- Captured: " .. os.date("%Y-%m-%d %H:%M:%S"))
    push("-- PlaceId=" .. tostring(game.PlaceId) .. " GameId=" .. tostring(game.GameId) .. " JobId=" .. tostring(game.JobId))
    push("-- Passive static data only. No gameplay action or server-only logic can be inferred with certainty.")
    push("-- No hooks, input capture, module requires, or remote calls.")
    push("")
    inventory()
    local roots = {
        game:GetService("ReplicatedStorage"), game:GetService("ReplicatedFirst"),
        workspace, player, game:GetService("StarterPlayer"),
        game:GetService("StarterGui"), game:GetService("Lighting"),
        game:GetService("SoundService"), game:GetService("TextChatService"),
    }
    local seen = {}
    for _, root in ipairs(roots) do
        if run.cancelled then return end
        print("[PvPDump] Scanning " .. root.Name)
        push("")
        push("-- ROOT " .. safePath(root) .. " children=" .. #root:GetChildren() .. " attrs=" .. attrs(root))
        for i, child in ipairs(root:GetChildren()) do
            if i > 60 then break end
            push("--   " .. child.ClassName .. " " .. child.Name .. " attrs=" .. attrs(child))
        end
        local descendants = root:GetDescendants()
        for i, inst in ipairs(descendants) do
            if run.cancelled then return end
            if not seen[inst] then seen[inst] = true; scan(inst) end
            if i % 150 == 0 then task.wait() end
        end
        task.wait()
    end
    section("REMOTES (client-visible)", sections.remotes, counts.remotes)
    section("SCRIPTS AND MODULES (names only)", sections.scripts, counts.scripts)
    section("NPCS AND MONSTERS", sections.actors, counts.actors)
    section("PROMPTS AND CLICK TARGETS", sections.prompts, counts.prompts)
    section("WORLD, ISLANDS, PORTALS, SPAWNS", sections.world, counts.world)
    section("PLAYER AND GAME VALUES", sections.values, counts.values)
    section("GUI AND GAMEPLAY TEXT", sections.ui, counts.ui)

    local ok, tags = pcall(function() return CollectionService:GetAllTags() end)
    if ok then
        push("")
        push("--[[ COLLECTION TAGS ]] count=" .. #tags)
        table.sort(tags)
        for i, tag in ipairs(tags) do
            if i > 200 then break end
            local tagged = CollectionService:GetTagged(tag)
            local examples = {}
            for j = 1, math.min(#tagged, 3) do examples[j] = safePath(tagged[j]) end
            push("-- " .. tag .. " count=" .. #tagged .. " examples=" .. table.concat(examples, " | "))
        end
    end
    push("")
    push("-- Elapsed=" .. string.format("%.1fs", os.clock() - run.started))
    local dump = table.concat(lines, "\n")
    run.text = dump
    env.PvPDumpCopy = function()
        local clipboard = setclipboard or toclipboard or set_clipboard
        if type(clipboard) ~= "function" then warn("[PvPDump] Clipboard unavailable"); return false end
        local copied, err = pcall(clipboard, dump)
        if not copied then warn("[PvPDump] Clipboard error: " .. tostring(err)); return false end
        print("[PvPDump] Copied " .. #dump .. " bytes. Send the pasted text for analysis.")
        return true
    end
    if not env.PvPDumpCopy() then
        print("[PvPDump] Full result available as getgenv().VANTA_PvPDump.text")
        for i = 1, #dump, 4000 do print(dump:sub(i, i + 3999)) end
    end
end

local ok, err = pcall(runSnapshot)
if not ok then warn("[PvPDump] Failed: " .. tostring(err)) end
