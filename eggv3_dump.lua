-- EggWorld diagnostic for eggv3. Start it before field eggs appear, then use /dimp.

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local WS = game:GetService("Workspace")
local TextChatService = game:GetService("TextChatService")
local player = Players.LocalPlayer
local network = RS:WaitForChild("Packages", 10)
network = network and network:WaitForChild("Networking", 10)
if not network then
    warn("[EggV3Dump] Packages.Networking not found")
    return
end

local env = type(getgenv) == "function" and getgenv() or _G
if env.VANTA_EggV3Dump and type(env.VANTA_EggV3Dump.stop) == "function" then
    env.VANTA_EggV3Dump.stop()
end
local state = { active = true, connections = {}, started = os.date("%Y-%m-%d %H:%M:%S") }
env.VANTA_EggV3Dump = state
local events = {}
local remotes = {}
local captureSnapshots
local lastSnapshotAt = 0

local function describe(value, depth, seen)
    depth = depth or 0
    seen = seen or {}
    local kind = typeof(value)
    if kind == "Instance" then return "<" .. value.ClassName .. ": " .. value:GetFullName() .. ">" end
    if kind == "Vector3" then return string.format("Vector3(%.1f,%.1f,%.1f)", value.X, value.Y, value.Z) end
    if kind == "CFrame" then return describe(value.Position) end
    if kind == "string" then return string.format("%q", value:sub(1, 180)) end
    if kind ~= "table" then return tostring(value) end
    if seen[value] then return "<cycle>" end
    if depth >= 5 then return "{...}" end
    seen[value] = true
    local parts, count = {}, 0
    for key, item in pairs(value) do
        count = count + 1
        if count > 48 then table.insert(parts, "..."); break end
        table.insert(parts, "[" .. describe(key, depth + 1, seen) .. "]=" .. describe(item, depth + 1, seen))
    end
    seen[value] = nil
    return "{" .. table.concat(parts, ", ") .. "}"
end

