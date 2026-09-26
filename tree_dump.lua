-- Tree growth and lightning diagnostic. Start before buying a tree; use /dimp to copy.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local WS = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TextChatService = game:GetService("TextChatService")
local player = Players.LocalPlayer
local playerGui = player and player:WaitForChild("PlayerGui", 10)
if not playerGui then warn("[TreeDump] PlayerGui not found"); return end

local env = type(getgenv) == "function" and getgenv() or _G
local previous = env.VANTA_TreeDump_Runtime
if previous and type(previous.stop) == "function" then pcall(previous.stop) end
local runtime = { active = true, connections = {}, command = nil }
env.VANTA_TreeDump_Runtime = runtime
local started = os.date("%Y-%m-%d %H:%M:%S")
local events, remoteList = {}, {}
local watchedRemotes, watchedButtons, watchedLabels, watchedModels = {}, {}, {}, {}
local watchedModelCount = 0
local MAX_EVENTS = 1200

local keywords = {
    "tree", "seed", "sapling", "plant", "grow", "growth", "garden", "farm", "plot",
    "lightning", "thunder", "strike", "storm", "weather", "burn", "destroy",
    "buy", "purchase", "shop", "harvest", "sell", "claim", "risk", "timer",
}

local remoteKeywords = {
    "tree", "seed", "sapling", "plant", "grow", "garden", "farm", "plot",
    "lightning", "thunder", "strike", "storm", "weather", "harvest",
    "buy", "purchase",
}

local function relevant(text)
    text = tostring(text or ""):lower()
    for _, word in ipairs(keywords) do
        if text:find(word, 1, true) then return true end
    end
    return false
end

local function relevantRemote(text)
    text = tostring(text or ""):lower()
    for _, word in ipairs(remoteKeywords) do
        if text:find(word, 1, true) then return true end
    end
    return false
end

local function pathOf(inst)
    local parts = {}
    while inst and inst ~= game do
        table.insert(parts, 1, string.format("[%q]", inst.Name))
        inst = inst.Parent
    end
    return "game" .. table.concat(parts)
end

