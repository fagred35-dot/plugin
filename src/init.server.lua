-- GitHub Sync Plugin Entry Point
local pluginInstance = plugin

if not pluginInstance then
    return
end

local UI = require(script.Parent.UI)
UI.Init(pluginInstance)

print("[GitHubSync] Plugin initialized successfully.")