local function arguments(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = describe(select(i, ...))
    end
    local joined = table.concat(parts, ", ")
    return #joined > 6000 and joined:sub(1, 6000) .. "..." or joined
end

local function log(kind, detail)
    if not state.active then return end
    detail = tostring(detail or "")
    if #detail > 6000 then detail = detail:sub(1, 6000) .. "..." end
    local line = string.format("[%s] %s %s", os.date("%H:%M:%S"), kind, detail)
    table.insert(events, line)
    if #events > 350 then table.remove(events, 1) end
    print("[EggV3Dump] " .. line:sub(1, 350))
end

local function watchRemote(remote)
    if remotes[remote] then return end
    if not (remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction")) then return end
    if not remote.Name:find("EggWorld", 1, true) and not remote.Name:find("EggCapture", 1, true) then return end
    remotes[remote] = true
    if remote:IsA("RemoteEvent") then
        table.insert(state.connections, remote.OnClientEvent:Connect(function(...)
            log("IN " .. remote.Name, arguments(...))
            if captureSnapshots and (remote.Name:find("FieldEggBatchShifted", 1, true)
                or remote.Name:find("FieldEggRaritiesShown", 1, true)
                or remote.Name:find("FieldEggShifted", 1, true))
                and os.clock() - lastSnapshotAt > 1.5 then
                lastSnapshotAt = os.clock()
                task.delay(0.4, function()
                    if state.active then captureSnapshots("AFTER " .. remote.Name) end
                end)
            end
        end))
    end
end

for _, remote in ipairs(network:GetChildren()) do watchRemote(remote) end
table.insert(state.connections, network.ChildAdded:Connect(watchRemote))

local hooked = false
if type(hookmetamethod) == "function" and type(getnamecallmethod) == "function" then
    local oldNamecall
    local wrap = type(newcclosure) == "function" and newcclosure or function(fn) return fn end
    local ok, result = pcall(function()
        return hookmetamethod(game, "__namecall", wrap(function(self, ...)
            if state.active and remotes[self] then
                local method = getnamecallmethod()
                if method == "FireServer" or method == "InvokeServer" then
                    log("OUT " .. self.Name, arguments(...))
                    if method == "InvokeServer" then
                        local values = table.pack(oldNamecall(self, ...))
                        log("RETURN " .. self.Name, arguments(table.unpack(values, 1, values.n)))
                        return table.unpack(values, 1, values.n)
                    end
                end
            end
            return oldNamecall(self, ...)
        end))
    end)
    if ok then oldNamecall = result; hooked = true else warn("[EggV3Dump] Hook failed:", result) end
end

local function worldSnapshot(lines)
    table.insert(lines, "--[[ EGG-LIKE WORKSPACE OBJECTS ]] ")
    local count = 0
    for _, inst in ipairs(WS:GetDescendants()) do
        local name = inst.Name:lower()
        if (inst:IsA("Model") or inst:IsA("BasePart"))
            and (name:find("egg", 1, true) or inst:GetAttribute("EggId") or inst:GetAttribute("EggType")) then
            count = count + 1
            if count <= 120 then
                local position = inst:IsA("BasePart") and inst.Position or inst:GetPivot().Position
                table.insert(lines, string.format("-- %s pos=%s attrs=%s", inst:GetFullName(), describe(position), describe(inst:GetAttributes())))
            end
        end
    end
    table.insert(lines, "-- Count: " .. count)
end

local function copyDump()
    local lines = { "-- EggWorld Diagnostic Dump", "-- Started: " .. state.started,
        "-- Copied: " .. os.date("%Y-%m-%d %H:%M:%S"), "-- Outgoing hook: " .. tostring(hooked), "" }
    worldSnapshot(lines)
    table.insert(lines, "")
    table.insert(lines, "--[[ EGGWORLD TIMELINE ]] ")
    for _, event in ipairs(events) do table.insert(lines, "-- " .. event) end
    if #events == 0 then table.insert(lines, "-- no events") end
    local dump = table.concat(lines, "\n")
    local clipboard = setclipboard or toclipboard or set_clipboard
    if type(clipboard) == "function" then
        local ok, err = pcall(clipboard, dump)
        if ok then log("COPIED", tostring(#dump) .. " bytes"); return end
        warn("[EggV3Dump] Clipboard failed:", err)
    end
    print(dump)
end

state.stop = function()
    if not state.active then return end
    state.active = false
    for _, connection in ipairs(state.connections) do connection:Disconnect() end
    if state.command then state.command:Destroy() end
    if env.EggV3DumpCopy == copyDump then env.EggV3DumpCopy = nil end
end
env.EggV3DumpCopy = copyDump

local lastCopy = 0
local function command(text)
    text = tostring(text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if text ~= "/dimp" and text ~= "/copy" then return end
    if os.clock() - lastCopy < 0.5 then return end
    lastCopy = os.clock()
    copyDump()
end
table.insert(state.connections, player.Chatted:Connect(command))
pcall(function()
    table.insert(state.connections, TextChatService.SendingMessage:Connect(function(message)
        command(message.Text)
    end))
end)
pcall(function()
    local chatCommand = Instance.new("TextChatCommand")
    chatCommand.Name = "EggV3DumpCommand"
    chatCommand.PrimaryAlias = "/dimp"
    chatCommand.Parent = TextChatService
    state.command = chatCommand
    table.insert(state.connections, chatCommand.Triggered:Connect(function() command("/dimp") end))
end)

captureSnapshots = function(tag)
    for _, name in ipairs({ "RF/EggWorld/AskFieldEggSnapshot", "RF/EggWorld/AskLiveSnapshot" }) do
        local remote = network:FindFirstChild(name)
        if remote and remote:IsA("RemoteFunction") then
            task.spawn(function()
                local ok, result = pcall(function() return remote:InvokeServer() end)
                log(tag .. " " .. name, "ok=" .. tostring(ok) .. " result=" .. describe(result))
            end)
        end
    end
end
captureSnapshots("INITIAL")

log("READY", "Wait for field eggs, manually pick one, then use /dimp. Outgoing hook=" .. tostring(hooked))
