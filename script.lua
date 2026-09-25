-- Training x2 diagnostic. Run before the bonus appears, then use /dimp.

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local playerGui = player and player:WaitForChild("PlayerGui", 10)
if not playerGui then
    warn("[TrainingDump] PlayerGui not found")
    return
end

local executorEnv = type(getgenv) == "function" and getgenv() or nil
local runtimeEnv = type(executorEnv) == "table" and executorEnv or _G
local previous = runtimeEnv.VANTA_TrainingDump_Runtime or runtimeEnv.VANTA_EventDump_Runtime
if previous and type(previous.stop) == "function" then pcall(previous.stop) end

local runtime = { active = true, connections = {}, command = nil }
runtimeEnv.VANTA_TrainingDump_Runtime = runtime
local startedAt = os.date("%Y-%m-%d %H:%M:%S")
local events = {}
local trackedButtons = {}
local trackedRemotes = {}
local incomingConnections = {}
local MAX_EVENTS = 260

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
    if kind == "Vector3" then return string.format("Vector3(%.1f,%.1f,%.1f)", value.X, value.Y, value.Z) end
    if kind == "CFrame" then
        local p = value.Position
        return string.format("CFrame(%.1f,%.1f,%.1f)", p.X, p.Y, p.Z)
    end
    if kind == "string" then return string.format("%q", value:sub(1, 200)) end
    if kind == "table" then
        if seen[value] then return "<cycle>" end
        if depth >= 3 then return "{...}" end
        seen[value] = true
        local entries, count = {}, 0
        for key, item in pairs(value) do
            count = count + 1
            if count > 18 then table.insert(entries, "..."); break end
            table.insert(entries, tostring(key) .. "=" .. valueText(item, depth + 1, seen))
        end
        seen[value] = nil
        return "{" .. table.concat(entries, ",") .. "}"
    end
    return tostring(value)
end

local function argsText(...)
    local out = {}
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        out[i] = valueText(value)
    end
    local text = table.concat(out, ", ")
    return #text > 3000 and text:sub(1, 3000) .. "..." or text
end

local function log(kind, detail)
    if not runtime.active then return end
    local line = string.format("[%s] %s %s", os.date("%H:%M:%S"), kind, detail or "")
    table.insert(events, line)
    if #events > MAX_EVENTS then table.remove(events, 1) end
    print("[TrainingDump] " .. line:sub(1, 450))
end

local function visibleOnScreen(obj)
    local node = obj
    while node and node ~= playerGui do
        if node:IsA("GuiObject") and not node.Visible then return false end
        if node:IsA("ScreenGui") and not node.Enabled then return false end
        node = node.Parent
    end
    return obj:IsDescendantOf(playerGui)
end

local function guiText(obj)
    local pieces = { obj.Name }
    if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
        table.insert(pieces, obj.Text)
    end
    if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
        table.insert(pieces, obj.Image)
    end
    local count = 0
    for _, child in ipairs(obj:GetDescendants()) do
        if child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox") then
            table.insert(pieces, child.Text)
            count = count + 1
        elseif child:IsA("ImageLabel") or child:IsA("ImageButton") then
            table.insert(pieces, child.Image)
            count = count + 1
        end
        if count >= 12 then break end
    end
    return table.concat(pieces, " "):sub(1, 360)
end

local function bonusSignal(text)
    text = text:lower()
    return text:find("x2", 1, true) ~= nil
        or text:find("2x", 1, true) ~= nil
        or text:find("train", 1, true) ~= nil
        or text:find("bonus", 1, true) ~= nil
        or text:find("multiplier", 1, true) ~= nil
end

local function buttonDetail(button)
    local pos, size = button.AbsolutePosition, button.AbsoluteSize
    return string.format("%s | visible=%s pos=(%.0f,%.0f) size=(%.0f,%.0f) text=%s",
        pathOf(button), tostring(visibleOnScreen(button)), pos.X, pos.Y, size.X, size.Y,
        valueText(guiText(button)))
end

local function watchButton(button, announce)
    if trackedButtons[button] then return end
    local state = { connections = {}, lastVisible = false, lastPos = nil }
    trackedButtons[button] = state
    table.insert(state.connections, button.Activated:Connect(function()
        log("BUTTON_ACTIVATED", buttonDetail(button))
    end))
    table.insert(state.connections, button.AncestryChanged:Connect(function()
        if not button:IsDescendantOf(playerGui) then
            if state.lastVisible and bonusSignal(guiText(button)) then
                log("BONUS_REMOVED", pathOf(button))
            end
            for _, connection in ipairs(state.connections) do connection:Disconnect() end
            trackedButtons[button] = nil
        end
    end))
    if announce then log("BUTTON_ADDED", buttonDetail(button)) end
end

