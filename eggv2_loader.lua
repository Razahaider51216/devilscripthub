local url = "https://raw.githubusercontent.com/Razahaider51216/devilscripthub/main/eggv2.lua"
warn("[VANTA V2 Loader] Downloading " .. url)

local fetched, source = pcall(function()
    return game:HttpGet(url .. "?v=" .. tostring(os.time()))
end)
if not fetched then
    error("[VANTA V2 Loader] Download failed: " .. tostring(source))
end
if type(source) ~= "string" or not source:find("VANTA Egg Collector v2", 1, true) then
    error("[VANTA V2 Loader] Unexpected response from GitHub")
end

local scriptFunction, compileError = loadstring(source)
if not scriptFunction then
    error("[VANTA V2 Loader] Compile failed: " .. tostring(compileError))
end

local ran, runtimeError = pcall(scriptFunction)
if not ran then
    error("[VANTA V2 Loader] Runtime failed: " .. tostring(runtimeError))
end
