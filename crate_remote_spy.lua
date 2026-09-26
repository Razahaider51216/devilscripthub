-- DEVIL HUB crate diagnostic for PlaceId 120475074479690.
-- Run first, interact with a crate manually, wait 3 seconds, then type /dumpspy.

if game.PlaceId ~= 120475074479690 then
    warn("[CrateSpy] Wrong place: " .. tostring(game.PlaceId))
    return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TextChatService = game:GetService("TextChatService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local player = Players.LocalPlayer
local crates = Workspace:FindFirstChild("Crates") or Workspace:WaitForChild("Crates", 10)
local env = type(getgenv) == "function" and getgenv() or _G

if env.DEVIL_CRATE_SPY and type(env.DEVIL_CRATE_SPY.stop) == "function" then
    pcall(env.DEVIL_CRATE_SPY.stop)
end

local spy = {
    active = true, connections = {}, incoming = {}, command = nil,
    events = {}, lastBySignature = {}, started = os.date("%Y-%m-%d %H:%M:%S"),
    hookInstalled = false,
}
env.DEVIL_CRATE_SPY = spy
local MAX_EVENTS = 450

local function pathOf(inst)
    local parts = {}
    while inst and inst ~= game do
        table.insert(parts, 1, string.format("[%q]", inst.Name))
        inst = inst.Parent
    end
    return "game" .. table.concat(parts)
end

local function formatValue(value, depth, seen)
    depth = depth or 0
    seen = seen or {}
    local kind = typeof(value)
    if kind == "Instance" then return "<" .. value.ClassName .. " " .. pathOf(value) .. ">" end
    if kind == "Vector3" then
        return string.format("Vector3(%.1f,%.1f,%.1f)", value.X, value.Y, value.Z)
    end
    if kind == "CFrame" then
        local p = value.Position
        return string.format("CFrame(%.1f,%.1f,%.1f)", p.X, p.Y, p.Z)
    end
    if kind == "string" then return string.format("%q", value:sub(1, 220)) end
    if kind == "table" then
        if seen[value] then return "<cycle>" end
        if depth >= 3 then return "{...}" end
        seen[value] = true
        local entries, count = {}, 0
        for key, item in pairs(value) do
            count = count + 1
            if count > 14 then
                entries[#entries + 1] = "..."
                break
            end
            entries[#entries + 1] = tostring(key) .. "=" .. formatValue(item, depth + 1, seen)
        end
        seen[value] = nil
        return "{" .. table.concat(entries, ",") .. "}"
    end
    return tostring(value)
end

local function argsText(...)
    local entries = {}
    for index = 1, select("#", ...) do
        entries[index] = formatValue(select(index, ...))
    end
    local value = table.concat(entries, ", ")
    return #value > 2200 and value:sub(1, 2200) .. "..." or value
end

local function record(kind, detail, signature)
    if not spy.active then return end
    local now = os.clock()
    if signature then
        local old = spy.lastBySignature[signature]
        if old and now - old.last < 2 then
            old.count = old.count + 1
            old.last = now
            old.lastTime = os.date("%H:%M:%S")
            return
        end
    end
    local entry = {
        time = os.date("%H:%M:%S"), lastTime = os.date("%H:%M:%S"),
        kind = kind, detail = detail, count = 1, last = now,
    }
    spy.events[#spy.events + 1] = entry
    if signature then spy.lastBySignature[signature] = entry end
    if #spy.events > MAX_EVENTS then
        local removed = table.remove(spy.events, 1)
        for key, tracked in pairs(spy.lastBySignature) do
            if tracked == removed then spy.lastBySignature[key] = nil end
        end
    end
    print("[CrateSpy] " .. entry.time .. " " .. kind .. " " .. detail:sub(1, 350))
end

local function playerPosition()
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    return root and formatValue(root.Position) or "no character root"
end

local function modelForPrompt(prompt)
    local node = prompt
    while node and node ~= crates do
        if node.Parent == crates then return node end
        node = node.Parent
    end
    return nil
end

local function promptDetails(prompt)
    local model = modelForPrompt(prompt)
    local info = model and ("crate=" .. model.Name) or "crate=outside Workspace.Crates"
    return info .. " path=" .. pathOf(prompt)
        .. " action=" .. formatValue(prompt.ActionText)
        .. " object=" .. formatValue(prompt.ObjectText)
        .. " enabled=" .. tostring(prompt.Enabled)
        .. " hold=" .. tostring(prompt.HoldDuration)
        .. " maxDistance=" .. tostring(prompt.MaxActivationDistance)
        .. " player=" .. playerPosition()
end

local function crateState(model)
    if not model then return "no crate model" end
    local prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
    local ok, pivot = pcall(function() return model:GetPivot() end)
    return "name=" .. model.Name
        .. " parent=" .. (model.Parent and pathOf(model.Parent) or "nil")
        .. " position=" .. (ok and formatValue(pivot.Position) or "unknown")
        .. " prompt=" .. (prompt and ("enabled=" .. tostring(prompt.Enabled)
            .. " action=" .. formatValue(prompt.ActionText)) or "none")
        .. " attrs=" .. formatValue(model:GetAttributes())
end

local function toolList()
    local names = {}
    local backpack = player:FindFirstChildOfClass("Backpack")
    local containers = {}
    if backpack then containers[#containers + 1] = backpack end
    if player.Character then containers[#containers + 1] = player.Character end
    for _, container in ipairs(containers) do
        for _, item in ipairs(container:GetChildren()) do
            if item:IsA("Tool") then names[#names + 1] = item.Name end
        end
    end
    table.sort(names)
    return table.concat(names, ", ")
end

local function watchRemote(inst)
    if spy.incoming[inst] then return end
    if inst.ClassName ~= "RemoteEvent" and inst.ClassName ~= "UnreliableRemoteEvent" then return end
    if not inst:IsDescendantOf(ReplicatedStorage) then return end
    local name = inst.Name:lower()
    if not (name:find("crate", 1, true) or name:find("storm", 1, true)
        or name:find("collect", 1, true) or name:find("interact", 1, true)
        or name:find("steal", 1, true) or name:find("reveal", 1, true)) then return end
    local ok, connection = pcall(function()
        return inst.OnClientEvent:Connect(function(...)
            record("REMOTE_IN", pathOf(inst) .. " args=" .. argsText(...))
        end)
    end)
    if ok then spy.incoming[inst] = connection end
end

local function snapshot(lines, title)
    lines[#lines + 1] = "--[[ " .. title .. " ]]"
    lines[#lines + 1] = "-- Player position: " .. playerPosition()
    lines[#lines + 1] = "-- Tools: " .. toolList()
    if not crates then
        lines[#lines + 1] = "-- Workspace.Crates missing"
        return
    end
    local models = {}
    for _, item in ipairs(crates:GetChildren()) do
        if item:IsA("Model") then models[#models + 1] = item end
    end
    table.sort(models, function(a, b) return a.Name < b.Name end)
    lines[#lines + 1] = "-- Crate models: " .. #models
    for index = 1, math.min(#models, 100) do
        lines[#lines + 1] = "-- CRATE " .. crateState(models[index])
    end
end

local function makeDump()
    local lines = {
        "-- DEVIL HUB Crate Remote Spy",
        "-- Started: " .. spy.started,
        "-- Copied: " .. os.date("%Y-%m-%d %H:%M:%S"),
        "-- PlaceId: " .. tostring(game.PlaceId),
        "-- Hook: " .. tostring(spy.hookInstalled),
        "",
    }
    for _, line in ipairs(spy.startSnapshot or {}) do lines[#lines + 1] = line end
    lines[#lines + 1] = ""
    snapshot(lines, "WORLD AT COPY")
    lines[#lines + 1] = ""
    lines[#lines + 1] = "--[[ TIMELINE: oldest first ]]"
    if #spy.events == 0 then lines[#lines + 1] = "-- no events captured" end
    for _, entry in ipairs(spy.events) do
        local repeatText = entry.count > 1
            and (" x" .. entry.count .. " through " .. entry.lastTime) or ""
        lines[#lines + 1] = "-- [" .. entry.time .. "] " .. entry.kind .. " "
            .. entry.detail .. repeatText
    end
    return table.concat(lines, "\n")
end

local function copyDump()
    local dump = makeDump()
    local clipboard = setclipboard or toclipboard or set_clipboard
    if type(clipboard) == "function" then
        local ok = pcall(clipboard, dump)
        if ok then
            print(string.format("[CrateSpy] Copied %d bytes and %d events", #dump, #spy.events))
            return
        end
    end
    if type(writefile) == "function" then
        local filename = "DevilCrateSpy_" .. os.date("%Y%m%d_%H%M%S") .. ".txt"
        local ok = pcall(writefile, filename, dump)
        if ok then
            warn("[CrateSpy] Clipboard unavailable; saved " .. filename)
            return
        end
    end
    warn("[CrateSpy] Clipboard and file output unavailable; printing dump")
    print(dump)
end

env.DevilCrateSpyCopy = copyDump
spy.stop = function()
    if not spy.active then return end
    spy.active = false
    for _, connection in ipairs(spy.connections) do connection:Disconnect() end
    for _, connection in pairs(spy.incoming) do connection:Disconnect() end
    if spy.command then spy.command:Destroy() end
    if env.DevilCrateSpyCopy == copyDump then env.DevilCrateSpyCopy = nil end
end

local lastCommandAt = 0
local function handleCommand(message)
    message = tostring(message or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if message ~= "/dumpspy" or os.clock() - lastCommandAt < 0.8 then return end
    lastCommandAt = os.clock()
    copyDump()
end

table.insert(spy.connections, player.Chatted:Connect(handleCommand))
pcall(function()
    table.insert(spy.connections, TextChatService.SendingMessage:Connect(function(message)
        if message and message.Text then handleCommand(message.Text) end
    end))
end)
pcall(function()
    local command = Instance.new("TextChatCommand")
    command.Name = "DevilCrateDumpSpyCommand"
    command.PrimaryAlias = "/dumpspy"
    command.Parent = TextChatService
    spy.command = command
    table.insert(spy.connections, command.Triggered:Connect(function(origin, message)
        if not origin or origin.UserId == player.UserId then
            handleCommand(message or "/dumpspy")
        end
    end))
end)

table.insert(spy.connections, ProximityPromptService.PromptShown:Connect(function(prompt)
    if modelForPrompt(prompt) then record("PROMPT_SHOWN", promptDetails(prompt)) end
end))
table.insert(spy.connections, ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt, who)
    if modelForPrompt(prompt) and (not who or who == player) then
        record("PROMPT_HOLD", promptDetails(prompt))
    end
end))
table.insert(spy.connections, ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
    local model = modelForPrompt(prompt)
    if not model or (who and who ~= player) then return end
    record("PROMPT_TRIGGERED", promptDetails(prompt))
    record("CRATE_BEFORE", crateState(model) .. " tools=" .. toolList())
    for _, delaySeconds in ipairs({ 0.4, 1.5, 3 }) do
        task.delay(delaySeconds, function()
            if spy.active then
                record("CRATE_AFTER_" .. delaySeconds,
                    crateState(model) .. " tools=" .. toolList()
                    .. " player=" .. playerPosition())
            end
        end)
    end
end))

if crates then
    table.insert(spy.connections, crates.ChildAdded:Connect(function(item)
        if item:IsA("Model") then record("CRATE_ADDED", crateState(item)) end
    end))
    table.insert(spy.connections, crates.ChildRemoved:Connect(function(item)
        if item:IsA("Model") then record("CRATE_REMOVED", crateState(item)) end
    end))
end
local backpack = player:FindFirstChildOfClass("Backpack")
if backpack then
    table.insert(spy.connections, backpack.ChildAdded:Connect(function(item)
        if item:IsA("Tool") then record("TOOL_ADDED", item.Name) end
    end))
end

for _, item in ipairs(ReplicatedStorage:GetDescendants()) do watchRemote(item) end
table.insert(spy.connections, ReplicatedStorage.DescendantAdded:Connect(watchRemote))

if type(hookmetamethod) == "function" and type(getnamecallmethod) == "function" then
    local oldNamecall
    local wrap = type(newcclosure) == "function" and newcclosure or function(fn) return fn end
    local ok, result = pcall(function()
        return hookmetamethod(game, "__namecall", wrap(function(self, ...)
            local method = getnamecallmethod()
            local class = typeof(self) == "Instance" and self.ClassName or ""
            if spy.active and (class == "RemoteEvent" or class == "RemoteFunction"
                or class == "UnreliableRemoteEvent")
                and (method == "FireServer" or method == "InvokeServer") then
                local path = pathOf(self)
                if not path:find("UserGenerated", 1, true) then
                    local details = path .. " args=" .. argsText(...)
                        .. " player=" .. playerPosition()
                    record("REMOTE_OUT " .. method, details, method .. details)
                end
                if method == "InvokeServer" then
                    local results = table.pack(oldNamecall(self, ...))
                    if not path:find("UserGenerated", 1, true) then
                        record("REMOTE_RETURN", path .. " result="
                            .. argsText(table.unpack(results, 1, results.n)),
                            path:find("rf_CRATE_TIMERS", 1, true) and ("TIMER_RETURN|" .. path) or nil)
                    end
                    return table.unpack(results, 1, results.n)
                end
            end
            return oldNamecall(self, ...)
        end))
    end)
    if ok then
        oldNamecall = result
        spy.hookInstalled = true
    else
        warn("[CrateSpy] Outgoing hook failed: " .. tostring(result))
    end
end

spy.startSnapshot = {}
snapshot(spy.startSnapshot, "WORLD AT START")
record("READY", "Crates=" .. tostring(crates and #crates:GetChildren() or 0)
    .. " outgoingHook=" .. tostring(spy.hookInstalled))
print("[CrateSpy] Manually collect one crate, wait 3 seconds, then type /dumpspy")