local function relevantRemote(inst)
    if not (inst:IsA("RemoteEvent") or inst:IsA("RemoteFunction")
        or inst:IsA("BindableEvent") or inst:IsA("BindableFunction")) then return false end
    local path = pathOf(inst):lower()
    return path:find("trainingservice", 1, true) ~= nil
        or path:find("spawnbonus", 1, true) ~= nil
        or path:find("claimbonus", 1, true) ~= nil
        or path:find("trainingbonus", 1, true) ~= nil
end

local function watchRemote(inst)
    if not relevantRemote(inst) or trackedRemotes[inst] then return end
    trackedRemotes[inst] = true
    log("REMOTE_FOUND", inst.ClassName .. " " .. pathOf(inst))
    if inst:IsA("RemoteEvent") or inst:IsA("BindableEvent") then
        local ok, connection = pcall(function()
            local signal = inst:IsA("RemoteEvent") and inst.OnClientEvent or inst.Event
            return signal:Connect(function(...)
                log("REMOTE_IN", pathOf(inst) .. " args=" .. argsText(...))
            end)
        end)
        if ok then incomingConnections[inst] = connection end
    end
end

local function scan()
    for _, inst in ipairs(playerGui:GetDescendants()) do
        if inst:IsA("GuiButton") then watchButton(inst, false) end
    end
    for _, inst in ipairs(game:GetDescendants()) do
        if relevantRemote(inst) then watchRemote(inst) end
    end
end

