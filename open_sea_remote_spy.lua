-- Open Sea diagnostic for eggv2.lua. Run before charging and changing carry capacity.
-- Play one charge manually, change the carry setting, then type /seadump.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local player = Players.LocalPlayer
local playerGui = player and player:WaitForChild("PlayerGui", 10)
if not playerGui then
    warn("[SeaSpy] PlayerGui unavailable")
    return
end

local env = type(getgenv) == "function" and getgenv() or _G
if env.DEVIL_OPEN_SEA_SPY and type(env.DEVIL_OPEN_SEA_SPY.stop) == "function" then
    pcall(env.DEVIL_OPEN_SEA_SPY.stop)
end

local spy = {
    active = true,
    started = os.date("%Y-%m-%d %H:%M:%S"),
    events = {},
    connections = {},
    incoming = {},
    watchedGui = {},
    watchedValues = {},
    hookInstalled = false,
}
env.DEVIL_OPEN_SEA_SPY = spy

local MAX_EVENTS = 650
local KEYWORDS = { "sea", "wave", "split", "charge", "perfect", "meter", "power", "carry", "capacity", "egg", "slot", "open" }

local function pathOf(inst)
    local parts = {}
    while inst and inst ~= game do
        table.insert(parts, 1, string.format("[%q]", inst.Name))
        inst = inst.Parent
    end
    return "game" .. table.concat(parts)
end