local function valueText(value, depth, seen)
    depth = depth or 0
    seen = seen or {}
    local kind = typeof(value)
    if kind == "Instance" then return "<" .. value.ClassName .. " " .. pathOf(value) .. ">" end
    if kind == "Vector3" then return string.format("Vector3(%.2f,%.2f,%.2f)", value.X, value.Y, value.Z) end
    if kind == "CFrame" then return "CFrame(" .. valueText(value.Position) .. ")" end
    if kind == "string" then return string.format("%q", value:sub(1, 220)) end
    if kind ~= "table" then return tostring(value) end
    if seen[value] then return "<cycle>" end
    if depth >= 4 then return "{...}" end
    seen[value] = true
    local parts, count = {}, 0
    for key, item in pairs(value) do
        count = count + 1
        if count > 35 then table.insert(parts, "..."); break end
        table.insert(parts, "[" .. valueText(key, depth + 1, seen) .. "]=" .. valueText(item, depth + 1, seen))
    end
    seen[value] = nil
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function argsText(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = valueText(select(i, ...)) end
    local joined = table.concat(parts, ", ")
    return #joined > 3500 and joined:sub(1, 3500) .. "..." or joined
end

local function serverTime()
    local ok, value = pcall(function() return WS:GetServerTimeNow() end)
    return ok and string.format("%.3f", value) or "unavailable"
end

local function log(kind, detail)
    if not runtime.active then return end
    detail = tostring(detail or "")
    if #detail > 3600 then detail = detail:sub(1, 3600) .. "..." end
    local line = string.format("[%s | server=%s | clock=%.3f] %s %s",
        os.date("%H:%M:%S"), serverTime(), os.clock(), kind, detail)
    table.insert(events, line)
    if #events > MAX_EVENTS then table.remove(events, 1) end
    print("[TreeDump] " .. line:sub(1, 330))
end

local function attributes(inst)
    local ok, result = pcall(function() return inst:GetAttributes() end)
    return ok and valueText(result) or "{}"
end

local function isTreeLike(inst)
    if not (inst:IsA("Model") or inst:IsA("Folder")) then return false end
    if relevant(inst.Name) then return true end
    for name in pairs(inst:GetAttributes()) do
        if relevant(name) then return true end
    end
    return false
end

local function positionOf(inst)
    if inst:IsA("Model") then
        local ok, pivot = pcall(function() return inst:GetPivot() end)
        if ok then return valueText(pivot.Position) end
    end
    local part = inst:FindFirstChildWhichIsA("BasePart", true)
    return part and valueText(part.Position) or "unknown"
end

local function watchModel(inst)
    if watchedModels[inst] or not isTreeLike(inst) then return end
    if watchedModelCount >= 200 then return end
    watchedModels[inst] = true
    watchedModelCount = watchedModelCount + 1
    table.insert(runtime.connections, inst.AttributeChanged:Connect(function(name)
        if relevant(name) or relevant(inst.Name) then
            log("TREE_ATTR", pathOf(inst) .. " " .. name .. "=" .. valueText(inst:GetAttribute(name)))
        end
    end))
end

local function guiText(inst)
    local text = inst.Name
    if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
        text = text .. " " .. inst.Text
    end
    for _, child in ipairs(inst:GetDescendants()) do
        if child:IsA("TextLabel") or child:IsA("TextButton") then
            text = text .. " " .. child.Text
            if #text > 300 then break end
        end
    end
    return text:sub(1, 350)
end

local function watchButton(inst)
    if watchedButtons[inst] or not inst:IsA("GuiButton") then return end
    if not relevant(guiText(inst)) then return end
    watchedButtons[inst] = true
    table.insert(runtime.connections, inst.Activated:Connect(function()
        log("BUTTON", pathOf(inst) .. " text=" .. valueText(guiText(inst)))
    end))
end

local function watchLabel(inst)
    if watchedLabels[inst] or not (inst:IsA("TextLabel") or inst:IsA("TextButton")) then return end
    if inst.Name == "GrowthProgress" or inst.Name == "Timer2" then return end
    if not relevant(inst.Name .. " " .. inst.Text) then return end
    watchedLabels[inst] = true
    local lastLogged = 0
    table.insert(runtime.connections, inst:GetPropertyChangedSignal("Text"):Connect(function()
        if os.clock() - lastLogged < 2 then return end
        lastLogged = os.clock()
        log("UI_TEXT", pathOf(inst) .. " text=" .. valueText(inst.Text))
    end))
end

local function watchRemote(remote)
    if watchedRemotes[remote] then return end
    if not (remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction")) then return end
    if not remote:IsDescendantOf(RS) then return end
    watchedRemotes[remote] = true
    table.insert(remoteList, remote.ClassName .. " " .. pathOf(remote))
    if remote:IsA("RemoteEvent") and relevantRemote(pathOf(remote)) then
        table.insert(runtime.connections, remote.OnClientEvent:Connect(function(...)
            local ok, payload = pcall(argsText, ...)
            if ok then log("REMOTE_IN", pathOf(remote) .. " args=" .. payload) end
        end))
    end
end

table.insert(runtime.connections, RS.DescendantAdded:Connect(watchRemote))
table.insert(runtime.connections, playerGui.DescendantAdded:Connect(function(inst)
    task.defer(function()
        if not runtime.active or not inst.Parent then return end
        if inst:IsA("GuiButton") then watchButton(inst) end
        watchLabel(inst)
    end)
end))
table.insert(runtime.connections, WS.DescendantAdded:Connect(function(inst)
    if not relevantRemote(inst.Name) then return end
    if inst:FindFirstAncestor("Shocked") then return end
    task.defer(function()
        if not runtime.active or not inst.Parent then return end
        if isTreeLike(inst) then
            watchModel(inst)
            log("TREE_ADDED", pathOf(inst) .. " pos=" .. positionOf(inst) .. " attrs=" .. attributes(inst))
        elseif inst.Name:lower():find("lightning", 1, true) or inst.Name:lower():find("thunder", 1, true) then
            local position = inst:IsA("BasePart") and valueText(inst.Position) or "unknown"
            log("LIGHTNING_OBJECT", pathOf(inst) .. " pos=" .. position)
        end
    end)
end))
table.insert(runtime.connections, WS.DescendantRemoving:Connect(function(inst)
    if watchedModels[inst] then
        log("TREE_REMOVED", pathOf(inst) .. " attrs=" .. attributes(inst))
        watchedModels[inst] = nil
        watchedModelCount = math.max(0, watchedModelCount - 1)
    end
end))
table.insert(runtime.connections, ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
    if who and who ~= player then return end
    log("PROMPT", pathOf(prompt) .. " action=" .. valueText(prompt.ActionText) .. " object=" .. valueText(prompt.ObjectText))
end))

task.spawn(function()
    local descendants = RS:GetDescendants()
    for i, inst in ipairs(descendants) do
        if not runtime.active then return end
        watchRemote(inst)
        if i % 150 == 0 then task.wait() end
    end
end)
task.spawn(function()
    local descendants = playerGui:GetDescendants()
    for i, inst in ipairs(descendants) do
        if not runtime.active then return end
        if inst:IsA("GuiButton") then watchButton(inst) end
        watchLabel(inst)
        if i % 150 == 0 then task.wait() end
    end
end)
task.spawn(function()
    local descendants = WS:GetDescendants()
    for i, inst in ipairs(descendants) do
        if not runtime.active then return end
        if relevantRemote(inst.Name) then watchModel(inst) end
        if i % 150 == 0 then task.wait() end
    end
end)

local function snapshot(lines)
    table.insert(lines, "--[[ ENVIRONMENT ]]")
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    table.insert(lines, "-- Player position: " .. (root and valueText(root.Position) or "unknown"))
    table.insert(lines, "-- Lighting ClockTime: " .. tostring(Lighting.ClockTime))
    table.insert(lines, "-- Lighting TimeOfDay: " .. tostring(Lighting.TimeOfDay))
    table.insert(lines, "-- Lighting attributes: " .. attributes(Lighting))
    table.insert(lines, "-- Workspace attributes: " .. attributes(WS))
    table.insert(lines, "")
    table.insert(lines, "--[[ TREE-LIKE OBJECTS ]] ")
    local candidates = {}
    for _, inst in ipairs(WS:GetDescendants()) do
        if isTreeLike(inst) then
            local score = 0
            local path = pathOf(inst):lower()
            if path:find("plot", 1, true) or path:find("farm", 1, true) or path:find("home", 1, true) then score = score + 4 end
            for key in pairs(inst:GetAttributes()) do if relevant(key) then score = score + 2 end end
            if inst.Name:lower():find("tree", 1, true) then score = score + 1 end
            table.insert(candidates, { inst = inst, score = score })
        end
    end
    table.sort(candidates, function(a, b) return a.score > b.score end)
    table.insert(lines, "-- Count: " .. #candidates .. " (showing up to 150)")
    for i = 1, math.min(#candidates, 150) do
        local inst = candidates[i].inst
        table.insert(lines, "-- TREE " .. pathOf(inst) .. " pos=" .. positionOf(inst) .. " attrs=" .. attributes(inst))
    end
    table.insert(lines, "")
    table.insert(lines, "--[[ REMOTE INVENTORY ]] ")
    local count = 0
    for _, entry in ipairs(remoteList) do
        count = count + 1
        if count <= 250 then table.insert(lines, "-- " .. entry) end
    end
    table.insert(lines, "-- Count: " .. count)
    table.insert(lines, "")
    table.insert(lines, "--[[ RELEVANT UI ]] ")
    local shown = 0
    for _, inst in ipairs(playerGui:GetDescendants()) do
        if (inst:IsA("TextLabel") or inst:IsA("TextButton")) and relevant(inst.Name .. " " .. inst.Text) then
            shown = shown + 1
            if shown <= 100 then table.insert(lines, "-- UI " .. pathOf(inst) .. " text=" .. valueText(inst.Text)) end
        end
    end
end

local function copyDump()
    local lines = {
        "-- Tree and Lightning Diagnostic Dump",
        "-- Started: " .. started,
        "-- Copied: " .. os.date("%Y-%m-%d %H:%M:%S"),
        "-- Passive mode: no outgoing hook",
        "-- PlaceId: " .. tostring(game.PlaceId),
        "",
    }
    snapshot(lines)
    table.insert(lines, "")
    table.insert(lines, "--[[ TIMELINE (oldest first) ]] ")
    if #events == 0 then table.insert(lines, "-- no events") end
    for _, event in ipairs(events) do table.insert(lines, "-- " .. event) end
    local dump = table.concat(lines, "\n")
    local clipboard = setclipboard or toclipboard or set_clipboard
    if type(clipboard) == "function" then
        local ok, err = pcall(clipboard, dump)
        if ok then print(string.format("[TreeDump] Copied %d bytes, %d events", #dump, #events)); return end
        warn("[TreeDump] Clipboard failed:", err)
    end
    print(dump)
end

runtime.stop = function()
    if not runtime.active then return end
    runtime.active = false
    for _, connection in ipairs(runtime.connections) do connection:Disconnect() end
    if runtime.command then runtime.command:Destroy() end
    if env.TreeDumpCopy == copyDump then env.TreeDumpCopy = nil end
end
env.TreeDumpCopy = copyDump

local lastCopy = 0
local function command(message)
    message = tostring(message or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if message ~= "/dimp" and message ~= "/treedump" and message ~= "/copy" then return end
    if os.clock() - lastCopy < 0.5 then return end
    lastCopy = os.clock()
    copyDump()
end
table.insert(runtime.connections, player.Chatted:Connect(command))
pcall(function()
    table.insert(runtime.connections, TextChatService.SendingMessage:Connect(function(message)
        command(message.Text)
    end))
end)
pcall(function()
    local chatCommand = Instance.new("TextChatCommand")
    chatCommand.Name = "VANTATreeDumpCommand"
    chatCommand.PrimaryAlias = "/dimp"
    chatCommand.SecondaryAlias = "/treedump"
    chatCommand.Parent = TextChatService
    runtime.command = chatCommand
    table.insert(runtime.connections, chatCommand.Triggered:Connect(function() command("/dimp") end))
end)

log("READY", "Passive mode. Buy and plant a tree, then observe growth and lightning; /dimp copies the dump.")