local function snapshot(lines)
    table.insert(lines, "--[[ TRAINING UI SNAPSHOT ]]")
    local buttons, bonusTexts = {}, {}
    for button in pairs(trackedButtons) do
        if button.Parent and visibleOnScreen(button) then
            table.insert(buttons, { button = button, priority = bonusSignal(guiText(button)) and 1 or 0 })
        end
    end
    table.sort(buttons, function(a, b)
        if a.priority ~= b.priority then return a.priority > b.priority end
        return pathOf(a.button) < pathOf(b.button)
    end)
    table.insert(lines, string.format("-- Visible buttons: %d (showing up to 100)", #buttons))
    for i = 1, math.min(#buttons, 100) do
        table.insert(lines, "-- BUTTON " .. buttonDetail(buttons[i].button))
    end
    for _, inst in ipairs(playerGui:GetDescendants()) do
        if (inst:IsA("TextLabel") or inst:IsA("ImageLabel")) and visibleOnScreen(inst)
            and bonusSignal(guiText(inst)) then
            local p = inst.AbsolutePosition
            table.insert(bonusTexts, string.format("%s pos=(%.0f,%.0f) text=%s",
                pathOf(inst), p.X, p.Y, valueText(guiText(inst))))
        end
    end
    table.insert(lines, string.format("-- Bonus labels/images: %d (showing up to 60)", #bonusTexts))
    for i = 1, math.min(#bonusTexts, 60) do table.insert(lines, "-- BONUS_UI " .. bonusTexts[i]) end

    table.insert(lines, "")
    table.insert(lines, "--[[ TRAINING REMOTES ]]")
    local remotePaths = {}
    for remote in pairs(trackedRemotes) do
        if remote.Parent then table.insert(remotePaths, remote.ClassName .. " " .. pathOf(remote)) end
    end
    table.sort(remotePaths)
    for _, path in ipairs(remotePaths) do table.insert(lines, "-- " .. path) end
    if #remotePaths == 0 then table.insert(lines, "-- none found") end
end

local function makeDump()
    scan()
    local lines = {
        "-- Training x2 Diagnostic Dump",
        "-- Started: " .. startedAt,
        "-- Copied: " .. os.date("%Y-%m-%d %H:%M:%S"),
        "-- PlayerGui: " .. pathOf(playerGui),
        "",
    }
    snapshot(lines)
    table.insert(lines, "")
    table.insert(lines, "--[[ TIMELINE (oldest first) ]]")
    if #events == 0 then table.insert(lines, "-- no events captured") end
    for _, event in ipairs(events) do table.insert(lines, "-- " .. event) end
    return table.concat(lines, "\n")
end

local function copyDump()
    local dump = makeDump()
    local clipboard = setclipboard or toclipboard or set_clipboard
    if type(clipboard) ~= "function" then
        warn("[TrainingDump] Clipboard unavailable; printing dump")
        print(dump)
        return
    end
    local ok, err = pcall(clipboard, dump)
    if ok then
        print(string.format("[TrainingDump] Copied %d bytes, %d events", #dump, #events))
    else
        warn("[TrainingDump] Clipboard failed:", err)
        print(dump)
    end
end

runtimeEnv.TrainingDumpCopy = copyDump
runtime.stop = function()
    if not runtime.active then return end
    runtime.active = false
    for _, connection in ipairs(runtime.connections) do connection:Disconnect() end
    for _, state in pairs(trackedButtons) do
        for _, connection in ipairs(state.connections) do connection:Disconnect() end
    end
    for _, connection in pairs(incomingConnections) do connection:Disconnect() end
    if runtime.command then runtime.command:Destroy() end
    if runtimeEnv.TrainingDumpCopy == copyDump then runtimeEnv.TrainingDumpCopy = nil end
end

local lastCommand, lastCommandAt = "", 0
local function handleCommand(message)
    message = tostring(message or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if message == lastCommand and os.clock() - lastCommandAt < 0.5 then return end
    lastCommand, lastCommandAt = message, os.clock()
    if message == "/dimp" or message == "/dump" or message == "/copy" then
        copyDump()
    elseif message == "/clear" then
        table.clear(events)
        print("[TrainingDump] Timeline cleared")
    elseif message == "/rescan" then
        scan()
        print("[TrainingDump] Rescan done")
    end
end

table.insert(runtime.connections, player.Chatted:Connect(handleCommand))
pcall(function()
    table.insert(runtime.connections, TextChatService.SendingMessage:Connect(function(message)
        if message and message.Text then handleCommand(message.Text) end
    end))
end)
pcall(function()
    local command = Instance.new("TextChatCommand")
    command.Name = "TrainingDumpCommand"
    command.PrimaryAlias = "/dimp"
    command.Parent = TextChatService
    runtime.command = command
    table.insert(runtime.connections, command.Triggered:Connect(function()
        handleCommand("/dimp")
    end))
end)

table.insert(runtime.connections, playerGui.DescendantAdded:Connect(function(inst)
    if inst:IsA("GuiButton") then
        task.defer(function()
            if runtime.active and inst.Parent then watchButton(inst, true) end
        end)
    elseif inst:IsA("TextLabel") or inst:IsA("ImageLabel") then
        task.delay(0.1, function()
            if runtime.active and inst.Parent and bonusSignal(guiText(inst)) then
                local p = inst.AbsolutePosition
                log("BONUS_UI_ADDED", string.format("%s pos=(%.0f,%.0f) text=%s",
                    pathOf(inst), p.X, p.Y, valueText(guiText(inst))))
            end
        end)
    end
end))

table.insert(runtime.connections, game.DescendantAdded:Connect(function(inst)
    if relevantRemote(inst) then watchRemote(inst) end
end))

table.insert(runtime.connections, UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then return end
    local p = input.Position
    local hitText = {}
    local ok, hits = pcall(function()
        return playerGui:GetGuiObjectsAtPosition(p.X, p.Y)
    end)
    if ok then
        for i = 1, math.min(#hits, 5) do
            table.insert(hitText, pathOf(hits[i]) .. " text=" .. valueText(guiText(hits[i])))
        end
    end
    log("SCREEN_TAP", string.format("(%.0f,%.0f) hits={%s}", p.X, p.Y, table.concat(hitText, "; ")))
end))

local outgoingHookInstalled = false
if type(hookmetamethod) == "function" and type(getnamecallmethod) == "function" then
    local oldNamecall
    local wrap = type(newcclosure) == "function" and newcclosure or function(fn) return fn end
    local ok, result = pcall(function()
        return hookmetamethod(game, "__namecall", wrap(function(self, ...)
            if runtime.active and trackedRemotes[self] then
                local method = getnamecallmethod()
                if method == "FireServer" or method == "InvokeServer"
                    or method == "Fire" or method == "Invoke" then
                    log("REMOTE_OUT", method .. " " .. pathOf(self) .. " args=" .. argsText(...))
                end
            end
            return oldNamecall(self, ...)
        end))
    end)
    if ok then
        oldNamecall = result
        outgoingHookInstalled = true
    else
        warn("[TrainingDump] Outgoing remote hook failed:", result)
    end
end

task.spawn(function()
    while runtime.active do
        for button, state in pairs(trackedButtons) do
            if button.Parent then
                local isBonus = bonusSignal(guiText(button))
                local visible = isBonus and visibleOnScreen(button)
                local pos = button.AbsolutePosition
                if visible and not state.lastVisible then
                    log("BONUS_VISIBLE", buttonDetail(button))
                elseif visible and state.lastPos and (pos - state.lastPos).Magnitude >= 25 then
                    log("BONUS_MOVED", buttonDetail(button))
                elseif state.lastVisible and not visible then
                    log("BONUS_HIDDEN", pathOf(button))
                end
                state.lastVisible = visible
                state.lastPos = pos
            end
        end
        task.wait(0.35)
    end
end)

scan()
log("READY", "Training x2 dump active; outgoing hook=" .. tostring(outgoingHookInstalled))
print("[TrainingDump] Run before x2 appears. Use /dimp after tapping x2.")
