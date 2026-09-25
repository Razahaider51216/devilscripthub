local url = "https://raw.githubusercontent.com/Razahaider51216/devilscripthub/508a369afe97984f2fdfb8501ac15d85efe448ef/eggv2.lua"
local player = game:GetService("Players").LocalPlayer
local playerGui = player and player:WaitForChild("PlayerGui", 10)
local statusLabel
if playerGui then
    local oldStatus = playerGui:FindFirstChild("VANTA_LoaderStatus")
    if oldStatus then oldStatus:Destroy() end
    local screen = Instance.new("ScreenGui")
    screen.Name = "VANTA_LoaderStatus"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.DisplayOrder = 1001
    screen.Parent = playerGui

    statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.fromOffset(380, 42)
    statusLabel.AnchorPoint = Vector2.new(0.5, 0)
    statusLabel.Position = UDim2.new(0.5, 0, 0, 16)
    statusLabel.BackgroundColor3 = Color3.fromRGB(22, 24, 28)
    statusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    statusLabel.TextSize = 14
    statusLabel.Font = Enum.Font.GothamBold
    statusLabel.Text = "VANTA: downloading..."
    statusLabel.Parent = screen
    Instance.new("UICorner", statusLabel).CornerRadius = UDim.new(0, 6)
end

local function report(message)
    warn("[VANTA V2 Loader] " .. message)
    if statusLabel then
        statusLabel.Text = "VANTA: " .. message:sub(1, 42) .. (#message > 42 and "..." or "")
    end
end

report("downloading...")

local fetched, source = pcall(function()
    return game:HttpGet(url .. "?v=" .. tostring(os.time()))
end)
if not fetched then
    report("download failed: " .. tostring(source))
    return
end
if type(source) ~= "string" or not source:find("VANTA Egg Collector v2", 1, true) then
    report("unexpected response from GitHub")
    return
end

report("compiling...")
local compileOk, scriptFunction, compileError = pcall(loadstring, source)
if not compileOk then
    report("loadstring unavailable: " .. tostring(scriptFunction))
    return
end
if not scriptFunction then
    report("compile failed: " .. tostring(compileError))
    return
end

report("starting GUI...")
local ran, runtimeError = pcall(scriptFunction)
if not ran then
    report("runtime failed: " .. tostring(runtimeError))
    return
end

if not playerGui or not playerGui:FindFirstChild("VANTA_EggCollectorV2") then
    report("script returned without creating GUI")
    return
end

report("ready")
if statusLabel then statusLabel.Parent:Destroy() end
