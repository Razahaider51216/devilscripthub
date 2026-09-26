local url = "https://raw.githubusercontent.com/Razahaider51216/devilscripthub/5f427b74208186af5042ccc3367b7b6c5c44a8db/eggv3.lua"
local player = game:GetService("Players").LocalPlayer
local playerGui = player and player:WaitForChild("PlayerGui", 10)
local screen, label

if playerGui then
    local previous = playerGui:FindFirstChild("VANTA_EggV3LoaderStatus")
    if previous then previous:Destroy() end
    screen = Instance.new("ScreenGui")
    screen.Name = "VANTA_EggV3LoaderStatus"
    screen.ResetOnSpawn = false
    screen.IgnoreGuiInset = true
    screen.DisplayOrder = 1000
    screen.Parent = playerGui

    label = Instance.new("TextLabel")
    label.Size = UDim2.fromOffset(380, 42)
    label.AnchorPoint = Vector2.new(0.5, 0)
    label.Position = UDim2.new(0.5, 0, 0, 16)
    label.BackgroundColor3 = Color3.fromRGB(22, 24, 28)
    label.TextColor3 = Color3.fromRGB(255, 255, 255)
    label.TextSize = 14
    label.Font = Enum.Font.GothamBold
    label.Parent = screen
    Instance.new("UICorner", label).CornerRadius = UDim.new(0, 6)
end

local function report(message)
    warn("[VANTA V3 Loader] " .. message)
    if label then
        label.Text = "VANTA V3: " .. message:sub(1, 42) .. (#message > 42 and "..." or "")
    end
end

report("downloading...")
local fetched, source = pcall(function()
    return game:HttpGet(url .. "?v=" .. tostring(os.time()))
end)
if not fetched then report("download failed: " .. tostring(source)); return end
if type(source) ~= "string" or not source:find("VANTA Egg Collector V3", 1, true) then
    report("unexpected response from GitHub")
    return
end

report("compiling...")
local compiled, scriptFunction, compileError = pcall(loadstring, source)
if not compiled or not scriptFunction then
    report("compile failed: " .. tostring(compileError or scriptFunction))
    return
end

report("starting GUI...")
local ran, runtimeError = pcall(scriptFunction)
if not ran then report("runtime failed: " .. tostring(runtimeError)); return end
if not playerGui or not playerGui:FindFirstChild("VANTA_EggCollectorV3") then
    report("script returned without creating GUI")
    return
end

report("ready")
if screen then screen:Destroy() end