local function describe(value, depth, seen)
    depth = depth or 0
    seen = seen or {}
    local kind = typeof(value)
    if kind == "Instance" then return "<" .. value.ClassName .. " " .. pathOf(value) .. ">" end
    if kind == "Vector3" then return string.format("Vector3(%.2f,%.2f,%.2f)", value.X, value.Y, value.Z) end
    if kind == "CFrame" then return "CFrame(" .. describe(value.Position) .. ")" end
    if kind == "UDim2" then
        return string.format("UDim2(%.3f,%d,%.3f,%d)", value.X.Scale, value.X.Offset, value.Y.Scale, value.Y.Offset)
    end
    if kind == "string" then return string.format("%q", value:sub(1, 160)) end
    if kind == "table" then
        if seen[value] then return "<cycle>" end
        if depth >= 3 then return "{...}" end
        seen[value] = true
        local parts, count = {}, 0
        for key, item in pairs(value) do
            count = count + 1
            if count > 16 then parts[#parts + 1] = "..."; break end
            parts[#parts + 1] = tostring(key) .. "=" .. describe(item, depth + 1, seen)
        end
        seen[value] = nil
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return tostring(value)
end

local function argsText(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = describe(select(i, ...)) end
    local result = table.concat(parts, ", ")
    return #result > 1600 and result:sub(1, 1600) .. "..." or result
end

local function record(kind, details)
    if not spy.active then return end
    spy.events[#spy.events + 1] = string.format("[%.3f] %s %s", os.clock(), kind, tostring(details or ""))
    if #spy.events > MAX_EVENTS then table.remove(spy.events, 1) end
end
spy.record = record

local function relevant(text)
    text = tostring(text or ""):lower()
    if text:match("%d+%s*/%s*[1-6]%f[^%d]") then return true end
    for _, keyword in ipairs(KEYWORDS) do
        if text:find(keyword, 1, true) then return true end
    end
    return false
end

local function visible(inst)
    local node = inst
    while node and node ~= playerGui do
        if node:IsA("GuiObject") and not node.Visible then return false end
        if node:IsA("ScreenGui") and not node.Enabled then return false end
        node = node.Parent
    end
    return inst:IsDescendantOf(playerGui)
end

local function guiDetail(inst)
    local parts = { inst.ClassName, pathOf(inst), "visible=" .. tostring(visible(inst)) }
    if inst:IsA("GuiObject") then
        parts[#parts + 1] = "size=" .. describe(inst.Size)
        parts[#parts + 1] = "pos=" .. describe(inst.Position)
    end
    if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
        parts[#parts + 1] = "text=" .. describe(inst.Text)
    end
    if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
        parts[#parts + 1] = "image=" .. describe(inst.Image)
    end
    return table.concat(parts, " ")
end

local function snapshot(lines, title)
    lines[#lines + 1] = "--[[ " .. title .. " ]]"
    lines[#lines + 1] = "-- Player attributes: " .. describe(player:GetAttributes())
    for _, inst in ipairs(player:GetDescendants()) do
        if inst:IsA("ValueBase") and relevant(pathOf(inst)) then
            lines[#lines + 1] = "-- VALUE " .. pathOf(inst) .. "=" .. describe(inst.Value)
        end
    end
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    lines[#lines + 1] = "-- Position: " .. (root and describe(root.Position) or "unknown")
    local relevantGui = {}
    for _, inst in ipairs(playerGui:GetDescendants()) do
        if inst:IsA("GuiObject") and visible(inst) then
            local value = inst.Name
            if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
                value = value .. " " .. inst.Text
            end
            if relevant(value) or relevant(pathOf(inst)) then relevantGui[#relevantGui + 1] = inst end
        end
    end
    table.sort(relevantGui, function(a, b) return pathOf(a) < pathOf(b) end)
    lines[#lines + 1] = "-- Relevant visible GUI: " .. #relevantGui .. " (first 140)"
    for i = 1, math.min(#relevantGui, 140) do
        lines[#lines + 1] = "-- GUI " .. guiDetail(relevantGui[i])
    end
    local remotes = {}
    for _, inst in ipairs(ReplicatedStorage:GetDescendants()) do
        if (inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction") or inst:IsA("UnreliableRemoteEvent"))
            and relevant(pathOf(inst)) then
            remotes[#remotes + 1] = inst.ClassName .. " " .. pathOf(inst)
        end
    end
    table.sort(remotes)
    lines[#lines + 1] = "-- Relevant remotes: " .. #remotes .. " (first 100)"
    for i = 1, math.min(#remotes, 100) do lines[#lines + 1] = "-- REMOTE " .. remotes[i] end
end

local function watchGui(inst)
    if not inst:IsA("GuiObject") or spy.watchedGui[inst] then return end
    spy.watchedGui[inst] = true
    if inst:IsA("GuiButton") then
        spy.connections[#spy.connections + 1] = inst.Activated:Connect(function()
            record("BUTTON", guiDetail(inst))
        end)
    end
    if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
        local previous = inst.Text
        spy.connections[#spy.connections + 1] = inst:GetPropertyChangedSignal("Text"):Connect(function()
            local current = inst.Text
            if relevant(previous) or relevant(current) or relevant(pathOf(inst)) then
                record("UI_TEXT", pathOf(inst) .. " " .. describe(previous) .. " -> " .. describe(current))
            end
            previous = current
        end)
    end
    if relevant(pathOf(inst)) then
        local lastSize, lastLogged = inst.Size, 0
        spy.connections[#spy.connections + 1] = inst:GetPropertyChangedSignal("Size"):Connect(function()
            local now = os.clock()
            if now - lastLogged >= 0.1 then
                record("UI_SIZE", pathOf(inst) .. " " .. describe(lastSize) .. " -> " .. describe(inst.Size))
                lastLogged = now
            end
            lastSize = inst.Size
        end)
    end
end

local function watchRemote(inst)
    if not (inst:IsA("RemoteEvent") or inst:IsA("UnreliableRemoteEvent")) or spy.incoming[inst] then return end
    local ok, connection = pcall(function()
        return inst.OnClientEvent:Connect(function(...)
            record("REMOTE_IN", pathOf(inst) .. " args=" .. argsText(...))
        end)
    end)
    if ok then spy.incoming[inst] = connection end
end

local function watchValue(inst)
    if not inst:IsA("ValueBase") or spy.watchedValues[inst] or not relevant(pathOf(inst)) then return end
    spy.watchedValues[inst] = true
    spy.connections[#spy.connections + 1] = inst.Changed:Connect(function(value)
        record("PLAYER_VALUE", pathOf(inst) .. "=" .. describe(value))
    end)
end

local function makeDump()
    local lines = {
        "-- DEVIL HUB Open Sea / Carry Remote Spy",
        "-- Started: " .. spy.started,
        "-- Copied: " .. os.date("%Y-%m-%d %H:%M:%S"),
        "-- PlaceId: " .. tostring(game.PlaceId),
        "-- Outgoing hook: " .. tostring(spy.hookInstalled),
        "",
    }
    for _, line in ipairs(spy.startSnapshot) do lines[#lines + 1] = line end
    lines[#lines + 1] = ""
    snapshot(lines, "AT COPY")
    lines[#lines + 1] = ""
    lines[#lines + 1] = "--[[ TIMELINE ]]"
    for _, event in ipairs(spy.events) do lines[#lines + 1] = "-- " .. event end
    return table.concat(lines, "\n")
end

local function copyDump()
    local dump = makeDump()
    local clipboard = setclipboard or toclipboard or set_clipboard
    if type(clipboard) == "function" and pcall(clipboard, dump) then
        print(string.format("[SeaSpy] Copied %d bytes / %d events", #dump, #spy.events))
        return
    end
    if type(writefile) == "function" then
        local filename = "OpenSeaSpy_" .. os.date("%Y%m%d_%H%M%S") .. ".txt"
        if pcall(writefile, filename, dump) then
            warn("[SeaSpy] Saved " .. filename)
            return
        end
    end
    warn("[SeaSpy] Clipboard/file unavailable; printing dump")
    print(dump)
end

env.DevilOpenSeaSpyCopy = copyDump
spy.stop = function()
    if not spy.active then return end
    spy.active = false
    for _, connection in ipairs(spy.connections) do connection:Disconnect() end
    for _, connection in pairs(spy.incoming) do connection:Disconnect() end
    if spy.command then spy.command:Destroy() end
    if env.DevilOpenSeaSpyCopy == copyDump then env.DevilOpenSeaSpyCopy = nil end
    if env.DEVIL_OPEN_SEA_SPY_HOOK and env.DEVIL_OPEN_SEA_SPY_HOOK.spy == spy then
        env.DEVIL_OPEN_SEA_SPY_HOOK.spy = nil
    end
end

local lastCopy = 0
local function handleCommand(message)
    message = tostring(message or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if message ~= "/seadump" or os.clock() - lastCopy < 0.8 then return end
    lastCopy = os.clock()
    copyDump()
end

spy.connections[#spy.connections + 1] = player.Chatted:Connect(handleCommand)
pcall(function()
    spy.connections[#spy.connections + 1] = TextChatService.SendingMessage:Connect(function(message)
        if message and message.Text then handleCommand(message.Text) end
    end)
end)
pcall(function()
    local command = Instance.new("TextChatCommand")
    command.Name = "DevilOpenSeaDumpCommand"
    command.PrimaryAlias = "/seadump"
    command.Parent = TextChatService
    spy.command = command
    spy.connections[#spy.connections + 1] = command.Triggered:Connect(function(origin)
        if not origin or origin.UserId == player.UserId then handleCommand("/seadump") end
    end)
end)

spy.connections[#spy.connections + 1] = UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    local p = input.Position
    local hits = playerGui:GetGuiObjectsAtPosition(p.X, p.Y)
    local details = {}
    for i = 1, math.min(#hits, 5) do details[#details + 1] = guiDetail(hits[i]) end
    record("INPUT_DOWN", string.format("(%.0f,%.0f) %s", p.X, p.Y, table.concat(details, " | ")))
end)
spy.connections[#spy.connections + 1] = UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    record("INPUT_UP", string.format("(%.0f,%.0f)", input.Position.X, input.Position.Y))
end)
spy.connections[#spy.connections + 1] = ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
    if not who or who == player then
        record("PROMPT", pathOf(prompt) .. " action=" .. describe(prompt.ActionText))
    end
end)
spy.connections[#spy.connections + 1] = player.AttributeChanged:Connect(function(name)
    if relevant(name) then record("PLAYER_ATTRIBUTE", name .. "=" .. describe(player:GetAttribute(name))) end
end)

for _, inst in ipairs(playerGui:GetDescendants()) do watchGui(inst) end
spy.connections[#spy.connections + 1] = playerGui.DescendantAdded:Connect(watchGui)
for _, inst in ipairs(player:GetDescendants()) do watchValue(inst) end
spy.connections[#spy.connections + 1] = player.DescendantAdded:Connect(watchValue)
for _, inst in ipairs(ReplicatedStorage:GetDescendants()) do watchRemote(inst) end
spy.connections[#spy.connections + 1] = ReplicatedStorage.DescendantAdded:Connect(watchRemote)

local slot = env.DEVIL_OPEN_SEA_SPY_HOOK
if not slot and type(hookmetamethod) == "function" and type(getnamecallmethod) == "function" then
    slot = { spy = spy }
    local oldNamecall
    local wrap = type(newcclosure) == "function" and newcclosure or function(fn) return fn end
    local ok, old = pcall(function()
        return hookmetamethod(game, "__namecall", wrap(function(self, ...)
            local method = getnamecallmethod()
            local current = slot.spy
            if current and current.active and typeof(self) == "Instance"
                and (self:IsA("RemoteEvent") or self:IsA("RemoteFunction") or self:IsA("UnreliableRemoteEvent"))
                and (method == "FireServer" or method == "InvokeServer") then
                local arguments = table.pack(...)
                pcall(function()
                    current.record("REMOTE_OUT " .. method,
                        pathOf(self) .. " args=" .. argsText(table.unpack(arguments, 1, arguments.n)))
                end)
                if method == "InvokeServer" then
                    local result = table.pack(oldNamecall(self, ...))
                    pcall(function()
                        current.record("REMOTE_RETURN",
                            pathOf(self) .. " result=" .. argsText(table.unpack(result, 1, result.n)))
                    end)
                    return table.unpack(result, 1, result.n)
                end
            end
            return oldNamecall(self, ...)
        end))
    end)
    if ok then
        oldNamecall = old
        env.DEVIL_OPEN_SEA_SPY_HOOK = slot
        spy.hookInstalled = true
    else
        warn("[SeaSpy] Outgoing hook unavailable: " .. tostring(old))
    end
elseif slot then
    slot.spy = spy
    spy.hookInstalled = true
end

spy.startSnapshot = {}
snapshot(spy.startSnapshot, "AT START")
record("READY", "hook=" .. tostring(spy.hookInstalled))
print("[SeaSpy] Play one Open Sea charge and change carry 0/1 -> 0/6 manually, then type /seadump")
