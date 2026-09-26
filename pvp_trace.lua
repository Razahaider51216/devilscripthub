-- Narrow 90-second trace for quest and combat call signatures.
-- Start in a fresh game session, then manually attack and accept one repeatable quest.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local player = Players.LocalPlayer
local services = RS:WaitForChild("Packages", 10)
services = services and services:FindFirstChild("Knit")
services = services and services:FindFirstChild("Services")
if not player or not services then warn("[PvPTrace] Player or Knit services missing"); return end

local env = type(getgenv) == "function" and getgenv() or _G
if env.VANTA_PvPTrace and type(env.VANTA_PvPTrace.stop) == "function" then pcall(env.VANTA_PvPTrace.stop) end
local runtime = { active = true, connections = {}, started = os.clock(), entries = {} }
env.VANTA_PvPTrace = runtime

local outgoing = {
    CombatService = { "RegisterAttack", "EnemyDamage", "WeaponDamage", "ExecuteSkill", "SkillDamage" },
    QuestService = { "TalkToNPC", "AcceptQuest", "CompleteQuest", "TrackQuest" },
}
local incoming = {
    CombatService = { "EnemyDamaged", "SkillExecuted", "InCombatChanged" },
    QuestService = { "OnQuestStarted", "QuestProgressChanged", "QuestAutoUpdated" },
    EnemyService = { "ExpEffect" },
}

local watched = {}
local function pathOf(inst)
    local ok, result = pcall(function() return inst:GetFullName() end)
    return ok and result or tostring(inst)
end

local function valueText(value, depth, seen)
    depth, seen = depth or 0, seen or {}
    local kind = typeof(value)
    if kind == "Instance" then return "<" .. value.ClassName .. " " .. pathOf(value) .. ">" end
    if kind == "Vector3" then return string.format("Vector3(%.2f, %.2f, %.2f)", value.X, value.Y, value.Z) end
    if kind == "CFrame" then return "CFrame(" .. valueText(value.Position) .. ")" end
    if kind == "string" then return string.format("%q", value:sub(1, 180)) end
    if kind ~= "table" then return tostring(value) end
    if seen[value] then return "<cycle>" end
    if depth >= 3 then return "{...}" end
    seen[value] = true
    local parts, count = {}, 0
    for key, item in pairs(value) do
        count = count + 1
        if count > 24 then table.insert(parts, "..."); break end
        table.insert(parts, "[" .. valueText(key, depth + 1, seen) .. "]=" .. valueText(item, depth + 1, seen))
    end
    seen[value] = nil
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function argsText(values)
    local parts = {}
    for i = 1, values.n do parts[i] = valueText(values[i]) end
    return table.concat(parts, ", "):sub(1, 2500)
end

local function record(kind, detail)
    if not runtime.active then return end
    local entry = string.format("[%.2fs] %s %s", os.clock() - runtime.started, kind, tostring(detail))
    table.insert(runtime.entries, entry)
    if #runtime.entries > 500 then table.remove(runtime.entries, 1) end
end

local function serviceRemote(serviceName, direction, remoteName)
    local service = services:FindFirstChild(serviceName)
    local folder = service and service:FindFirstChild(direction)
    return folder and folder:FindFirstChild(remoteName)
end

for serviceName, names in pairs(outgoing) do
    for _, remoteName in ipairs(names) do
        local remote = serviceRemote(serviceName, "RF", remoteName)
        if remote then watched[remote] = serviceName .. "." .. remoteName end
    end
end

for serviceName, names in pairs(incoming) do
    for _, remoteName in ipairs(names) do
        local remote = serviceRemote(serviceName, "RE", remoteName)
        if remote and (remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent")) then
            table.insert(runtime.connections, remote.OnClientEvent:Connect(function(...)
                local values = table.pack(...)
                task.defer(function()
                    if runtime.active then record("IN " .. serviceName .. "." .. remoteName, argsText(values)) end
                end)
            end))
        end
    end
end

local hookInstalled = false
if type(hookmetamethod) == "function" and type(getnamecallmethod) == "function" then
    local oldNamecall
    local wrap = type(newcclosure) == "function" and newcclosure or function(fn) return fn end
    local ok, result = pcall(function()
        return hookmetamethod(game, "__namecall", wrap(function(self, ...)
            local label = runtime.active and watched[self]
            if label and getnamecallmethod() == "InvokeServer" then
                local values = table.pack(...)
                task.defer(function()
                    if runtime.active then record("OUT " .. label, argsText(values)) end
                end)
            end
            return oldNamecall(self, ...)
        end))
    end)
    if ok then oldNamecall = result; hookInstalled = true else warn("[PvPTrace] Hook failed: " .. tostring(result)) end
end

local function questSnapshot(label)
    local remote = serviceRemote("QuestService", "RF", "GetQuests")
    if not remote then return end
    local ok, result = pcall(function() return remote:InvokeServer() end)
    if ok then record(label, valueText(result):sub(1, 7000)) end
end

local function copyTrace()
    local lines = {
        "-- PvP Quest/Combat Trace",
        "-- PlaceId=" .. game.PlaceId .. " player=" .. player.Name,
        "-- Hook=" .. tostring(hookInstalled) .. " duration=" .. string.format("%.1fs", os.clock() - runtime.started),
        "-- Only selected combat and quest remotes are recorded.",
        "",
    }
    for _, entry in ipairs(runtime.entries) do table.insert(lines, "-- " .. entry) end
    local dump = table.concat(lines, "\n")
    env.VANTA_PvPTraceText = dump
    local clipboard = setclipboard or toclipboard or set_clipboard
    if type(clipboard) == "function" then
        local ok, err = pcall(clipboard, dump)
        if ok then print("[PvPTrace] Copied " .. #dump .. " bytes"); return end
        warn("[PvPTrace] Clipboard error: " .. tostring(err))
    end
    print(dump)
end

local lastCopy = 0
local function command(message)
    message = tostring(message or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if message ~= "/tracecopy" then return end
    if os.clock() - lastCopy < 0.5 then return end
    lastCopy = os.clock()
    questSnapshot("QUEST_END")
    copyTrace()
end
table.insert(runtime.connections, player.Chatted:Connect(command))
pcall(function()
    table.insert(runtime.connections, TextChatService.SendingMessage:Connect(function(message) command(message.Text) end))
end)
pcall(function()
    local chatCommand = Instance.new("TextChatCommand")
    chatCommand.Name = "VANTAPvPTraceCopy"
    chatCommand.PrimaryAlias = "/tracecopy"
    chatCommand.Parent = TextChatService
    runtime.command = chatCommand
    table.insert(runtime.connections, chatCommand.Triggered:Connect(function() command("/tracecopy") end))
end)

runtime.stop = function()
    if not runtime.active then return end
    runtime.active = false
    for _, connection in ipairs(runtime.connections) do connection:Disconnect() end
    if runtime.command then runtime.command:Destroy() end
end

questSnapshot("QUEST_START")
record("READY", "Attack a monster, speak to a quest NPC, then use /tracecopy. No game calls are modified.")
print("[PvPTrace] Ready for 90 seconds. Hook=" .. tostring(hookInstalled) .. "; /tracecopy copies early.")
task.delay(90, function()
    if not runtime.active then return end
    questSnapshot("QUEST_END")
    copyTrace()
    runtime.stop()
    print("[PvPTrace] Stopped. Rejoin to remove the installed namecall wrapper completely.")
end)
